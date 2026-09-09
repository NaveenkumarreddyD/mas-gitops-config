#!/usr/bin/env bash
# set-manage-asc.sh <env> — base64-encode Manage server.xml fragments and write them into the
# matching MANAGE_<BUNDLE>_ASC_B64 vars in envs/<env>.env, then optionally re-render.
#
# Each bundle's config is opt-in: only the vars you set here render (see
# base/instance/ibm-mas-masapp-configs.yaml.tpl). Map a file to a bundle with a flag.
#
# Where to keep the XML (source of truth, committed): manage-asc/<env>/
#   ui-cron.xml   -> ui + cron   (or split ui.xml / cron.xml)
#   mea.xml       -> mea
#   report.xml    -> report
#   jms.xml       -> jms server
# With no file flags, the script AUTO-DISCOVERS whatever exists in manage-asc/<env>/.
#
# Usage:
#   ./set-manage-asc.sh <env> [--render]                       # auto-discover from manage-asc/<env>/
#   ./set-manage-asc.sh <env> [--ui-cron F] [--ui F] [--cron F] \
#                             [--mea F] [--report F] [--jms F] [--render]   # explicit files
#     --ui-cron FILE   shorthand: same file for BOTH ui and cron
#     --render         run ./render.sh <env> afterwards
#
# Typical flow:
#   mkdir -p manage-asc/doc4 && cp ui-cron.xml mea.xml jms.xml manage-asc/doc4/
#   ./set-manage-asc.sh doc4 --render
#
# Notes:
#   * Client fragments (ui/cron/mea/report) point AT the jms server and are cluster-specific
#     (embed the jms service host) — use the file generated for THAT env.
#   * jms.xml is the JMS *server* fragment (wasJmsServer-1.0 + messagingEngine/queues), NOT a client.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

usage(){ cat <<'EOF'
set-manage-asc.sh — encode Manage server.xml fragments into MANAGE_<BUNDLE>_ASC_B64 env vars.

Keep readable XML per env under manage-asc/<env>/; this base64-encodes it into envs/<env>.env,
then optionally re-renders. Each bundle is opt-in — only the vars you set here render.

USAGE
  ./set-manage-asc.sh <env> [--render]                     # auto-discover manage-asc/<env>/
  ./set-manage-asc.sh <env> [FILE FLAGS...] [--render]     # explicit files

FILE FLAGS  (each takes a path to a Liberty server.xml fragment)
  --ui-cron FILE   same file for BOTH ui and cron (shorthand)
  --ui FILE        ui bundle      (JMS client)
  --cron FILE      cron bundle    (JMS client)
  --mea FILE       mea bundle     (JMS client)
  --report FILE    report bundle  (JMS client)
  --jms FILE       jms bundle     (JMS SERVER: wasJmsServer-1.0 + messagingEngine/queues)
  --render         run ./render.sh <env> after updating the env file
  -h, --help       this help

AUTO-DISCOVERY (no file flags) reads manage-asc/<env>/:
  ui-cron.xml -> ui+cron   ui.xml -> ui   cron.xml -> cron
  mea.xml -> mea   report.xml -> report   jms.xml -> jms
  Only files that exist are applied; a missing bundle stays at the operator default.

EXAMPLES
  cp cron_ui.xml manage-asc/doc4/ui-cron.xml && cp mea.xml jms.xml manage-asc/doc4/
  ./set-manage-asc.sh doc4 --render
  ./set-manage-asc.sh doc4 --ui-cron cron_ui.xml --mea mea.xml --jms jms.xml --render

Client fragments embed the cluster's jms host — keep them per-env. XML is validated before encoding.
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; "") usage >&2; exit 2 ;; esac
ENV="$1"; shift
ENVFILE="$ROOT/envs/$ENV.env"
[[ -f "$ENVFILE" ]] || { echo "ERROR: no env file: $ENVFILE" >&2; exit 2; }

