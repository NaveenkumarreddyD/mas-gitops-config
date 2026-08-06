# Manage 8.7.24 attachments on PowerScale S3

This is the source of truth for migrating Maximo Manage 8.7.24 attachments from
PowerScale NFS to PowerScale S3. PowerScale provisioning is documented in
[PowerScale S3 setup](./powerscale-s3-onefs-setup.md).

## Supported configuration for 8.7.24

IBM GitOps 8.4.0 passes `mas_appws_spec` directly into the `ManageWorkspace`
custom resource. It does not translate attachment settings into Maximo system
properties.

The installed CRD accepts
`spec.settings.db.attachmentProvider.s3.providerCredentials.s3Url`, but on the
tested Manage 8.7.24 deployment the operator did not materialize that block into
the server bundles. A successful `ManageWorkspace` reconciliation therefore does
not prove that S3 attachment storage is active.

For Manage 8.7.24, configure S3 with the nine IBM-documented Maximo system
properties. The GitOps template deliberately does not render the nonfunctional
S3 `attachmentProvider` block or the related Kubernetes Secret.

## GitOps modes

Set one mode in the target environment file:

| `MANAGE_ATTACHMENT_PROVIDER` | GitOps behavior |
|---|---|
| `filestorage` | Configure the file provider and mount `/doclinks` |
| `s3-migration` | Import PowerScale CAs and keep `/doclinks` mounted |
| `s3` | Import PowerScale CAs without mounting the legacy `/doclinks` PVC |

The filesystem modes also support:

```text
MANAGE_DOCLINKS_PATH=/doclinks
MANAGE_DOCLINKS_SIZE=100Gi
```

Use `s3-migration` until conversion, validation, and the rollback window are
complete. Changing to `s3` removes the mount from the Manage pod specification;
it does not delete the PVC or its data.

## Vault contract

Keep the PowerScale values at:

```text
secret/<account>/<cluster>/<instance>/manage-cos
```

| Vault field | Use |
|---|---|
| `endpoint` | `mxe.cosendpointuri` |
| `bucket` | `mxe.cosbucketname` |
| `access_key` | `mxe.cosaccesskey` |
| `secret_key` | `mxe.cossecretkey` |
| `powerscale_s3_subca` | Manage imported certificate |
| `powerscale_s3_rootca` | Manage imported certificate |

Argo CD Vault Plugin resolves only the two CA certificates into
`settings.deployment.importedCerts`. Until an approved external-secrets or API
integration is available, enter the four S3 connection values manually in
Manage. Do not commit them to Git or place them in `bundleLevelProperties`.

## Required Manage properties

In Manage, open **System Configuration > Platform Configuration > System
Properties**. Set the global values below and save them. Use the Manage UI or API
for the credential properties so Maximo handles their encrypted values; do not
update them with raw SQL.

| Property | Value |
|---|---|
| `mxe.attachmentstorage` | `com.ibm.tivoli.maximo.oslc.provider.COSAttachmentStorage` |
| `mxe.cosendpointuri` | PowerScale HTTPS S3 endpoint, including port `9021` |
| `mxe.cosbucketname` | PowerScale bucket name |
| `mxe.cosaccesskey` | PowerScale access key |
| `mxe.cossecretkey` | PowerScale secret key |
| `mxe.doclink.securedAttachment` | `true` |
| `mxe.doclink.doctypes.defpath` | `cos:doclinks/default` |
| `mxe.doclink.doctypes.topLevelPaths` | `cos:doclinks` |
| `mxe.doclink.path01` | `cos:doclinks=https://<manage-ui-route>/maximo/oslc/cosdoclink` |

If converted objects keep nested directory names, also test whether the 8.7.24
environment requires `mxe.cosnestedfile=1` before using it in production.

Restart every Manage server bundle after saving the properties unless each
property is confirmed to support Live Refresh.

## Deployment procedure

### 1. Prepare and baseline

1. Complete the [PowerScale S3 setup](./powerscale-s3-onefs-setup.md).
2. Confirm all six Vault fields exist.
3. Create a known set of NFS-backed test attachments and record their database
   IDs, record types, filenames, sizes, and checksums.
4. Take a coordinated database backup and `/doclinks` snapshot.

### 2. Retain NFS and import the S3 CA chain

Set and render:

```text
MANAGE_ATTACHMENT_PROVIDER=s3-migration
```

