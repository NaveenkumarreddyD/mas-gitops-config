
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
python3 render.py "${1:---all}"
