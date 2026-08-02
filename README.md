# MAS GitOps configuration

This repository contains the values discovered by IBM MAS GitOps ApplicationSets.
It follows IBM's directory and `merge-key` convention directly. Installation reads
the committed `mas/` YAML and does not run a local template generator.

```text
mas/
  drroc4/
    ibm-mas-cluster-base.yaml
    ibm-operator-catalog.yaml
    ibm-dro.yaml
    drgitopsapp/
      ibm-mas-instance-base.yaml
      ibm-sls.yaml
      ibm-mas-suite.yaml
      ibm-mas-suite-configs.yaml
      ibm-mas-workspaces.yaml
      ibm-mas-masapp-manage-install.yaml
      ibm-mas-masapp-configs.yaml
docs/
base/, envs/, render.py  # retained recovery tooling; not part of installation
```

Edit the YAML under `mas/`, validate it, and commit it. IBM's account root reads:

- `mas/<cluster>/*.yaml` for cluster-scoped configuration.
- `mas/<cluster>/<instance>/*.yaml` for instance-scoped configuration.

Secrets are references only. During the temporary Vault implementation, AVP resolves
`<path:secret/data/...>` placeholders. Never commit secret values.

The end-to-end installation procedure is in the platform repository's `INSTALL.md`.
