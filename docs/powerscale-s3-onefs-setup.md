# PowerScale (OneFS) S3 Setup for MAS Attachments — PowerScale Side Only

Simple OneFS steps to prepare an S3 bucket for IBM MAS Manage attachments.
(Manage-side configuration is a separate doc.)

## Values (drroc4)

| Item | Value |
|---|---|
| Bucket | `dr-maximo-bckt` |
| Backing path | `/ifs/stl-pwrsc/data/S3/DR-Maximo-Bckt` |
| S3 user | `dr_maximo` |
| Group | `s3_mas_attach_users` |
| Access zone | `data` |
| S3 endpoint | `https://bhm-pwrsclnfs.lac1.biz:9021` (VIP 10.1.108.198) |

---

## 1. Enable S3

```bash
isi s3 settings global modify --enabled true      # HTTPS/9021; HTTP/9020 stays off
```

## 2. Confirm the bucket and S3 user

```bash
isi s3 keys list
isi s3 buckets view dr-maximo-bckt
```
Bucket owner and access key user should both be `dr_maximo`.

## 3. Enter the access zone

```bash
isi zone zones view --zone=data
isi_run -z <ZONE_ID> -l root      # example: isi_run -z 2 -l root
```

## 4. Set bucket directory ownership

```bash
chown dr_maximo:s3_mas_attach_users /ifs/stl-pwrsc/data/S3/DR-Maximo-Bckt
```

## 5. Add parent directory traverse access

```bash
chmod +a group s3_mas_attach_users allow dir_gen_execute /ifs/stl-pwrsc
chmod +a group s3_mas_attach_users allow dir_gen_execute /ifs/stl-pwrsc/data
chmod +a group s3_mas_attach_users allow dir_gen_execute /ifs/stl-pwrsc/data/S3
```

## 6. Add bucket directory access

```bash
chmod +a group s3_mas_attach_users allow dir_gen_all,file_gen_all,object_inherit,container_inherit /ifs/stl-pwrsc/data/S3/DR-Maximo-Bckt
```
Existing bucket with files → add `-R`: `chmod -R +a group ... /ifs/stl-pwrsc/data/S3/DR-Maximo-Bckt`

## 7. Set the S3 bucket ACL

Grant the MAS user full control (UI or CLI):
```text
dr_maximo = FULL_CONTROL
```
S3 needs **both** the bucket ACL and the filesystem permissions (steps 4–6).

## 8. Enable virtual-hosted-style addressing

MAS connects as `dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz`, so OneFS must accept bucket-in-hostname:

```bash
# find groupnet: isi network pools list  (SC DNS name = bhm-pwrsclnfs.lac1.biz; pool ID = groupnet.subnet.pool)
isi network groupnets modify <groupnet> --allow-wildcard-subdomains=true
isi s3 settings zone modify --zone=data --base-domain=bhm-pwrsclnfs.lac1.biz
```
Also needs wildcard DNS `*.bhm-pwrsclnfs.lac1.biz → 10.1.108.198`.

## 9. Enable MD5 ETags

MAS verifies uploads by MD5; OneFS must return MD5 ETags:

```bash
isi s3 settings zone modify --zone=data --use-md5-for-etag=true
```

## 10. Certificate must cover the wildcard host

The S3 endpoint cert must include a `*.bhm-pwrsclnfs.lac1.biz` SAN. Verify:

```bash
echo | openssl s_client -connect bhm-pwrsclnfs.lac1.biz:9021 -servername bhm-pwrsclnfs.lac1.biz 2>/dev/null \
  | openssl x509 -noout -ext subjectAltName
```
Look for `DNS:*.bhm-pwrsclnfs.lac1.biz`.

---

## Quick test (from any host with the access key)

```bash
# path-style
s3cmd put test.txt s3://dr-maximo-bckt/test.txt \
  --host=bhm-pwrsclnfs.lac1.biz:9021 --host-bucket='bhm-pwrsclnfs.lac1.biz:9021' \
  --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer

# virtual-hosted (must pass after steps 8–9 — this is how MAS connects)
s3cmd put test.txt s3://dr-maximo-bckt/vhtest.txt \
  --host=bhm-pwrsclnfs.lac1.biz:9021 --host-bucket='%(bucket)s.bhm-pwrsclnfs.lac1.biz:9021' \
  --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer
```

## If it fails

| Error | Fix |
|---|---|
| `403 AccessDenied` | ACLs — steps 4–7 (`ls -led <path>`, `id dr_maximo`) |
| cert error naming `dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz` | step 10 — add `*.bhm-pwrsclnfs.lac1.biz` SAN |
| `InvalidBucketName` | step 8 — base domain + wildcard subdomains |
| `Unable to verify integrity of data upload` | step 9 — `--use-md5-for-etag=true` |

## Notes

- Parent dirs need only traverse/execute; bucket dir needs full read/write/create/delete.
- Prefer group ACLs over per-user for multiple MAS/S3 users.
- Steps 8–9 (base domain, MD5 ETag) are **per access zone**.
