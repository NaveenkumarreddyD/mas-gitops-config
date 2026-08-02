# Manage attachments on PowerScale (OneFS) S3

Configure Maximo Manage "attached documents" (doclinks) to store files in Dell
PowerScale (OneFS) S3 instead of a `/DOCLINKS` PVC or NFS share, for the
`drroc4` / `drrocapp` instance.

## What this is (and is NOT)

- Manage attachments on S3 are driven by **Maximo system properties**
  (`mxe.cos*`) stored in the Manage database (`MAXPROPVALUE`). They are **not** a
  MAS custom resource, so **GitOps cannot own them declaratively** — this is an
  imperative step, like the SLS/DRO registration harvest.
- The MAS **`ObjectStorageCfg` / `coscfgs` CR** (the `130-ibm-objectstorage-config`
  chart) is the MAS **platform** object-storage config used by other MAS apps. It
  does **not** configure Manage attachments. Do not wire it up for this.
- PowerScale OneFS S3 is just an S3-compatible endpoint (HTTPS on **port 9021**
  by default), so Manage's `COSAttachmentStorage` provider talks to it the same
  way it talks to AWS/IBM COS — you point `mxe.cosendpointuri` at PowerScale.
- IBM's `suite_manage_attachments_config` Ansible role does not provide a clean
  custom PowerScale endpoint path for this design, so the Manage properties are
  applied manually and tested before migration.

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

Using the Vault UI, create `secret/drroc4/drroc4/drrocapp/manage-cos` with:

| Field | Value |
|---|---|
| `endpoint` | `https://bhm-pwrsclnfs.lac1.biz:9021` |
| `bucket` | `dr-maximo-bckt` |
| `access_key` | OneFS S3 access key |
| `secret_key` | OneFS S3 secret key |
| `ca.crt` | Raw endpoint CA PEM |

This path is a secure operator handoff; no chart reads it automatically.

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
(the preflight in step 3 detects this). There is **no verified declarative
`certificates:` field on the `ManageWorkspace` CR** for an arbitrary external CA
in the 8.7.x line — do not add one blind. Use one of:
- Have OneFS present a cert signed by an internal CA that Manage already trusts
  (e.g. your Spire chain), if feasible; **or**
- Add the OneFS S3 CA to the Manage truststore via the mechanism supported by
  your exact MAS Manage build — **verify the field/secret against your
  `manageworkspaces.apps.mas.ibm.com` CRD before applying**
  (`oc explain manageworkspace.spec.settings --recursive | grep -i cert`).
Re-run step 3 until it reports **PASS**.

### 5. Apply the properties (encryption-safe)
`mxe.cosaccesskey` / `mxe.cossecretkey` are **encrypted** properties — a raw SQL
`UPDATE` writes plaintext that Maximo cannot decrypt. Set them via a path that
encrypts on write:
- **Manage admin UI** (recommended): System Configuration → Platform
  Configuration → System Properties → set each value → **Live Refresh**. Take the
  key values from Vault `secret/drroc4/drroc4/drrocapp/manage-cos`.
- **Maximo REST API**: same properties + a live refresh, using the superuser
  credential from the operator-generated secret `drrocapp-credentials-superuser`
  in the `mas-drrocapp-core` namespace.
- Set the non-encrypted properties through the same Manage UI and perform a Live Refresh.

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
- **`global_secrets` will NOT carry these.** The Manage operator only maps a
  whitelisted set of `MXE_*` env vars (the crypto keys) into system properties;
  arbitrary `mxe.cos*` env vars are not applied, and camelCase
  `mxe.doclink.securedAttachment` can't be represented as an uppercase env var.
  Use MAXPROPVALUE / UI / API, not `global_secrets`.
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
