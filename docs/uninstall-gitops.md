# MAS GitOps uninstall

Use IBM's normal GitOps deletion flow. Do not use force deletion for a production
environment unless IBM Support has reviewed the failed finalizer.

Before starting:

1. Back up the application database and confirm it can be restored.
2. Back up Manage encryption keys and attachment data.
3. Record the current AWS Secrets Manager version IDs for all environment secrets.
4. Inventory applications, custom resources, namespaces, and persistent volumes.
5. Disable automated sync on the account root while the change is reviewed.

```bash
oc get applications,applicationsets -n openshift-gitops
oc get suites,workspaces,manageapps,manageworkspaces -A
oc get mongocfgs,jdbccfgs,slscfgs,bascfgs.config.mas.ibm.com -A
oc get licenseservices.sls.ibm.com -A
oc get pvc -A
```

Remove instance files in reverse dependency order:

| Order | File |
|---|---|
| 1 | `ibm-mas-masapp-configs.yaml` |
| 2 | `ibm-mas-masapp-manage-install.yaml` |
| 3 | `ibm-mas-workspaces.yaml` |
| 4 | `ibm-mas-suite-configs.yaml` |
| 5 | `ibm-mas-suite.yaml` |
| 6 | `ibm-sls.yaml` |
| 7 | `ibm-mas-instance-base.yaml` |

Commit and push each reviewed stage, then sync the affected application with pruning.
Allow IBM's PostDelete hooks and operator finalizers to finish before continuing.

Remove cluster-level files such as `ibm-dro.yaml`,
`ibm-operator-catalog.yaml`, and `ibm-mas-cluster-base.yaml` only when no other
instance uses that cluster.

After removal, verify no instance resources remain:

```bash
oc get applications,applicationsets -n openshift-gitops
oc get suites,workspaces,manageapps,manageworkspaces -A
oc get mongocfgs,jdbccfgs,slscfgs,bascfgs.config.mas.ibm.com -A
oc get licenseservices.sls.ibm.com -A
```

Do not delete shared OpenShift GitOps, cert-manager, storage classes, or cluster-wide CRDs.
Retain AWS Secrets Manager entries through the rollback window so a rebuild can reuse the
database credentials, certificates, and Manage encryption keys.
