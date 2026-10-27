#!/usr/bin/env bash
# VEROUDERD (ontwerp 1): niet meer draaien. Vervangen door docs/design2/own-check.sh; zie docs/design2/plan.md par. 5.2.
# Eigendomscontrole (docs/design/plan.md par. 6.7): heeft elk bestand precies een eigenaar?
# Gebruik: docs/design/ownership-check.sh                 controleer het hele blok
#          docs/design/ownership-check.sh --owner <pad>   wie is eigenaar van dit bestand? (voor het doorsturen van CI-fouten)
exec python3 "$(dirname "$0")/tools/ownership_check.py" "$@"
