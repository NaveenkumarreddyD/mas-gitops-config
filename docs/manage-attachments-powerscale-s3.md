# Manage attachments on PowerScale (OneFS) S3

Configure Maximo Manage "attached documents" (doclinks) to store files in Dell
PowerScale (OneFS) S3 instead of a `/doclinks` PVC or NFS share. The shared
instance template supports filesystem, migration, and S3-only modes.

## What this is (and is NOT)

- GitOps owns the selected attachment provider through
  `ManageWorkspace.spec.settings.db.attachmentProvider`.
- `MANAGE_ATTACHMENT_PROVIDER=filestorage` configures `/doclinks` and mounts the
  RWX PVC. `s3-migration` configures S3 while retaining that PVC for migration
  verification or rollback. `s3` configures S3 without the legacy PVC.
- The S3 access secret is rendered as a Kubernetes Secret containing the IBM
  required `accessSecretKey` field. The endpoint, bucket, access key, secret key,
  and CA chain remain in Vault and are resolved by Argo CD Vault Plugin.
- The MAS **`ObjectStorageCfg` / `coscfgs` CR** (the `130-ibm-objectstorage-config`
  chart) is the MAS **platform** object-storage config used by other MAS apps. It
  does **not** configure Manage attachments. Do not wire it up for this.
- PowerScale OneFS S3 is just an S3-compatible endpoint (HTTPS on **port 9021**
  by default), so Manage's `COSAttachmentStorage` provider talks to it the same
  way it talks to AWS/IBM COS — you point `mxe.cosendpointuri` at PowerScale.
- The PowerScale SubCA and Root CA are supplied through
  `ManageWorkspace.spec.settings.deployment.importedCerts` so the Manage server
  bundles trust the private S3 endpoint.
- The deployed Manage CRD requires `providerCredentials.s3Url`; it is populated
  from the Vault `endpoint` field. Some IBM documentation still shows the older
  `cosAwsUrl` field, which this CRD rejects.

## The properties

| Property | Value | Notes |
|---|---|---|
| `mxe.attachmentstorage` | `com.ibm.tivoli.maximo.oslc.provider.COSAttachmentStorage` | selects the S3/COS provider |
| `mxe.cosendpointuri` | `https://bhm-pwrsclnfs.lac1.biz:9021` | PowerScale SmartConnect zone / VIP (resolves to 10.1.108.198) |
| `mxe.cosbucketname` | `dr-maximo-bckt` | pre-created bucket |
| `mxe.cosaccesskey` | *(from Vault)* | **encrypted property** — set via UI/API, not raw SQL |
| `mxe.cossecretkey` | *(from Vault)* | **encrypted property** — set via UI/API, not raw SQL |
| `mxe.doclink.securedAttachment` | `true` | **REQUIRED** — S3 attachments only work when true |

## Procedure

### 1. PowerScale (OneFS) side
- Enable S3 (off by default): `isi s3 settings global modify --enabled true`
  (HTTPS/9021; HTTP/9020 stays disabled).
- Create the bucket (`dr-maximo-bckt`).
- Generate an S3 access key + secret for the bucket owner:
  `isi s3 keys create --user <owner>`.
- Export the CA cert that the S3 endpoint presents on :9021 (almost certainly an
  internal / OneFS self-signed CA — you need it for step 4).

### 2. Store the handoff values in Vault

Using the Vault UI, create
`secret/<account>/<cluster>/<instance>/manage-cos` with:

| Field | Value |
|---|---|
| `endpoint` | `https://bhm-pwrsclnfs.lac1.biz:9021` |
| `bucket` | `dr-maximo-bckt` |
| `access_key` | OneFS S3 access key |
| `secret_key` | OneFS S3 secret key |
| `powerscale_s3_subca` | Raw SubCA PEM, including BEGIN/END lines |
| `powerscale_s3_rootca` | Raw Root CA PEM, including BEGIN/END lines |

The shared template reads these fields through Argo CD Vault Plugin. Do not put
the secret values in an `.env` file or commit them to Git.

### 3. Preflight

From a running Manage server-bundle pod, open a TLS session to the PowerScale endpoint:

```bash
oc exec -n mas-drrocapp-manage <server-bundle-pod> -- bash -c \
  "echo | openssl s_client -connect bhm-pwrsclnfs.lac1.biz:9021 \
  -servername dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz 2>/dev/null | grep -i 'verify return code'"
```

The expected result is `0 (ok)`.

### 4. Certificate trust — the most-missed step
Because :9021 is HTTPS with an internal CA, the Manage Liberty JVM must **trust
the PowerScale S3 CA** or every attachment call fails with a TLS handshake error
(the preflight in step 3 detects this). The S3 modes render the Vault SubCA and
Root CA into `ManageWorkspace.spec.settings.deployment.importedCerts`. After the
workspace reconciles, verify the imported aliases and rerun step 3 until the TLS
verification reports `0 (ok)`.

### 5. Select and render the provider

For the initial filesystem test:

```text
MANAGE_ATTACHMENT_PROVIDER=filestorage
MANAGE_DOCLINKS_PATH=/doclinks
MANAGE_DOCLINKS_SIZE=100Gi
```

After the test attachments exist and the Vault S3 values are ready, use
`MANAGE_ATTACHMENT_PROVIDER=s3-migration`. This changes the active provider to
S3 while retaining the legacy PVC. After migration and acceptance checks are
complete, use `MANAGE_ATTACHMENT_PROVIDER=s3` to stop mounting the legacy PVC.

Run `./render.sh <environment>` and commit the rendered environment. Argo CD
then creates the S3 credential Secret and reconciles the `ManageWorkspace`.

