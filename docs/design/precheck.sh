#!/usr/bin/env bash
# Voorcontrole voor elk Swift-bestand dat je aanraakt (docs/design/plan.md par. 6.1 en 7.1).
# Drie controles: 1. syntaxis (tree-sitter), 2. ViewBuilder-limiet (meer dan 9 statements in een closure),
# 3. ontwerpcontrole (design-checks.sh) op precies deze bestanden.
# Dit is GEEN compileerbewijs: de poort is de CI-build (par. 7.1). Het vangt wel syntaxisfouten en een VStack met 11 kinderen.
# Gebruik: docs/design/precheck.sh <bestand.swift> [...]      Omgeving: MYBUDDY_VENV (map met bin/python en tree_sitter)
HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="${MYBUDDY_VENV:-/tmp/claude-0/-home-user-MyBuddy/9beb118c-8e88-5a84-a4b5-426733aaf64d/scratchpad/venv}"
[ "$#" -gt 0 ] || { echo "gebruik: precheck.sh <bestand.swift> [...]"; exit 2; }
FAIL=0
echo "== 1. syntaxis (check_swift)"
out=$("$VENV/bin/python" "$HERE/tools/check_swift.py" "$@"); echo "$out" | grep -v "^ok " ; echo "$out" | grep -q "TOTAL ERROR NODES: 0" || FAIL=1
echo "== 2. ViewBuilder-limiet (count_children)"
cc=$("$VENV/bin/python" "$HERE/tools/count_children.py" "$@"); [ -z "$cc" ] && echo "geen closure met meer dan 9 statements" || { echo "$cc"; FAIL=1; }
echo "== 3. ontwerpcontrole"
"$HERE/design-checks.sh" "$@" | grep -E "FAIL|ALLES PASS|ER ZIJN FAILS" || true
"$HERE/design-checks.sh" "$@" >/dev/null || FAIL=1
[ "$FAIL" = 0 ] && echo "PRECHECK OK" || { echo "PRECHECK: ER IS IETS MIS"; exit 1; }
