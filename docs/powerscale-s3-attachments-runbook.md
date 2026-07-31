# PowerScale S3 Bucket for IBM MAS Attachments — Full Runbook

End-to-end steps to set up a PowerScale (OneFS) S3 bucket for IBM MAS Manage attachments,
including the OneFS protocol settings and Manage properties that MAS needs to actually work.

## Environment values (drroc4 / drgitopsapp)

| Item | Value |
|---|---|
| Bucket | `dr-maximo-bckt` |
| Backing path | `/ifs/stl-pwrsc/data/S3/DR-Maximo-Bckt` |
| S3 user | `dr_maximo` |
| Group | `s3_mas_attach_users` |
| Access zone | `data` |
| S3 endpoint | `https://bhm-pwrsclnfs.lac1.biz:9021` (VIP 10.1.108.198) |
| CA | internal Spire chain — `/etc/pki/ca-trust/source/anchors/spire-chain.cer` |

---

# Part A — OneFS: bucket, user, and permissions

## 1. Confirm the bucket and S3 user

```bash
isi s3 keys list
isi s3 buckets view dr-maximo-bckt
```
The bucket owner/ACL and the access key user should both be `dr_maximo`.

## 2. Enter the correct access zone

`dr_maximo` is a local user in the `data` zone. Find the zone ID and enter it:

```bash
isi zone zones view --zone=data
isi_run -z <ZONE_ID> -l root      # example: isi_run -z 2 -l root
```

## 3. Set bucket directory ownership

```bash
chown dr_maximo:s3_mas_attach_users /ifs/stl-pwrsc/data/S3/DR-Maximo-Bckt
```

## 4. Add parent directory traverse access

Each parent dir needs traverse/execute:

```bash
chmod +a group s3_mas_attach_users allow dir_gen_execute /ifs/stl-pwrsc
chmod +a group s3_mas_attach_users allow dir_gen_execute /ifs/stl-pwrsc/data
chmod +a group s3_mas_attach_users allow dir_gen_execute /ifs/stl-pwrsc/data/S3
```
(Or use `user dr_maximo` instead of `group s3_mas_attach_users`.)

## 5. Add bucket directory access

```bash
chmod +a group s3_mas_attach_users allow dir_gen_all,file_gen_all,object_inherit,container_inherit /ifs/stl-pwrsc/data/S3/DR-Maximo-Bckt
```
For an existing bucket with files, apply recursively with `chmod -R +a ...`.

## 6. Set the S3 bucket ACL

Grant the MAS S3 user full control (UI or CLI):
```text
dr_maximo = FULL_CONTROL
```
PowerScale S3 needs **both** the S3 bucket ACL **and** the OneFS filesystem permission (steps 3–5).

---

# Part B — OneFS: S3 protocol settings MAS requires

Manage's AWS SDK talks to S3 in a specific way. These three settings are what make MAS work
(each one, if missing, gives a different error — see Troubleshooting).

## 7. Enable S3

```bash
isi s3 settings global modify --enabled true      # HTTPS/9021; HTTP/9020 stays off
```

## 8. Enable virtual-hosted-style addressing (base domain)

MAS connects as `dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz` (bucket in hostname). OneFS must be told
to accept that:

```bash
# find the groupnet: isi network pools list  (SC DNS name = bhm-pwrsclnfs.lac1.biz; pool ID = groupnet.subnet.pool)
isi network groupnets modify <groupnet> --allow-wildcard-subdomains=true
isi s3 settings zone modify --zone=data --base-domain=bhm-pwrsclnfs.lac1.biz
```
Also needs wildcard DNS `*.bhm-pwrsclnfs.lac1.biz → 10.1.108.198`.

## 9. Enable MD5 ETags

MAS verifies uploads by MD5; OneFS doesn't return MD5 ETags by default:

```bash
isi s3 settings zone modify --zone=data --use-md5-for-etag=true
```

## 10. Certificate must cover the wildcard host

The S3 endpoint cert must include a `*.bhm-pwrsclnfs.lac1.biz` SAN (because MAS connects to
`dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz`). Verify:

```bash
echo | openssl s_client -connect bhm-pwrsclnfs.lac1.biz:9021 -servername bhm-pwrsclnfs.lac1.biz 2>/dev/null \
  | openssl x509 -noout -ext subjectAltName
```
Look for `DNS:*.bhm-pwrsclnfs.lac1.biz`.

---

# Part C — Test from the command line

Use the same access key/secret MAS will use.

**Path-style (basic bucket check):**
```bash
s3cmd ls  s3://dr-maximo-bckt/                      --host=bhm-pwrsclnfs.lac1.biz:9021 --host-bucket='bhm-pwrsclnfs.lac1.biz:9021'            --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer
s3cmd put test.txt s3://dr-maximo-bckt/test.txt     --host=bhm-pwrsclnfs.lac1.biz:9021 --host-bucket='bhm-pwrsclnfs.lac1.biz:9021'            --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer
s3cmd get s3://dr-maximo-bckt/test.txt              --host=bhm-pwrsclnfs.lac1.biz:9021 --host-bucket='bhm-pwrsclnfs.lac1.biz:9021'            --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer
s3cmd del s3://dr-maximo-bckt/test.txt              --host=bhm-pwrsclnfs.lac1.biz:9021 --host-bucket='bhm-pwrsclnfs.lac1.biz:9021'            --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer
```