Commit the rendered configuration and let Argo CD synchronize it. Verify that
the legacy PVC remains mounted and the CA entries are present:

```bash
export INSTANCE_ID=drgitopsapp
export WORKSPACE_ID=drgitopswks
export MANAGE_NS=mas-${INSTANCE_ID}-manage
export MANAGEWORKSPACE=${INSTANCE_ID}-${WORKSPACE_ID}

oc get manageworkspace "$MANAGEWORKSPACE" -n "$MANAGE_NS" \
  -o jsonpath='{.spec.settings.deployment.importedCerts[*].alias}{"\n"}'

oc get manageworkspace "$MANAGEWORKSPACE" -n "$MANAGE_NS" \
  -o jsonpath='{range .spec.settings.deployment.persistentVolumes[*]}{.pvcName}{" -> "}{.mountPath}{"\n"}{end}'
```

### 3. Configure and verify the runtime properties

Set the nine properties in Manage, restart all server bundles, then verify the
stored non-secret values in Oracle:

```sql
SELECT propname,
       CASE
         WHEN LOWER(propname) IN ('mxe.cosaccesskey', 'mxe.cossecretkey')
           THEN CASE WHEN propvalue IS NULL THEN '<missing>' ELSE '<configured>' END
         ELSE propvalue
       END AS propvalue,
       servername
FROM maximo.maxpropvalue
WHERE LOWER(propname) IN (
  'mxe.attachmentstorage',
  'mxe.cosendpointuri',
  'mxe.cosbucketname',
  'mxe.cosaccesskey',
  'mxe.cossecretkey',
  'mxe.doclink.securedattachment',
  'mxe.doclink.doctypes.defpath',
  'mxe.doclink.doctypes.toplevelpaths',
  'mxe.doclink.path01'
)
ORDER BY propname, servername;
```

Also confirm the S3 endpoint is trusted from a running Manage server-bundle pod:

```bash
export MANAGE_POD=<ui-or-cron-server-bundle-pod>
oc exec -n "$MANAGE_NS" "$MANAGE_POD" -- bash -c \
  "echo | openssl s_client -connect bhm-pwrsclnfs.lac1.biz:9021 \
  -servername dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz 2>/dev/null \
  | grep -i 'verify return code'"
```

Expected TLS result: `0 (ok)`.

### 4. Migrate and validate

Use IBM's supported `file2s3.sh` conversion tool from a Manage admin or maxinst
pod that can still access `/doclinks`. Copying files directly into the bucket is
not sufficient because the database metadata and S3 object keys must agree.

After conversion:

1. Compare source file count and total size with the converted object set.
2. Compare checksums for the recorded test files.
3. Open migrated attachments from Work Orders, Assets, and Locations.
4. Upload, download, and delete new S3-backed attachments.
5. Review all server-bundle logs for S3, TLS, integrity, and authorization errors.

### 5. Complete the migration

After acceptance and the rollback window, set:

```text
MANAGE_ATTACHMENT_PROVIDER=s3
```

Render, commit, and synchronize. Confirm `/doclinks` is no longer mounted before
scheduling the old PVC for separate retention and removal. Do not delete the NFS
data in the same change that removes the mount.

## Verify the nonfunctional 8.7.24 CR field is absent

The following command prints the stored `s3Url` only when the block that is
nonfunctional in this 8.7.24 deployment is still present:

```bash
oc get manageworkspace "$MANAGEWORKSPACE" -n "$MANAGE_NS" \
  -o jsonpath='{.spec.settings.db.attachmentProvider.s3.providerCredentials.s3Url}{"\n"}'
```

After the corrected GitOps manifest synchronizes, this command should print a
blank line for S3 modes. For file storage, `attachmentProvider.filestorage`
remains valid.

To inspect what the installed CRD accepts:

```bash
oc explain manageworkspace.spec.settings.db.attachmentProvider.s3.providerCredentials \
  --api-version=apps.mas.ibm.com/v1
```

Schema acceptance alone is not runtime verification. Confirm the nine system
properties and complete an upload/download test.

## References

- [IBM: S3 attachment properties](https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd?topic=properties-attachment-s3)
- [IBM: Convert file-based storage to S3](https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd?topic=storage-converting-file-based-s3)
- [IBM MAS DevOps: Manage attachment configuration](https://ibm-mas.github.io/ansible-devops/roles/suite_manage_attachments_config/)
- [PowerScale S3 setup](./powerscale-s3-onefs-setup.md)
