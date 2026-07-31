# Verified configuration controls

The mappings below were checked against the IBM MAS GitOps `8.4.0` charts and the local
`8.4.0-vault-patch` compatibility branch.

## Platform controls

| Value | Consumer | Effect |
|---|---|---|
| `rootOnly` | Platform root Helm chart | Renders only the bootstrap Application when `true`. |
| `installStage` | Platform child templates | `secrets`, `database`, or `mas`; controls installation order. |
| `enable.grafana` | Grafana Application templates | Enables the optional Grafana operator and instance. |
| `accountRoot.autoSync` | IBM account-root Application | Enables Argo CD automated sync for IBM orchestration. |
| `accountRoot.clusterAdminRole` | IBM account root | Allows cluster-scoped IBM resources. |
| `accountRoot.applicationAdminRole` | IBM account root | Allows application-scoped IBM resources. |
| `auto_delete` | Platform and IBM Applications | Enables pruning when `true`; retained as `false` for this install. |

Vault, MongoDB, and the IBM account root are mandatory and are controlled only by
`installStage`; they do not have duplicate enable switches.

## MAS controls

| Value | IBM consumer | Current value |
|---|---|---|
| `ibm_dro.run_sync_hooks` | Patched DRO post-sync Job | `true`; writes cluster-scoped DRO registration to Vault. |
| `ibm_sls.run_sync_hooks` | Patched SLS post-sync Job | `true`; writes instance-scoped SLS registration to Vault. |
| `jdbc_ssl_enabled` | `130-ibm-jdbc-config` | `false`; external Oracle uses plain TCP. |
| `ibm_mas_suite.mas_manual_cert_mgmt` | MAS Suite chart | `true`; Suite creates the core public certificate Secret from Vault values. |
| `ibm_suite_app_manage_install.mas_manual_cert_mgmt` | Manage install chart | `true`; Manage install creates its public certificate Secret. |
| Manage config `mas_manual_cert_mgmt` | Manage workspace config chart | `false`; certificate ownership stays with the install chart. |
| `autoGenerateEncryptionKeys` | `ManageWorkspace.spec.settings.deployment` | `true`; correct for a fresh database. |
| `run_sanity_test` | Manage workspace config chart | `false`; IBM post-sync sanity tests are disabled. |
| `mas.ibm.com/operationalMode` | Suite annotation and Manage jobs | `nonproduction`. |
| `mas_feature_usage` | MAS Suite chart | `true`. |
| `mas_deployment_progression` | MAS Suite chart | `true`. |
| `mas_usability_metrics` | MAS Suite chart | `true`. |

## Version controls

| Value | Consumer |
|---|---|
| `ibm_operator_catalog.mas_catalog_version` | IBM operator catalog and instance root. |
| `ibm_mas_suite.mas_channel` | MAS Suite subscription. |
| `ibm_suite_app_manage_install.mas_app_channel` | Manage subscription. |
| `ibm_sls.sls_channel` | SLS subscription. |
| Platform `source.revision` | Every IBM GitOps Application; pinned to `8.4.0-vault-patch`. |

The legacy `.env` audit found values that did not reach any chart:
`MONGO_NS`, `MAS_TARGET_VERSION`, `MANAGE_TARGET_VERSION`, and `STORAGE_CLASS`.
`MANAGE_COS_ENDPOINT` and `MANAGE_COS_BUCKET` were consumed only by helper scripts and
are intentionally not part of the fresh-install chart configuration. These dead values
were removed from `envs/drroc4.env`; the PowerScale endpoint and bucket remain in `docs/`.

## Recovery-renderer controls

Argo CD and Helm read the committed YAML under `mas/drroc4`; they do not read
`envs/drroc4.env`. The environment file and `render.py` are retained only to reproduce
that YAML if it must be rebuilt.

| Environment value | Purpose |
|---|---|
| `GITOPS_OWNS_CERT_MANAGER` | When `false`, the renderer omits `redhat-cert-manager.yaml` because cert-manager is managed outside this repository. |
| `SHARED_CLUSTER_SKIP` | Optional comma-separated list of additional cluster config files the renderer must omit. It is empty for `drroc4`. |

All remaining environment values either populate a field in the committed MAS config
YAML or control whether one of those config files is generated. They are not runtime
feature flags.