**Virtual-hosted (mirrors what MAS actually does — this must pass after Part B):**
```bash
s3cmd put test.txt s3://dr-maximo-bckt/vhtest.txt \
  --host=bhm-pwrsclnfs.lac1.biz:9021 --host-bucket='%(bucket)s.bhm-pwrsclnfs.lac1.biz:9021' \
  --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer
```
Expect `stored` / no error. `InvalidBucketName` or MD5 errors here mean Part B step 8 or 9 isn't done.

---

# Part D — Configure Manage (manual, for now)

Set the properties directly in Manage. No Vault/GitOps — enter the S3 keys by hand.

## 11. Get the S3 access key + secret

From OneFS (or from whoever created them):
```bash
isi s3 keys list                       # confirm the key belongs to dr_maximo
isi s3 keys create --user dr_maximo    # only if you need to (re)generate a key
```
Keep the **access key** and **secret key** handy for the next step.

## 12. Confirm Manage trusts the S3 CA

The endpoint uses the internal Spire CA. From a Manage server-bundle pod:
```bash
oc exec -n mas-drgitopsapp-manage <pod> -- bash -c \
  "echo | openssl s_client -connect bhm-pwrsclnfs.lac1.biz:9021 -servername bhm-pwrsclnfs.lac1.biz 2>/dev/null | grep -i 'verify return code'"
```
Want `0 (ok)`. If it fails, add the Spire CA to the Manage truststore before continuing.

## 13. Set Manage system properties (by hand)

Manage UI → **System Configuration → Platform Configuration → System Properties**. Set each value,
then **Live Refresh**, then restart **all** server-bundle pods. Type the access/secret key straight
into the UI (they are encrypted properties — set via UI, **never** raw SQL).

| Property | Value |
|---|---|
| `mxe.attachmentstorage` | `com.ibm.tivoli.maximo.oslc.provider.COSAttachmentStorage` |
| `mxe.cosendpointuri` | `https://bhm-pwrsclnfs.lac1.biz:9021` |
| `mxe.cosbucketname` | `dr-maximo-bckt` |
| `mxe.cosaccesskey` | *(paste the access key from step 11)* |
| `mxe.cossecretkey` | *(paste the secret key from step 11)* |
| `mxe.doclink.securedAttachment` | `true` (required) |
| `mxe.doclink.doctypes.defpath` | `cos:doclinks/default` |
| `mxe.doclink.doctypes.topLevelPaths` | `cos:doclinks` |
| `mxe.doclink.path01` | `cos:doclinks=https://drgitopswks.manage.drgitopsapp.apps.drroc4.lac1.biz/maximo/oslc/cosdoclink` |

> Store the keys in Vault for controlled handoff, but enter the encrypted properties through
> the Manage UI. AVP does not configure Maximo database system properties.

## 14. Verify in Manage

Add an attachment to any record → confirm it saves with no error, and the object appears:
```bash
s3cmd ls s3://dr-maximo-bckt/ --host=bhm-pwrsclnfs.lac1.biz:9021 --host-bucket='bhm-pwrsclnfs.lac1.biz:9021' --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer
```

---

# Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `403 AccessDenied` on s3cmd | Filesystem/S3 ACL missing | Part A steps 3–6; check `ls -led <path>`, `id dr_maximo` |
| TLS/cert error naming `dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz` | Cert missing wildcard SAN | Step 10 — add `*.bhm-pwrsclnfs.lac1.biz` SAN |
| `InvalidBucketName` (400) on upload | Virtual-hosted not enabled on OneFS | Step 8 — `--base-domain` + `--allow-wildcard-subdomains` |
| `Unable to verify integrity of data upload` (object lands but Manage errors `BMXAA2322E`) | OneFS returns non-MD5 ETag | Step 9 — `--use-md5-for-etag=true` |

Manage-side fallback for the MD5 error (only if you can't change OneFS): JVM option on the server
bundles `-Dcom.amazonaws.services.s3.disablePutObjectMD5Validation=true`.

---

# Notes

- Parent directories need only traverse/execute; the bucket directory needs full read/write/create/delete.
- Prefer **group** ACLs (`s3_mas_attach_users`) over per-user if multiple MAS/S3 users.
- Users/groups in the `data` zone → run ACL commands from `isi_run -z <ZONE_ID> -l root`.
- Manage uses **virtual-hosted-style** S3 and cannot be switched to path-style, so Part B is mandatory.
- Existing filesystem attachments are not auto-migrated — use `file2s3.sh` if needed.
