# Manage attachments on PowerScale S3

This is the source of truth for the MAS and GitOps side of Maximo Manage
attachments on Dell PowerScale S3. PowerScale provisioning is documented in
[PowerScale S3 setup](./powerscale-s3-onefs-setup.md).

## Ownership

| Area | Owner |
|---|---|
| Bucket, S3 user, ACLs, DNS, TLS endpoint, ETag behavior | PowerScale/storage team |
| Vault values, GitOps configuration, ManageWorkspace, migration, validation | MAS/platform team |
| Coordinated database and attachment backup/restore | Both teams |

The MAS `ObjectStorageCfg` resource does not configure Manage attachments. The
attachment provider is owned by
`ManageWorkspace.spec.settings.db.attachmentProvider`.

## GitOps configuration

Set one attachment mode in the environment file:

| `MANAGE_ATTACHMENT_PROVIDER` | Provider | `/doclinks` PVC |
|---|---|---|
| `filestorage` | File storage | Mounted |
| `s3-migration` | S3 | Retained for migration validation and rollback |
| `s3` | S3 | Not mounted |

The filesystem modes also support:

```text
MANAGE_DOCLINKS_PATH=/doclinks
MANAGE_DOCLINKS_SIZE=100Gi
```

For S3 modes, the renderer creates this provider configuration:

```yaml
attachmentProvider:
  providerSourceType: s3
  s3:
    providerCredentials:
      s3Url: "<Vault endpoint>"
      bucketName: "<Vault bucket>"
      accessKey: "<Vault access_key>"
      secretKey:
        secretName: <workspace>-manage-s3-secret
```

The installed Manage CRD requires `providerCredentials.s3Url`. It rejects the
older `cosAwsUrl` field shown in some IBM documentation.

## Vault contract

Create the following Vault entry once:

```text
secret/<account>/<cluster>/<instance>/manage-cos
```

| Field | Content |
|---|---|
| `endpoint` | PowerScale HTTPS S3 endpoint, including port 9021 |
| `bucket` | Existing PowerScale bucket name |
| `access_key` | PowerScale S3 access key |
| `secret_key` | PowerScale S3 secret key |
| `powerscale_s3_subca` | SubCA certificate in PEM format |
| `powerscale_s3_rootca` | Root CA certificate in PEM format |

Argo CD Vault Plugin resolves the endpoint, bucket, access key, and certificates
during rendering. The current deployment does not create the Kubernetes Secret.
Create `<workspace>-manage-s3-secret` manually from the Vault `secret_key` value
before synchronizing the `ManageWorkspace`. Do not commit the credential.

## Deployment procedure

### 1. Complete the prerequisites

- Complete the [PowerScale S3 setup](./powerscale-s3-onefs-setup.md).
- Confirm the Vault entry contains all six required fields.
- Create the required Kubernetes Secret as described below.
- Confirm `mxe.doclink.securedAttachment` is `true` in Manage.
- Create a known set of file-storage attachments and record their database IDs,
  object types, filenames, sizes, and checksums.
- Take a database backup and a coordinated snapshot of the `/doclinks` volume.

### 2. Create the S3 Secret

Read the `secret_key` value from Vault, then enter it without placing it in shell
history:

```bash
read -s -p "PowerScale S3 secret key: " S3_SECRET_KEY
echo

oc create secret generic drgitopswks-manage-s3-secret \
  -n mas-drgitopsapp-manage \
  --from-literal=accessSecretKey="$S3_SECRET_KEY" \
  --dry-run=client -o yaml | oc apply -f -

unset S3_SECRET_KEY
```

The name, namespace, and data key must exactly match the `ManageWorkspace`
reference. The Secret is intentionally maintained outside Argo CD until an
external-secrets controller is available.

### 3. Enable migration mode

```text
MANAGE_ATTACHMENT_PROVIDER=s3-migration
```

Render the environment, review the generated `ManageWorkspace`, commit it, and
allow Argo CD to synchronize. Migration mode makes S3 the configured provider
while retaining the legacy PVC for the controlled conversion and rollback
window.

### 4. Verify the generated resources

Set the values for the target workspace:

```bash
export INSTANCE_ID=drgitopsapp
export WORKSPACE_ID=drgitopswks
export MANAGE_NS=mas-${INSTANCE_ID}-manage
export MANAGEWORKSPACE=${INSTANCE_ID}-${WORKSPACE_ID}
export S3_SECRET=${WORKSPACE_ID}-manage-s3-secret
```

Confirm the provider configuration:

```bash
oc get manageworkspace "$MANAGEWORKSPACE" -n "$MANAGE_NS" \
  -o jsonpath='{.spec.settings.db.attachmentProvider}{"\n"}'
```

Confirm the S3 secret exists without printing it:

```bash
oc get secret "$S3_SECRET" -n "$MANAGE_NS" \
  -o jsonpath='{.data.accessSecretKey}' | wc -c
```

Confirm the workspace reconciles successfully:

