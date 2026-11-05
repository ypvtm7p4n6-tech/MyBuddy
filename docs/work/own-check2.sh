#!/usr/bin/env bash
# Eigendomscontrole voor verdelen, doelen met meer potten, opnemen met bestemming en loon per maand (docs/work/plan2.md, par. 5
# "Eigendom per fase"). Kopie van docs/work/own-check.sh met het blok van plan2.md en de fasen 1, 2 en 3.
# Gebruik: docs/work/own-check2.sh <fase 1|2|3> [--base <commit>] [--only <eigenaar>]
#            Loopt over de bestanden die veranderd zijn sinds <commit> (standaard HEAD: de werkboom) en over ongevolgde bestanden.
#            Meldt per eigenaar het aantal bestanden en elk bestand waarvan de eigenaar in die golf "-" is (of dat in die golf
#            van een ander pakket is dan de eigenaren die je met --only noemt). Exit 1 bij een bestand zonder eigenaar.
#          docs/work/own-check2.sh --owner <pad> <fase>
#            Wie is eigenaar van dit bestand in die golf? (voor het doorsturen van een CI-fout)
# Het blok staat tussen <!-- EIGENDOM-BEGIN --> en <!-- EIGENDOM-EINDE --> in docs/work/plan2.md. Regel: "pad fase1 fase2 fase3",
# "-" = niemand, "C" = de coördinator (het plan zelf). Een pad dat op / eindigt geldt voor alles daaronder; de meest specifieke (langste) regel wint. Een pad zonder regel
# telt in elke fase als "-". Met --only <eigenaar> meldt het script ook elk veranderd bestand dat van een ANDERE eigenaar is.
exec python3 - "$@" <<'PY'
import os, re, subprocess, sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "/home/user/MyBuddy"
os.chdir(ROOT)
args = sys.argv[1:]

def usage():
    print("gebruik: own-check2.sh <fase> [--base <commit>] [--only <eigenaar>]  |  own-check2.sh --owner <pad> <fase>")
    sys.exit(2)

text = open("docs/work/plan2.md", encoding="utf8").read()
m = re.search(r"<!-- EIGENDOM-BEGIN -->(.*?)<!-- EIGENDOM-EINDE -->", text, re.S)
if not m:
    print("FOUT: geen EIGENDOM-blok in docs/work/plan2.md"); sys.exit(2)

rules = []
for raw in m.group(1).splitlines():
    line = raw.strip()
    if not line or line.startswith("```") or line.startswith("#"):
        continue
    parts = line.split()
    if len(parts) != 4:
        print("FOUT: onleesbare regel in het eigendomsblok:", line); sys.exit(2)
    rules.append((parts[0], parts[1:]))

def owner_of(path, golf):
    best = None
    for rule_path, owners in rules:
        hit = path.startswith(rule_path) if rule_path.endswith("/") else path == rule_path
        if hit and (best is None or len(rule_path) > len(best[0])):
            best = (rule_path, owners)
    if best is None:
        return "-"
    return best[1][golf - 1]

def parse_golf(value):
    if value not in ("1", "2", "3"):
        usage()
    return int(value)

if args and args[0] == "--owner":
    if len(args) != 3:
        usage()
    golf = parse_golf(args[2])
    print(f"{args[1]}: eigenaar in fase {golf} = {owner_of(args[1], golf)}")
    sys.exit(0)

if not args:
    usage()
golf = parse_golf(args[0])
base = "HEAD"
if "--base" in args:
    base = args[args.index("--base") + 1]
only = args[args.index("--only") + 1] if "--only" in args else None

changed = set(subprocess.run(["git", "diff", "--name-only", base], capture_output=True, text=True).stdout.split("\n"))
changed |= set(subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], capture_output=True, text=True).stdout.split("\n"))
changed.discard("")

per_owner = {}
violations = []
others = []
for f in sorted(changed):
    owner = owner_of(f, golf)
    per_owner.setdefault(owner, []).append(f)
    if owner == "-":
        violations.append(f)
    elif only is not None and owner not in (only, "C"):
        others.append((f, owner))

print(f"Eigendom fase {golf}, veranderd sinds {base}: {len(changed)} bestanden")
for owner in sorted(per_owner):
    label = "niemand (fout)" if owner == "-" else "de coördinator" if owner == "C" else "pakket " + owner
    print(f"  {label}: {len(per_owner[owner])} bestanden")
for f in violations:
    print(f"FOUT: {f} heeft geen eigenaar in fase {golf}")
for f, owner in others:
    print(f"FOUT: {f} is van {owner}, niet van {only}")
if violations or others:
    print("EIGENDOM: ER IS IETS MIS"); sys.exit(1)
print("EIGENDOM OK")
PY