# plain vars (no `declare -A` — portable to bash 3.2 / macOS)
SRC_UI=""; SRC_CRON=""; SRC_MEA=""; SRC_REPORT=""; SRC_JMS=""; RENDER=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ui)      SRC_UI="$2"; shift 2 ;;
    --cron)    SRC_CRON="$2"; shift 2 ;;
    --mea)     SRC_MEA="$2"; shift 2 ;;
    --report)  SRC_REPORT="$2"; shift 2 ;;
    --jms)     SRC_JMS="$2"; shift 2 ;;
    --ui-cron) SRC_UI="$2"; SRC_CRON="$2"; shift 2 ;;
    --render)  RENDER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; echo "run: $(basename "$0") --help" >&2; exit 2 ;;
  esac
done

# Auto-discover from manage-asc/<env>/ when no explicit file flags were given.
ASCDIR="$ROOT/manage-asc/$ENV"
if [[ -z "$SRC_UI$SRC_CRON$SRC_MEA$SRC_REPORT$SRC_JMS" ]]; then
  [[ -f "$ASCDIR/ui-cron.xml" ]] && { SRC_UI="$ASCDIR/ui-cron.xml"; SRC_CRON="$ASCDIR/ui-cron.xml"; }
  [[ -f "$ASCDIR/cron_ui.xml" ]] && { SRC_UI="$ASCDIR/cron_ui.xml"; SRC_CRON="$ASCDIR/cron_ui.xml"; }
  [[ -f "$ASCDIR/ui.xml"     ]] && SRC_UI="$ASCDIR/ui.xml"
  [[ -f "$ASCDIR/cron.xml"   ]] && SRC_CRON="$ASCDIR/cron.xml"
  [[ -f "$ASCDIR/mea.xml"    ]] && SRC_MEA="$ASCDIR/mea.xml"
  [[ -f "$ASCDIR/report.xml" ]] && SRC_REPORT="$ASCDIR/report.xml"
  [[ -f "$ASCDIR/jms.xml"    ]] && SRC_JMS="$ASCDIR/jms.xml"
  [[ -n "$SRC_UI$SRC_CRON$SRC_MEA$SRC_REPORT$SRC_JMS" ]] && echo "auto-discovered XML in $ASCDIR/"
fi
[[ -n "$SRC_UI$SRC_CRON$SRC_MEA$SRC_REPORT$SRC_JMS" ]] \
  || { echo "ERROR: nothing to do — put XML in $ASCDIR/ (ui-cron.xml, mea.xml, jms.xml, report.xml) or pass --<bundle> FILE" >&2; exit 2; }

b64(){ base64 < "$1" | tr -d '\r\n'; }   # single-line, portable (BSD/macOS + GNU/Linux)

set_var(){   # <VARNAME> <value>  — rewrite the line in place (value-safe: no sed delimiter issues)
  VARKEY="$1" VARVAL="$2" python3 - "$ENVFILE" <<'PY'
import os, sys
f = sys.argv[1]; key = os.environ["VARKEY"]; val = os.environ["VARVAL"]
lines = open(f).read().splitlines()
for i, l in enumerate(lines):
    if l.split("=", 1)[0].strip() == key:
        lines[i] = f"{key}={val}"; break
else:
    lines.append(f"{key}={val}")
open(f, "w").write("\n".join(lines) + "\n")
PY
}

apply_one(){   # <BUNDLE> <file>
  local bundle="$1" f="$2"
  [[ -z "$f" ]] && return 0
  [[ -f "$f" ]] || { echo "ERROR: file for $bundle not found: $f" >&2; exit 2; }
  # fail fast on malformed XML so we never encode a broken fragment into the config
  python3 -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$f" 2>/dev/null \
    || { echo "ERROR: $f is not well-formed XML" >&2; exit 2; }
  set_var "MANAGE_${bundle}_ASC_B64" "$(b64 "$f")"
  echo "  MANAGE_${bundle}_ASC_B64  <-  $f  ($(wc -c <"$f" | tr -d ' ') bytes)"
}

apply_one UI     "$SRC_UI"
apply_one CRON   "$SRC_CRON"
apply_one MEA    "$SRC_MEA"
apply_one REPORT "$SRC_REPORT"
apply_one JMS    "$SRC_JMS"

echo "updated $ENVFILE"
if [[ "$RENDER" == 1 ]]; then
  echo "rendering $ENV…"
  ( cd "$ROOT" && ./render.sh "$ENV" )
fi