### 6. Verify
Create an attachment on any record; confirm the object appears in the
`dr-maximo-bckt` bucket on PowerScale. Existing filesystem attachments
are **not** migrated automatically — plan a separate copy/migration if needed.

## Gotchas

- **Path-style vs virtual-hosted addressing.** On-prem S3 usually needs
  **path-style** (`endpoint/bucket/key`); virtual-hosted style
  (`bucket.endpoint`) needs wildcard DNS that SmartConnect typically lacks.
  Confirm OneFS is configured for path-style (or DNS supports virtual-hosted) and
  that your Manage build's COS client honours it. This is the most likely thing
  to bite during step 6.
- **`securedAttachment` must be `true`** or the S3 provider is bypassed.
- **Do not use `global_secrets` for the S3 credentials.** The chart creates the
  dedicated Secret shape expected by `attachmentProvider.s3.secretKey`.
- **Version check.** Confirm the exact property list for the Manage 8.7.x channel
  in IBM docs before applying — property names have been stable but verify.

## Resolved issues — the three things that blocked attachments (CONFIRMED, drroc4)

Manage attachments to PowerScale S3 failed through **three distinct layers**, each with a
different error. All three are now fixed. Diagnose in this order if it breaks again — the
symptom changes as you fix each layer.

### 1. TLS — cert did not cover the virtual-hosted hostname
- **Symptom:** TLS/cert error naming `dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz`.
- **Why:** the AWS SDK uses **virtual-hosted style** (`<bucket>.<endpoint>`), so it connects to
  `dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz` — which the OneFS cert didn't cover.
- **Fix:** add a **`*.bhm-pwrsclnfs.lac1.biz`** SAN to the OneFS S3 cert.
- **Verify:** `echo | openssl s_client -connect bhm-pwrsclnfs.lac1.biz:9021 -servername bhm-pwrsclnfs.lac1.biz 2>/dev/null | openssl x509 -noout -ext subjectAltName` → shows `DNS:*.bhm-pwrsclnfs.lac1.biz`.

### 2. S3 addressing — OneFS rejected virtual-hosted requests → `InvalidBucketName`
- **Symptom:** `AmazonS3Exception: The specified bucket is not valid (InvalidBucketName; 400)`.
  Manage stack ends in `COSApi.uploadFile` → `AmazonS3Client.putObject`.
- **Why:** AWS SDK v1 defaults to **virtual-hosted style** for DNS-valid bucket names and has
  **no property/env toggle** for path-style (code-only `withPathStyleAccessEnabled`). OneFS only
  accepts virtual-hosted requests when the S3 **base domain** is configured; it wasn't, so it
  couldn't map the hostname subdomain to a bucket. (s3cmd worked only because `.s3cfg` had
  `host_bucket` **without** `%(bucket)s`, forcing path-style — a different mode than Manage.)
- **Reproduce with s3cmd (virtual-hosted PUT = what Manage does):**
  ```
  s3cmd put /tmp/x s3://dr-maximo-bckt/x --host=bhm-pwrsclnfs.lac1.biz:9021 \
    --host-bucket='%(bucket)s.bhm-pwrsclnfs.lac1.biz:9021' --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer
  ```
- **Fix (OneFS, per Dell OneFS S3 API Guide H18293):**
  ```
  isi network groupnets modify <groupnet> --allow-wildcard-subdomains=true
  isi s3 settings zone modify --zone=<zone> --base-domain=bhm-pwrsclnfs.lac1.biz
  ```
  Needs wildcard DNS `*.bhm-pwrsclnfs.lac1.biz → 10.1.108.198` (already present) and the SAN from #1.
  Find the groupnet via `isi network pools list` (SC DNS name = `bhm-pwrsclnfs.lac1.biz`; pool ID = `groupnet.subnet.pool`).

### 3. Data integrity — OneFS non-MD5 ETag → `Unable to verify integrity of data upload`
- **Symptom:** SDK error `Unable to verify integrity of data upload. Client calculated content
  hash (contentMD5 …) didn't match hash (etag: 000000010b61…) calculated by Amazon S3`.
  **The object lands in the bucket at full size, but Manage rolls back the doclink** (you get
  `BMXAA2322E - Cannot clear the filter until record is saved`), so the attachment isn't
  registered and each attempt orphans an object.
- **Why:** OneFS by default does **not** compute MD5 ETags — it returns an opaque string. The AWS
  SDK verifies uploads by comparing its MD5 to the returned ETag → mismatch → throws.
- **Fix (OneFS, preferred — keeps integrity checking):**
  ```
  isi s3 settings zone modify --zone=<zone> --use-md5-for-etag=true
  ```
  (per-zone; disabled by default; OneFS 9.4+. Optional companion `--validate-content-md5=true`.)
- **Fallback (Manage/SDK — no storage change):** JVM option on the server bundles
  `-Dcom.amazonaws.services.s3.disablePutObjectMD5Validation=true` (add `disableGetObjectMD5Validation=true`
  for reads). Skips the client check; you lose upload integrity verification.

**References:** Dell OneFS S3 API Guide (H18293); Dell OneFS Web Admin Guide "ETag"
(`use-md5-for-etag` / `validate-content-md5`); AWS SDK for Java v1 `SkipMd5CheckStrategy`.

## Records for this change

- This document contains the endpoint, bucket, properties, and confirmed fixes.
- Vault contains the credential handoff at `secret/drroc4/drroc4/drrocapp/manage-cos`.
- The migration and acceptance evidence must be attached to the implementation ticket.
