#!/usr/bin/env bash
# harness-handoff-render -- thin wrapper over .harness/scripts/lib/harness_handoff_gen.py
# (C7 twin: powershell/harness-handoff-render.ps1).
#   render [ROOT] [--write] [--no-ci] [--no-doctor] [--fleet BASE]
#   check  [ROOT] [--json]
LIB="$(cd "$(dirname "$0")" && pwd)/../lib/harness_handoff_gen.py"
[ -f "$LIB" ] || { echo "[handoff] missing $LIB"; exit 1; }
PY=""
for n in python3 python py; do
    if command -v "$n" >/dev/null 2>&1; then PY="$n"; break; fi
done
[ -n "$PY" ] || { echo "[handoff] no python on PATH"; exit 1; }
CMD="${1:-render}"; shift || true
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then ROOT="$1"; shift; fi
"$PY" "$LIB" "$CMD" "$ROOT" "$@"
