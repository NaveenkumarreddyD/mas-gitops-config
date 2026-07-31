# PowerScale S3 for MAS Attachments — Production Standard

What to consider and take care of before running MAS Manage attachments on PowerScale (OneFS) S3
in production. Use as a readiness checklist and operational standard.

---

## 1. Architecture & addressing (must be right or attachments fail)

- **Manage uses virtual-hosted-style S3** (`<bucket>.<endpoint>`) and cannot be switched to
  path-style. OneFS must be configured to match:
  - S3 base domain set on the access zone (`isi s3 settings zone modify --base-domain`)
  - Wildcard subdomains enabled on the groupnet
  - Wildcard DNS `*.<zone> → VIP`
- **Endpoint cert must carry a `*.<zone>` SAN** (SDK connects to `bucket.zone`).
- **OneFS must return MD5 ETags** (`--use-md5-for-etag=true`) or the SDK fails upload integrity
  verification even though the object lands.
- Use **HTTPS/9021 only**; keep HTTP/9020 disabled.

## 2. Scale & capacity (the main production risk)

- OneFS maps each S3 object → a file; **Maximo stores attachments FLAT** (no subdirectories), so
  they concentrate in one directory.
- **Filesystem limit is the real ceiling:** ~**100K files/dir recommended, 1M hard max**. Millions
  of attachments in one flat directory will degrade then fail.
- **Take care of:**
  - **Bucket/path rollover plan** (e.g. per year) so no directory exceeds ~100K–500K files.
  - **SSD/flash metadata acceleration** on the zone — biggest lever for large-directory performance.
  - **Capacity + inode sizing** for millions of small files (metadata heavy).
  - Bucket-count limits (40K/cluster, 1K/user) are not the constraint — files-per-directory is.

## 3. Security & access

- **Least privilege:** dedicated S3 user (`dr_maximo`) + group; grant only that identity
  `FULL_CONTROL` on the bucket. Both **S3 bucket ACL and OneFS filesystem ACL** are required.
- **Credentials in a secret store** (Vault/AVP), not in properties files or tickets. Rotate the S3
  access/secret keys on a schedule; document rotation steps.
- **Encrypted Manage properties:** set `mxe.cosaccesskey`/`mxe.cossecretkey` via UI/API only,
  never raw SQL.
- **TLS everywhere**, trusted CA (internal Spire chain) in the Manage truststore; no
  cert-verification bypass.
- **Network:** restrict S3 endpoint reachability to the MAS cluster; segregate the access zone.

## 4. Data protection & DR

- **Backups/snapshots:** SnapshotIQ on the bucket path; define frequency + retention.
- **Replication:** SyncIQ to the DR site if attachments must survive site loss; confirm it matches
  MAS DR RPO/RTO.
- **Consistency with the DB:** attachments live on PowerScale, the doclink pointers live in the
  Manage DB — back them up **together / point-in-time aligned**, or restores will orphan/dangle.
- **Orphan management:** failed uploads can leave objects with no DB pointer; schedule reconciliation
  cleanup.

## 5. Monitoring & alerting

- **SmartQuotas (accounting)** on the bucket path — alert on **file count** nearing 100K/500K and on
  capacity thresholds.
- **Directory growth trend** — watch enumeration latency as counts climb.
- **S3 service health** (`isi s3` enabled, listener on 9021), cert expiry on the endpoint SAN.
- **MAS side:** alert on attachment errors in server-bundle logs (`InvalidBucketName`,
  `Unable to verify integrity`, `403`, TLS handshake).
- **Cluster health:** node/SSD utilization, protection status.

## 6. Performance

- SSD metadata read/write acceleration (see §2).
- Keep directory tree depth < 275; avoid a single mega-directory (rollover).
- Size the access zone / node pool for the small-file, high-metadata attachment workload.
- Validate under expected concurrency (many bundles PUTting at once).

## 7. Configuration management & change control

- **All Manage properties documented and version-controlled**; prefer Vault/AVP-driven config over
  hand-set once validated (manual is fine for bring-up).
- **Change control** for OneFS zone settings (base-domain, ETag, ACLs) — these are shared-storage
  changes; coordinate with the storage team.
- **Restart discipline:** after property changes, Live Refresh **and restart all server-bundle pods**.
- **Version verification:** confirm behavior on your exact Manage build (8.7.24) — attachment
  layout and CR-based `attachmentProvider` support can change between releases.

## 8. Runbooks & ownership

- **Documented setup runbook** (bucket/ACL/OneFS settings) and **troubleshooting** (the 4 failure
  modes: 403, cert SAN, InvalidBucketName, MD5 ETag).
- **Clear ownership split:** storage team owns OneFS (zone settings, ACLs, quotas, snapshots);
  MAS/platform team owns Manage properties and credentials.
- **Migration plan** for existing filesystem attachments (`file2s3.sh`), tested in non-prod.

---

## Pre-production checklist

- [ ] Base domain + wildcard subdomains + wildcard DNS configured
- [ ] Cert has `*.<zone>` SAN; Manage trusts the CA
- [ ] `use-md5-for-etag=true` on the zone
- [ ] Dedicated S3 user, least-privilege bucket + filesystem ACLs
- [ ] Credentials in Vault; rotation procedure documented
- [ ] SSD metadata acceleration on the access zone
- [ ] Bucket/path rollover strategy defined (files-per-directory bounded)
- [ ] SmartQuotas + file-count/capacity alerts configured
- [ ] Snapshots/SyncIQ aligned with MAS DB backup and DR RPO/RTO
- [ ] Orphan-object reconciliation job scheduled
- [ ] Tested end to end in non-prod (upload, retrieve, migrate, restore)
- [ ] Runbook + ownership + change-control in place

---

## Top risks (watch list)

| Risk | Why it matters | Mitigation |
|---|---|---|
| Flat namespace → mega-directory | Hits 1M files/dir hard limit; perf collapse | Rollover + SSD metadata + file-count alerts |
| DB/attachment restore mismatch | Dangling or orphaned attachments | Point-in-time aligned backup of DB + PowerScale |
| Cert SAN / base-domain drift | All attachments break | Monitor cert expiry; change-control zone settings |
| Non-MD5 ETag regression | Uploads land but Manage rolls back | Keep `use-md5-for-etag=true`; alert on integrity errors |
| Credential sprawl | Security exposure | Vault-managed keys, scheduled rotation |
