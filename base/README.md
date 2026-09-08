# Template contract

`render.py` combines `base/*.tpl` with `envs/<cluster>.env` and writes the committed
IBM configuration under `<account>/<cluster>/<instance>`.

Secret values never belong in this repository. A value such as
`<path:<account>/<cluster>/<instance>/jdbc-system#password>` is resolved from AWS
Secrets Manager by Argo CD. The `#` separates the JSON field from the secret name and
must not be stripped as a YAML comment.

## ManageWorkspace rules

- `serverBundles` and `persistentVolumes` must be nested under
  `settings.deployment`. Other locations are silently ignored by the CRD.
- Split bundles require `settings.aio.install: false`.
- Split mode needs an explicit `isUserSyncTarget` on an `all` or `mea` bundle and an
  explicit `isMobileTarget` on the mobile-facing bundle.
- Component `version: latest` means the version supplied by the pinned Manage catalog,
  not an unrestricted image upgrade. Control upgrades with the catalog pin and a database
  backup.
- A fresh database may use `MANAGE_AUTO_GENERATE_ENCRYPTION_KEYS=true`. A reused database
  must use its original keys: set the value to `false` and create the `manage-crypto`
  AWS secret before deployment.

## Attachment storage

`MANAGE_ATTACHMENT_PROVIDER` controls the rendered storage:

- `filestorage`: file provider plus an RWX PVC at `/doclinks`.
- `s3-migration`: keeps `/doclinks` and imports the PowerScale S3 CA chain.
- `s3`: imports the CA chain without the legacy attachment PVC.
- unset: no attachment-provider override.

Manage 8.7.24 still requires the `mxe.cos*` application properties described in
`docs/manage-attachments-powerscale-s3.md`.

PVC sizes are controlled by `MANAGE_JMSSTORE_SIZE`, `MANAGE_GLOBALDIR_SIZE`, and
`MANAGE_DOCLINKS_SIZE`. PVCs may be expanded when the storage class allows it; they
cannot be shrunk.

Run `./render.sh <cluster>` after every environment change and review both the template
and generated-file diff before commit.
