# MAS GitOps uninstall planning

Uninstall is intentionally not automated in this repository. `auto_delete` is `false`,
and IBM resources have finalizers and post-delete hooks that must be allowed to complete.

Before any uninstall, create an approved change plan containing:

1. A Vault Raft snapshot and database backup.
2. An inventory of Applications and namespaces owned by `drgitopsapp`.
3. Confirmation whether MongoDB and DRO are dedicated or shared.
4. The IBM-supported deletion order for ManageWorkspace, ManageApp, Workspace, Suite,
   instance root, and cluster root.
5. Stop conditions for failed finalizers; never clear finalizers without reviewing the
   owning operator and the resources it is protecting.

Inventory commands are read-only:

```bash
oc get applications -n openshift-gitops
oc get manageapps,manageworkspaces -A
oc get suites.core.mas.ibm.com,workspaces.core.mas.ibm.com -A
oc get namespaces | grep -E 'mas-drgitopsapp|mongo-drgitops|ibm-software-central'
```

Do not delete Vault, cert-manager, OpenShift GitOps, the IBM operator catalog, or DRO
unless the approved plan confirms they are not shared and their backups are verified.
