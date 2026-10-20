#!/usr/bin/env bash
# Eigendomscontrole (docs/design/plan.md par. 6.7): heeft elk bestand precies een eigenaar?
# Gebruik: docs/design/ownership-check.sh                 controleer het hele blok
#          docs/design/ownership-check.sh --owner <pad>   wie is eigenaar van dit bestand? (voor het doorsturen van CI-fouten)
exec python3 "$(dirname "$0")/tools/ownership_check.py" "$@"
