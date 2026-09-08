# PowerScale S3 setup for MAS attachments

This document contains only the Dell PowerScale OneFS work required before MAS
Manage can use an S3 bucket. The MAS configuration and migration procedure is in
[Manage attachments on PowerScale S3](./manage-attachments-powerscale-s3.md).

## Environment values

| Item | Value |
|---|---|
| Bucket | `dr-maximo-bckt` |
| Backing path | `/ifs/stl-pwrsc/data/S3/DR-Maximo-Bckt` |
| S3 user | `dr_maximo` |
| Group | `s3_mas_attach_users` |
| Access zone | `data` |
| S3 endpoint | `https://bhm-pwrsclnfs.lac1.biz:9021` |

## Provisioning

### 1. Enable HTTPS S3

```bash
isi s3 settings global modify --enabled true
```

Keep HTTP port 9020 disabled. MAS uses HTTPS port 9021.

### 2. Confirm the bucket and S3 identity

```bash
isi s3 keys list
isi s3 buckets view dr-maximo-bckt
```

The bucket owner and access-key user should both be `dr_maximo`.

### 3. Enter the access zone

```bash
isi zone zones view --zone=data
isi_run -z <ZONE_ID> -l root
```

### 4. Configure filesystem ownership and ACLs

```bash
chown dr_maximo:s3_mas_attach_users /ifs/stl-pwrsc/data/S3/DR-Maximo-Bckt

chmod +a group s3_mas_attach_users allow dir_gen_execute /ifs/stl-pwrsc
chmod +a group s3_mas_attach_users allow dir_gen_execute /ifs/stl-pwrsc/data
chmod +a group s3_mas_attach_users allow dir_gen_execute /ifs/stl-pwrsc/data/S3

chmod +a group s3_mas_attach_users allow \
  dir_gen_all,file_gen_all,object_inherit,container_inherit \
  /ifs/stl-pwrsc/data/S3/DR-Maximo-Bckt
```

Parent directories require traverse access. The bucket directory requires the
read, write, create, and delete permissions used by Manage. For an existing
bucket, review the effect before applying ACL changes recursively.

### 5. Configure the bucket ACL

Grant the dedicated MAS identity bucket-scoped access:

```text
dr_maximo = FULL_CONTROL
```

Both the S3 bucket ACL and the OneFS filesystem permissions must allow access.

### 6. Enable virtual-hosted S3 addressing

Manage connects to `<bucket>.<endpoint>`. Configure OneFS, DNS, and the endpoint
certificate for that hostname pattern:

```bash
isi network pools list
isi network groupnets modify <groupnet> --allow-wildcard-subdomains=true
isi s3 settings zone modify --zone=data \
  --base-domain=bhm-pwrsclnfs.lac1.biz
```

Create wildcard DNS pointing `*.bhm-pwrsclnfs.lac1.biz` to the S3 VIP. The TLS
certificate must include the same wildcard name in its SAN list.

### 7. Enable MD5 ETags

Manage verifies uploads against the returned ETag:

```bash
isi s3 settings zone modify --zone=data --use-md5-for-etag=true
```

Without this setting, OneFS can store the object while the Manage transaction
still fails its integrity check.

## Validation

Verify the certificate SAN:

```bash
echo | openssl s_client \
  -connect bhm-pwrsclnfs.lac1.biz:9021 \
  -servername dr-maximo-bckt.bhm-pwrsclnfs.lac1.biz 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Test basic path-style access and the virtual-hosted request pattern used by
Manage:

```bash
echo "PowerScale S3 test" > test.txt

s3cmd put test.txt s3://dr-maximo-bckt/path-test.txt \
  --host=bhm-pwrsclnfs.lac1.biz:9021 \
  --host-bucket='bhm-pwrsclnfs.lac1.biz:9021' \
  --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer

s3cmd put test.txt s3://dr-maximo-bckt/virtual-host-test.txt \
  --host=bhm-pwrsclnfs.lac1.biz:9021 \
  --host-bucket='%(bucket)s.bhm-pwrsclnfs.lac1.biz:9021' \
  --ca-certs=/etc/pki/ca-trust/source/anchors/spire-chain.cer
```

Confirm list, download, and delete operations before handing the bucket to the
MAS team.

## Handoff to the MAS team

Provide these values through the approved secret-transfer process:

| Value | Purpose |
|---|---|
| Endpoint | Manage `mxe.cosendpointuri` system property |
| Bucket name | Attachment destination |
| Access key | Manage `mxe.cosaccesskey` encrypted system property |
| Secret key | Manage `mxe.cossecretkey` encrypted system property |
| SubCA PEM | Manage imported certificate chain |
| Root CA PEM | Manage imported certificate chain |

Never place the secret key in Git, tickets, chat, or email.

## Production operations

- Use a dedicated S3 identity and bucket-scoped permissions. Rotate credentials
  on an agreed schedule with the MAS team.
- Set capacity and object-count quotas and alerts based on measured attachment
  growth. Include metadata performance in capacity planning.
- Protect the bucket path with SnapshotIQ and, where required, SyncIQ. Coordinate
  recovery points with the Manage database backup schedule.
- Monitor the S3 service, endpoint certificate expiry, DNS, access-zone health,
  capacity, object count, ACL changes, and ETag behavior.
- Apply change control to the base domain, wildcard DNS, TLS certificate, ACLs,
  and `use-md5-for-etag` setting because changes can stop all Manage attachment
  operations.

## Troubleshooting

| Symptom | Check |
|---|---|
| `403 AccessDenied` | Bucket ACL, filesystem ACLs, ownership, and access-zone identity |
| TLS hostname error | Wildcard DNS and certificate SAN for `<bucket>.<endpoint>` |
| `InvalidBucketName` | Base domain and wildcard-subdomain settings |
| Upload integrity error | `use-md5-for-etag=true` on the correct access zone |

## Storage acceptance checklist

- [ ] HTTPS S3 is enabled and HTTP is disabled.
- [ ] Dedicated user, key, bucket, filesystem ACLs, and bucket ACL are verified.
- [ ] Virtual-hosted upload, download, list, and delete operations pass.
- [ ] Wildcard DNS and certificate SAN cover `<bucket>.<endpoint>`.
- [ ] MD5 ETags are enabled and verified.
- [ ] Capacity alerts, snapshots, replication, and ownership are documented.
- [ ] Endpoint, credentials, and CA chain are transferred securely to the MAS team.
