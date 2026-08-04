#!/usr/bin/env python3
"""Render MAS GitOps config from base/ templates + envs/<cluster>.env.

IBM-aligned (hub-and-spoke): ONE config repo branch holds EVERY cluster directory.
Output is written to ./<ACCOUNT_ID>/<CLUSTER_ID>/... at the repo root - exactly what the single
Account Root Application's cluster ApplicationSet globs (<account>/*/...).

Usage:
  python3 render.py <cluster>     # render one cluster   (e.g. python3 render.py drroc4)
  python3 render.py --all         # render every envs/*.env
"""
import os, re, sys, glob

HERE = os.path.dirname(os.path.abspath(__file__))
# Supports ${VAR} (required: must be set in the env file) and ${VAR:-default} (optional: uses the
# env value if set, otherwise the inline default). Defaults let the shared template carry sensible
# per-env-overridable values (e.g. PVC sizes, replicas) without forcing every env to declare them.
VAR = re.compile(r"\$\{([A-Z0-9_]+)(?::-([^}]*))?\}")
# Conditional block: {{IF_FALSE VAR}} ... {{END_IF}} renders the body ONLY when env[VAR] is NOT
# truthy. Used for mutually-exclusive config — e.g. omit the global_secrets crypto Vault path when
# MANAGE_AUTO_GENERATE_ENCRYPTION_KEYS=true (MAS generates its own keys, so providing them is
# redundant and would add an unwanted AVP dependency on the manage-crypto secret).
IF_FALSE = re.compile(r"^[ \t]*\{\{IF_FALSE ([A-Z0-9_]+)\}\}[ \t]*\n(.*?)\n[ \t]*\{\{END_IF\}\}[ \t]*\n", re.DOTALL | re.MULTILINE)
# {{IF_TRUE VAR}} ... {{END_IF}} renders the body ONLY when env[VAR] IS truthy (the mirror of
# IF_FALSE). Used e.g. to include the manual tls_cert/tls_key/ca_cert lines only when
# MAS_MANUAL_CERT_MGMT=true; when false, MAS auto-generates a self-signed core cert.
IF_TRUE = re.compile(r"^[ \t]*\{\{IF_TRUE ([A-Z0-9_]+)\}\}[ \t]*\n(.*?)\n[ \t]*\{\{END_IF\}\}[ \t]*\n", re.DOTALL | re.MULTILINE)
# {{IF_SET VAR}} ... {{END_IF}} renders the body ONLY when env[VAR] has a non-empty value. Unlike
# IF_TRUE (which needs a boolean 1/true/yes), this is "opt-in when a value is passed" — e.g. a
# per-bundle server.xml base64 that renders its Secret + additionalServerConfig only when supplied;
# left empty, the bundle falls back to the Manage operator default.
IF_SET = re.compile(r"^[ \t]*\{\{IF_SET ([A-Z0-9_]+)\}\}[ \t]*\n(.*?)\n[ \t]*\{\{END_IF\}\}[ \t]*\n", re.DOTALL | re.MULTILINE)

# Fully declarative: every cluster/instance config + app renders for every cluster. There are NO
# ENABLE_* staging toggles. Runtime-dependent configs (SLSCfg/BASCfg) simply sit Degraded until
# their registration is harvested into Vault, then converge. The only things that suppress a file
# are GITOPS_OWNS_CERT_MANAGER (environmental: don't install cert-manager if the cluster has it)
# and SHARED_CLUSTER_SKIP (low-level override).

def load_env(path):
    env = {}
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            v = re.sub(r"\s+#.*$", "", v).strip()   # strip inline comments (e.g. VAL  # note)
            env[k.strip()] = v
    return env

def strip_conditionals(text, env):
    # {{IF_SET VAR}} keeps its body only when VAR has a non-empty value (opt-in when passed).
    text = IF_SET.sub(lambda m: m.group(2) + "\n" if env.get(m.group(1), "").strip() else "", text)
    # {{IF_TRUE VAR}} keeps its body only when VAR is truthy; {{IF_FALSE VAR}} only when it is NOT.
    text = IF_TRUE.sub(lambda m: m.group(2) + "\n" if truthy(env.get(m.group(1), "")) else "", text)
    return IF_FALSE.sub(lambda m: "" if truthy(env.get(m.group(1), "")) else m.group(2) + "\n", text)

