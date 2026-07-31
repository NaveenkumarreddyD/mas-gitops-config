# Repository structure

The committed files under `mas/` are the source of truth. Their filenames are part of
IBM MAS GitOps discovery, so add an IBM-supported file to enable a component and remove
that file to stop generating its Application.

For a new cluster, copy an existing cluster directory, update every ID, namespace,
domain, version, and Vault path, then validate the resulting YAML before committing.
Do not introduce an `.env` renderer; it hides which values Argo CD actually consumes.

`base/`, `envs/`, and `render.py` are retained only as recovery history. They are not
called by the installation. If they are ever used deliberately, review and commit the
generated diff instead of treating generated output as automatically correct.
