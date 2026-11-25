#!/usr/bin/env bash
# harnessd -- thin wrapper over .harness/scripts/lib/harnessd.py (C7 twin: powershell/harnessd.ps1).
#   ensure | start | stop | status | bench [n] | serve
# Wired at SessionStart and UserPromptSubmit as `ensure`: starts the resident daemon that serves
# the PreToolUse / PostToolUse http hooks when it is not running. Silent when already healthy.
# Never fails the hook.
LIB="$(cd "$(dirname "$0")" && pwd)/../lib/harnessd.py"
[ -f "$LIB" ] || exit 0
PY=""
for n in python3 python py; do
    if command -v "$n" >/dev/null 2>&1; then PY="$n"; break; fi
done
[ -n "$PY" ] || exit 0
"$PY" "$LIB" "$@"
exit $?
