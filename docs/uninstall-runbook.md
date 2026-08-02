# Delete & reinstall a MAS instance

IBM's way: **remove config files → Argo CD prunes them.** Example uses `doc4` / `docapp` —
substitute your cluster/instance. Vault is kept, so reinstall is fast.

```bash
refresh(){ oc annotate application ibm-mas-account-root -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite; }
```

---

## Delete (IBM way)

### 1. Turn pruning on

Removing a file does nothing unless pruning is on (`auto_delete: false` by default). The account-root
is applied **once**, so editing code doesn't update it — change it on the cluster:

```bash
oc edit application ibm-mas-account-root -n openshift-gitops
#   under spec.source.helm.values, set:   auto_delete: true
```

Also set it in git so future re-applies keep it:

```bash
cd platform-gitops
sed -i 's/^auto_delete: false/auto_delete: true/' gitops/values.yaml
git commit -am "enable auto_delete for teardown" && git push
```

### 2. Remove the config files (reverse order)

```bash
cd ../mas-gitops-config
git rm -r doc4/doc4/docapp && git commit -m "doc4: remove instance" && git push
refresh
oc get suites,workspaces,manageapps,manageworkspaces,mongocfgs,slscfgs,jdbccfgs,bascfgs -A -w   # → all empty
```

Removing the whole cluster too? Also remove the cluster files:

```bash
git rm doc4/doc4/ibm-dro.yaml doc4/doc4/ibm-mas-cluster-base.yaml doc4/doc4/ibm-operator-catalog.yaml
git commit -m "doc4: remove cluster config" && git push && refresh
```

### 3. Remove the platform apps (not IBM config)

```bash
oc delete application ibm-mas-account-root mongodb mongodb-operator -n openshift-gitops
```

### 4. Verify it's gone

```bash
oc get applications -n openshift-gitops | grep -Ei 'doc4|docapp|manage|mongodb'
oc get suites,workspaces,manageapps,manageworkspaces -A
oc get ns | grep -E 'mas-docapp|mongo-gitops|ibm-software-central'
```

All empty. **Keep `envs/doc4.env`** and **keep Vault** — you need both to reinstall.

---

## Bring it back (reinstall — Vault kept)

### 1. Re-render the config

```bash
cd mas-gitops-config
./render.sh doc4
git add doc4 && git commit -m "re-render doc4" && git push
```

### 2. Put `auto_delete` back to false

```bash
cd ../platform-gitops
sed -i 's/^auto_delete: true/auto_delete: false/' gitops/values.yaml
git commit -am "restore auto_delete: false" && git push
```

### 3. Verify Vault still seeded (skip re-seed if PASS)

```bash
export VAULT_ROOT_TOKEN="$(jq -r .root_token ~/vault-init-doc4.json)"
./bootstrap/12-vault-verify.sh doc4        # PASS = secrets intact
```

### 4. Redeploy

```bash
oc get crd certificates.cert-manager.io >/dev/null 2>&1 || ./bootstrap/05-operators.sh doc4
./bootstrap/20-mongodb.sh doc4             # wait until Running (fresh DB)
./bootstrap/30-mas.sh doc4
./scripts/status.sh doc4
```

---

## Notes

- **Force-refresh** skips the ~3 min git poll; the actual teardown still takes its own time — watch `-w`.
- Argo CD reads **GitLab**; you push to **GitHub**. Confirm each push reached GitLab before refreshing:
  `git ls-remote https://gitlab.lac1.biz/gitops/mas-gitops-config.git refs/heads/mas-vault-deploy`
- **Vault kept** = same secrets, no re-seed. **Mongo redeployed** = empty DB (new encryption keys) = true fresh MAS.
- Finalizers clear via the operators (not stripped) — go layer-by-layer if one gets stuck in `Terminating`.
- **Force teardown** (strips finalizers, one shot): `platform-gitops/scripts/delete-fast.sh --confirm doc4`.
