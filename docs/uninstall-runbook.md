# MAS uninstall runbook — IBM's way (config removal + prune)

End-to-end teardown of ONE instance the IBM way: you remove config files and Argo CD deprovisions.
Example uses **doc4 / docapp** — substitute your `<cluster>`/`<instance>`. Mongo runs in `mongo-gitops`.

**How this works:** MAS resources are tied to their config files. Delete a file → Argo CD prunes the
resources (when pruning is on) → PostDelete hooks delete Suite-owned CRs (`MongoCfg`, etc.) that Argo
CD can't prune. Argo CD polls git every ~3 min; a **forced refresh** makes it act immediately.

> **The GitHub → GitLab hop:** Argo CD reads **GitLab**, but you push to **GitHub**. A forced refresh
> only helps once the commit is on GitLab. After each push, confirm it landed before refreshing:
> ```bash
> git ls-remote https://gitlab.lac1.biz/gitops/mas-gitops-config.git refs/heads/mas-vault-deploy
> ```

Handy alias for the forced refresh:
```bash
refresh(){ oc annotate application "$1" -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite; }
```

---

## Phase 0 — Back up + confirm target

```bash
oc exec -n vault vault-0 -- env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$VAULT_ROOT_TOKEN" \
  vault operator raft snapshot save /tmp/doc4.snap
oc cp vault/vault-0:/tmp/doc4.snap ~/doc4-vault.snap        # keep the Vault snapshot
# back up MongoDB data if it matters, then inventory:
oc get suites,workspaces,manageapps,manageworkspaces -A
```

## Phase 1 — Enable pruning (required; `auto_delete` is off by default)

Removing a file does nothing until pruning is on. Flip it, push, refresh:

```bash
cd platform-gitops
sed -i 's/^auto_delete: false/auto_delete: true/' gitops/values.yaml
git commit -am "doc4 teardown: enable auto_delete" && git push
refresh ibm-mas-account-root
```

## Phase 2 — Remove MAS config in reverse install order

From `mas-gitops-config`, delete each layer, **push, refresh, then watch it clear** before the next.

```bash
cd ../mas-gitops-config
D=doc4/doc4/docapp

git rm $D/ibm-mas-masapp-configs.yaml && git commit -m "rm manage-configs" && git push
refresh ibm-mas-account-root
oc get manageworkspaces -A -w                     # → empty, then Ctrl-C

git rm $D/ibm-mas-masapp-manage-install.yaml && git commit -m "rm manage-install" && git push
refresh ibm-mas-account-root
oc get manageapps -A -w                           # → empty (mas-docapp-manage drains)

git rm $D/ibm-mas-workspaces.yaml && git commit -m "rm workspace" && git push
refresh ibm-mas-account-root
oc get workspaces.core.mas.ibm.com -A -w          # → empty

git rm $D/ibm-mas-suite-configs.yaml && git commit -m "rm suite-configs" && git push
refresh ibm-mas-account-root
oc get mongocfgs,jdbccfgs,slscfgs,bascfgs.config.mas.ibm.com -A -w   # → empty (PostDelete hooks)

git rm $D/ibm-mas-suite.yaml && git commit -m "rm suite" && git push
refresh ibm-mas-account-root
oc get suites -A -w                               # → empty (mas-docapp-core drains)

git rm $D/ibm-sls.yaml && git commit -m "rm sls" && git push
refresh ibm-mas-account-root
oc get licenseservices.sls.ibm.com -A -w          # → empty (mas-docapp-sls drains)

git rm $D/ibm-mas-instance-base.yaml && git commit -m "rm instance-base" && git push
refresh ibm-mas-account-root                      # → instance-root app removed
```

Cluster-scoped files (only if removing the whole cluster deployment, not just the instance):

```bash
C=doc4/doc4
git rm $C/ibm-dro.yaml $C/ibm-mas-cluster-base.yaml $C/ibm-operator-catalog.yaml
git commit -m "rm cluster-scoped config" && git push
refresh ibm-mas-account-root                      # → DRO, catalog, cluster-root app removed
```

> **Faster full wipe:** `git rm -r doc4/doc4/docapp` (+ the cluster files) in one commit, push once,
> `refresh ibm-mas-account-root`, then watch everything drain in reverse-wave order. Layer-by-layer
> above is just easier to follow.

## Phase 3 — Remove the platform layers (your side, not IBM config)

These Applications come from `platform-gitops`, so delete them directly:

```bash
oc delete application ibm-mas-account-root -n openshift-gitops    # IBM account-root
oc delete application mongodb mongodb-operator -n openshift-gitops
oc get ns mongo-gitops -w                                        # drains

# Optional — only if fully decommissioning:
# oc delete application vault -n openshift-gitops ; oc delete ns vault     (loses seeded secrets!)
# oc delete application operators -n openshift-gitops                       (cert-manager is cluster-shared — usually keep)
```

## Phase 4 — Verify nothing is left

```bash
oc get applications,applicationsets -n openshift-gitops | grep -Ei 'doc4|docapp|manage|mongodb'
oc get suites,workspaces,manageapps,manageworkspaces -A
oc get mongocfgs,jdbccfgs,slscfgs,bascfgs.config.mas.ibm.com -A
oc get licenseservices.sls.ibm.com -A
oc get ns | grep -E 'mas-docapp|mongo-gitops|ibm-software-central'
oc get csv -A | grep -Ei 'ibm-mas|ibm-sls|manage'
```

All empty. Notes:
- **CRDs persist** (`oc get crd | grep mas.ibm.com`) — cluster-wide; removed only by uninstalling the
  MAS operators cluster-wide. Harmless; reused on reinstall.
- **Namespace stuck `Terminating`** → a finalizer didn't clear; inspect `oc get ns <ns> -o json | jq .status`.

## Phase 5 — Restore the safe setting

If the platform stays (redeploy later), put pruning back to production-safe:

```bash
cd ../platform-gitops
sed -i 's/^auto_delete: true/auto_delete: false/' gitops/values.yaml
git commit -am "restore auto_delete: false" && git push
```

---

## Reinstalling later

Deleting the rendered files does **not** touch the source (`envs/<cluster>.env` + `base/*.tpl`), so you
can regenerate anytime — **don't delete `envs/doc4.env`**:

```bash
cd mas-gitops-config
./render.sh doc4
git add doc4 && git commit -m "re-render doc4" && git push
```

Vault is preserved through this teardown, so the seeded secrets survive — the reinstall skips seeding
and just syncs (or re-run from `platform-gitops/bootstrap/20-mongodb.sh doc4` if you also removed Mongo).

## Two waits to keep separate

- **Git detection (~3 min poll)** — skip it with `refresh <app>` after the commit reaches GitLab.
- **Deprovision time** — the real teardown (finalizers, PostDelete hooks, namespace drain); varies by
  layer (Manage is minutes). Forcing a refresh does not speed this up — watch `oc get … -w`.

For a throwaway/recreate, `platform-gitops/scripts/delete-fast.sh <cluster>` does all of this by force
in one shot. Use this graceful path for production.