def render(text, env, src):
    text = strip_conditionals(text, env)
    # Only vars WITHOUT an inline default are required. ${VAR:-default} is always satisfiable.
    missing = sorted({m.group(1) for m in VAR.finditer(text)
                      if m.group(1) not in env and m.group(2) is None})
    if missing: sys.exit(f"ERROR: {src}: unset variables {missing}")
    rendered = VAR.sub(lambda m: env[m.group(1)] if m.group(1) in env else m.group(2), text)
    # Defensive: fail loudly if any ${...} survived (e.g. rendered by an OLD render.py without
    # ${VAR:-default} support). An unsubstituted placeholder produces invalid YAML that ArgoCD's
    # ApplicationSet generator rejects ("did not find expected ',' or '}'"). Note: AVP secret refs
    # use <path:...>, not ${...}, so they are unaffected.
    leftover = sorted(set(re.findall(r"\$\{[^}]*\}", rendered)))
    if leftover:
        sys.exit(f"ERROR: {src}: unsubstituted placeholders remain: {leftover} "
                 f"(update render.py — it needs ${{VAR:-default}} support)")
    if "CHANGE_ME" in rendered:
        bad = sorted({line.strip() for line in rendered.splitlines() if "CHANGE_ME" in line})
        sys.exit(f"ERROR: {src}: rendered output still contains placeholders: {bad}")
    return rendered

def truthy(value):
    return str(value).lower() in ("1", "true", "yes")

def write(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)
    if mode: os.chmod(path, mode)


def render_one(name):
    envfile = os.path.join(HERE, "envs", f"{name}.env")
    if not os.path.exists(envfile): sys.exit(f"no env file: {envfile}")
    env = load_env(envfile); cid, iid = env["CLUSTER_ID"], env["INSTANCE_ID"]
    # Top-level output dir is the ACCOUNT_ID, not a literal "mas". Per-env accounts
    # (e.g. roc4, doc4) render under their own account dir so each cluster's ArgoCD
    # Account Root App globs only its own subtree ("<account>/*/..."). account=mas
    # still renders to mas/ (backward compatible).
    acct = env["ACCOUNT_ID"]
    # Cluster-scoped ownership is explicit. If another platform process owns one
    # of these resources, do not render its file; IBM account-root gates those
    # Applications on file presence. SHARED_CLUSTER_SKIP remains as a low-level
    # compatibility override for any additional files that must be suppressed.
    skip = {s.strip() for s in env.get("SHARED_CLUSTER_SKIP", "").split(",") if s.strip()}
    if not truthy(env.get("GITOPS_OWNS_CERT_MANAGER", "true")):
        skip.add("redhat-cert-manager.yaml")
    # clean stale rendered output so removed templates don't leave orphan files
    import glob as _g
    for f in _g.glob(os.path.join(HERE, acct, cid, "*.yaml")) + _g.glob(os.path.join(HERE, acct, cid, iid, "*.yaml")):
        os.remove(f)
    skipped = []
    for tpl in sorted(os.listdir(os.path.join(HERE, "base", "cluster"))):
        out = tpl[:-4]
        if out in skip:
            skipped.append(out); continue
        write(os.path.join(HERE, acct, cid, out),
              render(open(os.path.join(HERE, "base", "cluster", tpl)).read(), env, tpl))
    for tpl in sorted(os.listdir(os.path.join(HERE, "base", "instance"))):
        out = tpl[:-4]
        write(os.path.join(HERE, acct, cid, iid, out),
              render(open(os.path.join(HERE, "base", "instance", tpl)).read(), env, tpl))
    all_skipped = skipped
    note = f"  (skipped {', '.join(all_skipped)})" if all_skipped else ""
    print(f"Rendered {name} -> {acct}/{cid}/{note}  (secret values remain in Vault)")

def main():
    if len(sys.argv) != 2: sys.exit("usage: python3 render.py <cluster>|--all")
    if sys.argv[1] == "--all":
        for f in sorted(glob.glob(os.path.join(HERE, "envs", "*.env"))):
            render_one(os.path.basename(f)[:-4])
    else:
        render_one(sys.argv[1])

if __name__ == "__main__":
    main()