```bash
oc get manageworkspace "$MANAGEWORKSPACE" -n "$MANAGE_NS" \
  -o jsonpath='{range .status.conditions[*]}{.type}{"="}{.status}{"  "}{.message}{"\n"}{end}'
```

### 5. Verify TLS from Manage

The S3 modes import the Vault SubCA and Root CA through
`spec.settings.deployment.importedCerts`. From a running server-bundle pod:

```bash
export MANAGE_POD=<ui-or-cron-server-bundle-pod>
oc exec -n "$MANAGE_NS" "$MANAGE_POD" -- bash -c \
  "echo | openssl s_client -connect bhm-pwrsclnfs.lac1.biz:9021 \
  -servername dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz 2>/dev/null \
  | grep -i 'verify return code'"
```

The expected result is `0 (ok)`.

### 6. Migrate and validate

Use IBM's supported file-to-S3 conversion process. Copying files directly to the
bucket is not sufficient by itself because the database metadata and S3 object
keys must remain consistent.

After conversion:

1. Compare source file count and total size with the converted object set.
2. Compare checksums for the recorded test files.
3. Open existing attachments from Work Orders, Assets, and Locations.
4. Upload, download, and delete new attachments.
5. Test from each server-bundle type that handles attachment requests.
6. Review server-bundle logs for S3, TLS, integrity, and authorization errors.

If migrated objects retain nested folder paths such as `attachments/` or
`diagrams/`, verify whether `mxe.cosnestedfile=1` is required for the installed
Manage version.

### 7. Complete the migration

After the acceptance checks and rollback window are complete:

```text
MANAGE_ATTACHMENT_PROVIDER=s3
```

Render, commit, and synchronize again. Confirm the legacy `/doclinks` PVC is no
longer mounted before scheduling its separate retention and removal process.
Do not delete the old data as part of the same change that enables S3.

## Runtime properties

The Manage operator derives the provider properties from the custom resource and
adds them to the server-bundle configuration. They might not appear as newly
updated rows in `MAXPROPVALUE`.

| Property | Source |
|---|---|
| `mxe.attachmentstorage` | `providerSourceType: s3` |
| `mxe.cosendpointuri` | Vault `endpoint` through `s3Url` |
| `mxe.cosbucketname` | Vault `bucket` |
| `mxe.cosaccesskey` | Vault `access_key` |
| `mxe.cossecretkey` | Kubernetes Secret `accessSecretKey` |
| `mxe.doclink.securedAttachment` | Verify separately; it must be `true` |

The provider custom resource does not update the `DOCTYPES` table. Validate the
existing document folder paths as part of migration testing.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| CRD reports `providerCredentials.s3Url: Required value` | Template uses unsupported `cosAwsUrl` | Render `s3Url` |
| ManageWorkspace reports that the S3 Secret is missing | Secret was not created in the Manage namespace, or its name/key does not match | Create `<workspace>-manage-s3-secret` with key `accessSecretKey` |
| TLS error names `<bucket>.<endpoint>` | Missing CA trust or wildcard SAN | Import the CA chain and add `*.<endpoint>` to the endpoint certificate |
| `InvalidBucketName` | OneFS virtual-hosted addressing is not configured | Set the OneFS base domain, wildcard subdomains, and wildcard DNS |
| `Unable to verify integrity of data upload` | OneFS returns a non-MD5 ETag | Enable `use-md5-for-etag` on the OneFS access zone |
| `403 AccessDenied` | Bucket or filesystem ACL is incomplete | Verify both OneFS filesystem permissions and bucket ACL |
| Migrated attachment is listed but cannot be opened | Object key/path does not match metadata | Validate conversion output and `mxe.cosnestedfile` |

Prefer fixing the OneFS ETag behavior. The JVM option
`-Dcom.amazonaws.services.s3.disablePutObjectMD5Validation=true` disables an
integrity check and should be used only as a documented exception.

## Production operations

- Back up the Manage database and PowerScale attachment data to the same recovery
  point. A mismatched restore creates dangling database links or orphaned objects.
- Rotate the PowerScale S3 key through change control. Update Vault and the
  manually managed Kubernetes Secret, reconcile Manage, and verify all server
  bundles before retiring the old credential.
- Monitor endpoint certificate expiry, S3 service health, bucket capacity and
  object count, failed attachment operations, and orphaned objects.
- Test upload, download, restore, and migrated attachment retrieval after Manage
  upgrades or PowerScale changes.
- Keep migration evidence and acceptance results with the implementation ticket.

## References

- [IBM: Configure attachments with the ManageWorkspace custom resource](https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd?topic=documents-configuring-attachments-by-using-manageworkspace-custom-resource)
- [IBM: Convert file-based storage to S3](https://www.ibm.com/docs/en/masv-and-l/maximo-manage/cd?topic=storage-converting-file-based-s3)
- [PowerScale S3 setup](./powerscale-s3-onefs-setup.md)
