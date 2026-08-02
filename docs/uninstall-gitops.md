# MAS GitOps uninstall

Two paths. Pick by intent:

- **A. Graceful (IBM's model)** — delete config files → sync with prune. For production or removing
  one piece from a running install. Lets finalizers and PostDelete hooks run.
- **B. Fast (`delete-fast.sh`)** — full wipe of one instance for a clean recreate on a dedicated
  cluster. Pauses Argo CD and force-removes; bypasses IBM's hooks.

Replace `<cluster>`/`<instance>` with your values (e.g. `drroc4`/`drrocapp`, `doc4`/`docapp`).
Mongo runs in the common `mongo-gitops` namespace.

## Before either path

1. **Vault Raft snapshot** + database backup (RUNBOOK "Vault backup").
2. Inventory (read-only):
   ```bash
   oc get applications,applicationsets -n openshift-gitops
   oc get suites,workspaces,manageapps,manageworkspaces -A
   oc get mongocfgs,jdbccfgs,slscfgs,bascfgs.config.mas.ibm.com -A
   oc get ns | grep -E 'mas-<instance>|mongo-gitops|ibm-software-central'
   ```
3. Confirm Mongo/DRO/Vault are dedicated (per-cluster here) before removing them.

## A. Graceful uninstall (IBM's approach)

Because `auto_delete: false` (prune off), Argo CD will **not** auto-deprovision. IBM's model is:
delete the config files from this repo in **reverse install order**, push, then **manually
sync-with-prune**. Suite-owned CRs (`MongoCfg`, `SlsCfg`, `JdbcCfg`, `BasCfg`, …) can't be pruned
by Argo CD — IBM's **PostDelete hook Jobs** `oc delete` them when their config file is removed
(requires `use_postdelete_hooks: true`).

Delete the files under `<account>/<cluster>/<instance>/` in this order, committing + pushing each:

| # | Remove file | Removes |
|---|---|---|
| 1 | `ibm-mas-masapp-configs.yaml` | ManageWorkspace + Manage app configs |
| 2 | `ibm-mas-masapp-manage-install.yaml` | ManageApp |
| 3 | `ibm-mas-workspaces.yaml` | Workspace |
| 4 | `ibm-mas-suite-configs.yaml` | MongoCfg / JdbcCfg / SlsCfg / BasCfg (via PostDelete hooks) |
| 5 | `ibm-mas-suite.yaml` | Suite |
| 6 | `ibm-sls.yaml` | LicenseService |
| 7 | `ibm-mas-instance-base.yaml` | the instance root |
| 8 | cluster files (`ibm-dro.yaml`, `ibm-mas-cluster-base.yaml`, `ibm-operator-catalog.yaml`) | cluster-scoped pieces |

After each push, trigger a prune sync of the affected app (Argo CD UI **Sync → Prune**, or):

```bash
oc patch application <app-name> -n openshift-gitops --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'
```

Wait for each layer to clear before removing the next. Never strip a finalizer without reviewing
the owning operator.

## B. Fast teardown (`delete-fast.sh`)

For a full recreate on a dedicated cluster. It pauses Argo CD, deletes ApplicationSets then
Applications (by IBM labels), purges OLM, strips finalizers, deletes the namespaces
(`mas-<instance>-*`, `mongo-gitops`, `ibm-software-central`), sweeps the catalog + instance RBAC,
restores Argo CD, and re-verifies.

```bash
cd ../platform-gitops
./scripts/delete-fast.sh <cluster>              # DRY RUN — prints what would be deleted
./scripts/delete-fast.sh --confirm <cluster>    # delete (Vault preserved; add --include-vault to remove it)
```

⚠️ Deletes MongoDB **data** (the `mongo-gitops` PVCs). Vault is preserved by default, so seeded
secrets survive a recreate.

## Verify nothing is left

```bash
oc get applications,applicationsets -n openshift-gitops | grep -Ei '<cluster>|<instance>|manage'
oc get suites,workspaces,manageapps,manageworkspaces -A
oc get mongocfgs,jdbccfgs,slscfgs,bascfgs.config.mas.ibm.com -A
oc get licenseservices.sls.ibm.com -A
oc get ns | grep -E 'mas-<instance>|mongo-gitops|ibm-software-central'
oc get csv -A | grep -Ei 'ibm-mas|ibm-sls|manage'
```

All should return empty. Two notes:

- **CRDs persist** (`oc get crd | grep mas.ibm.com`) — cluster-wide, removed only if you uninstall
  the operators cluster-wide. Harmless; reused on reinstall.
- **Namespace stuck `Terminating`** = a finalizer didn't clear. `delete-fast.sh` force-finalizes;
  otherwise inspect `oc get ns <ns> -o json | jq .status` for the blocker.

## Do not delete unless the plan confirms they are not shared

Vault, cert-manager, OpenShift GitOps. On these single-instance clusters the operator catalog,
DRO, and Mongo are per-cluster, so removing them with the instance is expected.
