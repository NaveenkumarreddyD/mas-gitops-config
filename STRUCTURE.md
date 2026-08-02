# Repository structure

The committed files under `<account>/<cluster>/<instance>/` are the source of truth — Argo CD
reads them directly. Their filenames are part of IBM MAS GitOps discovery: add an IBM-supported
file to enable a component, remove it to stop generating that Application.

Those files are generated from `envs/<cluster>.env` + `base/*.tpl` by `render.py`:

```bash
# edit envs/<cluster>.env, then:
./render.sh <cluster>          # writes <account>/<cluster>/<instance>/*.yaml
git diff                       # review the generated diff before committing
git add <account> envs/<cluster>.env && git commit -m "..." && git push
```

Always review the rendered diff before committing — treat the generated YAML as reviewed output,
not automatically correct.

For a **new cluster**: create `envs/<cluster>.env` (copy an existing one, update every ID,
account, domain, version, and the JMS `MANAGE_*_ASC_B64` blobs), run `./render.sh <cluster>`, review,
and commit. See the platform repo's `INSTALL.md` for the full add-a-cluster flow.
