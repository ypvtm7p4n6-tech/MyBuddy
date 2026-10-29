#!/usr/bin/env bash
# Eigendomscontrole voor startdatum en werkuren (docs/work/plan.md, par. 5 "Eigendom per golf"). Kopie van docs/design2/own-check.sh.
# Gebruik: docs/work/own-check.sh <golf 1|2|3> [--base <commit>]
#            Loopt over de bestanden die veranderd zijn sinds <commit> (standaard HEAD: de werkboom) en over ongevolgde bestanden.
#            Meldt per eigenaar het aantal bestanden en elk bestand waarvan de eigenaar in die golf "-" is (of dat in die golf
#            van een ander pakket is dan de eigenaren die je met --only noemt). Exit 1 bij een bestand zonder eigenaar.
#          docs/work/own-check.sh --owner <pad> <golf>
#            Wie is eigenaar van dit bestand in die golf? (voor het doorsturen van een CI-fout)
# Het blok staat tussen <!-- EIGENDOM-BEGIN --> en <!-- EIGENDOM-EINDE --> in docs/work/plan.md. Regel: "pad golf1 golf2 golf3",
# "-" = niemand, "C" = de coördinator (het plan zelf). Een pad dat op / eindigt geldt voor alles daaronder; de meest specifieke (langste) regel wint. Een pad zonder regel
# telt als "-" in golf 1 en 2 en als 3 in golf 3.
exec python3 - "$@" <<'PY'
import os, re, subprocess, sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "/home/user/MyBuddy"
os.chdir(ROOT)
args = sys.argv[1:]

def usage():
    print("gebruik: own-check.sh <golf> [--base <commit>]  |  own-check.sh --owner <pad> <golf>")
    sys.exit(2)

text = open("docs/work/plan.md", encoding="utf8").read()
m = re.search(r"<!-- EIGENDOM-BEGIN -->(.*?)<!-- EIGENDOM-EINDE -->", text, re.S)
if not m:
    print("FOUT: geen EIGENDOM-blok in docs/work/plan.md"); sys.exit(2)

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
        return "3" if golf == 3 else "-"
    return best[1][golf - 1]

def parse_golf(value):
    if value not in ("1", "2", "3"):
        usage()
    return int(value)

if args and args[0] == "--owner":
    if len(args) != 3:
        usage()
    golf = parse_golf(args[2])
    print(f"{args[1]}: eigenaar in golf {golf} = {owner_of(args[1], golf)}")
    sys.exit(0)

if not args:
    usage()
golf = parse_golf(args[0])
base = "HEAD"
if "--base" in args:
    base = args[args.index("--base") + 1]

changed = set(subprocess.run(["git", "diff", "--name-only", base], capture_output=True, text=True).stdout.split("\n"))
changed |= set(subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], capture_output=True, text=True).stdout.split("\n"))
changed.discard("")

per_owner = {}
violations = []
for f in sorted(changed):
    owner = owner_of(f, golf)
    per_owner.setdefault(owner, []).append(f)
    if owner == "-":
        violations.append(f)

print(f"Eigendom golf {golf}, veranderd sinds {base}: {len(changed)} bestanden")
for owner in sorted(per_owner):
    label = "niemand (fout)" if owner == "-" else "de coördinator" if owner == "C" else "pakket " + owner
    print(f"  {label}: {len(per_owner[owner])} bestanden")
for f in violations:
    print(f"FOUT: {f} heeft geen eigenaar in golf {golf}")
if violations:
    print("EIGENDOM: ER IS IETS MIS"); sys.exit(1)
print("EIGENDOM OK")
PY
