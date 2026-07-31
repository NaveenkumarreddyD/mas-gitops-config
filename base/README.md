# `base/` template contract

Templates here are rendered by `render.py` (`${VAR}` required, `${VAR:-default}` optional) into
`mas/<cluster>/...` and read by ArgoCD. Templates are kept **comment-free**; the non-obvious rules
that, if broken, cause **silent failures** are recorded here instead.

## AVP secret references — do not treat `#` as a comment
Lines like `"<path:secret/data/<acct>/<cluster>/<inst>/manage-crypto#cryptoKey>"` use `#` as the
**key separator inside the secret reference**. It is part of the value, not a comment. Never strip
`#` from `<path:...>` lines (any comment-removal tooling must skip lines containing `<path:`).

## ManageWorkspace (`ibm-mas-masapp-configs.yaml.tpl`)
- **`serverBundles` and `persistentVolumes` MUST be nested under `settings.deployment`.** The
  ManageWorkspace CRD only reads them there. Placed one level up (under `settings`) they are
  **silently dropped** — the operator then defaults to **AIO (a single `all` server)** and creates
  **no PVCs**. Symptom: "no ui/cron/mea pods, no PVCs."
- **Split bundles require `settings.aio.install: false`.** With AIO on (or no serverBundles), all
  bundles collapse into one `all` server.
- **Designate targets explicitly in split mode** (AIO did this automatically on the `all` server):
  - `isUserSyncTarget: true` — must be on an `all` or `mea` bundle (else the vmanage webhook denies:
    "at least one server bundle with bundle type all or mea must be selected to synchronize users").
  - `isMobileTarget: true` — the bundle Maximo Mobile connects to (we use the `ui` bundle).
- **Components use `version: latest`** (`base`/`utilities`/`spatial`). The operator resolves each to
  the version shipped in the pinned catalog. Do NOT pin an add-on to the Manage version number
  (e.g. Spatial `8.7.24` is not a real Spatial release → webhook rejection). NOTE: with `base: latest`
  a catalog bump will let Manage follow the new version and run a maxinst schema upgrade — control
  that via the catalog tag + a DB backup, not a base pin.
- **`autoGenerateEncryptionKeys` is `${MANAGE_AUTO_GENERATE_ENCRYPTION_KEYS}`** (env-controlled).
  Reused DB / prod → set `false` and provide the original keys (`ALLOW_CUSTOM_MANAGE_CRYPTO_KEYS=true`).
  Fresh DB → `true`. After install, `scripts/backup-manage-secrets.sh` backs up the live crypto keys +
  admin superuser into Vault for reproducibility.
- **Attachments use external storage** → no `/DOCLINKS` PVC. Only `jmsstore` (JMS persistence) and
  `globaldir` (shared dir) need local RWX volumes. If you switch to a mounted external share for
  attachments, add a `persistentVolumes` entry pointing at it.

## Per-env overrides (no env-file bloat)
Use `${VAR:-default}` so the template carries a default and an env sets the var only to override:
- `MANAGE_JMSSTORE_SIZE` / `MANAGE_GLOBALDIR_SIZE` — PVC sizes (default `20Gi`). PVCs can grow
  (StorageClass must allow expansion) but **cannot shrink**.

## Admin login
The MAS admin user is the **operator-generated** secret `${INSTANCE_ID}-credentials-superuser` in the
core namespace. We do NOT generate a superuser; `backup-manage-secrets.sh` copies the operator's value
into Vault `secret/<IP>/superuser` post-install.
