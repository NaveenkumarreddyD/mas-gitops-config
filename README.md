# MAS GitOps configuration

Per-env MAS configuration read by IBM MAS GitOps ApplicationSets. It follows IBM's
`<account>/<cluster>/<instance>` hierarchy and `merge-key` convention.

Each env runs on its own cluster with its own Argo CD and a **unique account** (convention:
`account == clusterId`). The account-root globs `<account>/*/…`, so each env's Argo CD only ever
sees its own subtree — that isolation is why the top-level dir is the account, not a shared `mas/`.

```text
drroc4/                          # account (= clusterId)
  drroc4/                        # cluster
    ibm-mas-cluster-base.yaml    # cluster-scoped config
    ibm-operator-catalog.yaml
    ibm-dro.yaml
    drrocapp/                    # instance
      ibm-mas-instance-base.yaml
      ibm-sls.yaml
      ibm-mas-suite.yaml
      ibm-mas-suite-configs.yaml
      ibm-mas-workspaces.yaml
      ibm-mas-masapp-manage-install.yaml
      ibm-mas-masapp-configs.yaml
roc4/…  nroc4/…  doc4/…          # the other envs, same shape
base/, envs/, render.py          # generator: envs/<cluster>.env + base/*.tpl -> the committed YAML
```

Argo CD reads **only** the committed `<account>/…` YAML. `render.py` (via `render.sh`) generates it
from `envs/<cluster>.env`:

```bash
# edit envs/<cluster>.env, then:
./render.sh <cluster>            # writes <account>/<cluster>/<instance>/*.yaml
git add <account> envs/<cluster>.env && git commit -m "..." && git push
```

IBM's account root reads:

- `<account>/<cluster>/*.yaml` — cluster-scoped configuration.
- `<account>/<cluster>/<instance>/*.yaml` — instance-scoped configuration.

Secrets are references only: AVP resolves `<path:secret/data/<account>/<cluster>/…>` from Vault at
sync time. Never commit secret values.

The end-to-end installation procedure is in the platform repository's `INSTALL.md`.
