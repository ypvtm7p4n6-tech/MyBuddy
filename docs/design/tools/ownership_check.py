#!/usr/bin/env python3
"""Eigendomscontrole voor docs/design/plan.md (par. 6.7).

Leest het blok tussen <!-- EIGENDOM-BEGIN --> en <!-- EIGENDOM-EINDE --> in plan.md. Elke regel is
    <eigenaar> <pad>            bestaand bestand of bestaande map (map eindigt op /)
    +<eigenaar> <pad>           nieuw bestand of nieuwe map (hoeft nog niet te bestaan)
Een regel met een pad dat op / eindigt geldt voor alles daaronder; de langste (meest specifieke) regel wint.
Controleert:
  1. elk bestaand bestand onder App/, Tests/, CoreTests/, scripts/, .github/, firebase/ en de losse bestanden in de
     hoofdmap en docs/v3-spec.md heeft precies een eigenaar (de meest specifieke regel; twee regels met gelijke
     specificiteit en verschillende eigenaren, of een pad dat dubbel staat, is een fout);
  2. elke regel zonder + wijst naar iets dat bestaat;
  3. geen eigenaar buiten de toegestane lijst.
Gebruik:  ownership_check.py [--owner <pad>] [--summary] [--plan docs/design/plan.md]
"""
import os, re, subprocess, sys

OWNERS = {"0A", "0B", "F", "A", "B1", "B2", "C", "D", "E", "G"}
ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "/home/user/MyBuddy"
os.chdir(ROOT)
plan = "docs/design/plan.md"
args = sys.argv[1:]
if "--plan" in args:
    plan = args[args.index("--plan") + 1]
text = open(plan, encoding="utf8").read()
m = re.search(r"<!-- EIGENDOM-BEGIN -->(.*?)<!-- EIGENDOM-EINDE -->", text, re.S)
if not m:
    print("FOUT: geen EIGENDOM-blok in", plan); sys.exit(2)

entries = []   # (pad, eigenaar, nieuw)
problems = []
for ln, raw in enumerate(m.group(1).splitlines(), 1):
    line = raw.strip()
    if not line or line.startswith("```") or line.startswith("#"):
        continue
    mm = re.match(r"^(\+?)([0-9A-Za-z]+)\s+(\S+)$", line)
    if not mm:
        problems.append(f"onleesbare regel in het blok: {line!r}"); continue
    new, owner, path = mm.groups()
    if owner not in OWNERS:
        problems.append(f"onbekende eigenaar {owner!r} bij {path}")
    entries.append((path, owner, bool(new)))

def universe():
    out = set()
    for top in ["App", "Tests", "CoreTests", "scripts", ".github", "firebase"]:
        for dp, dn, fn in os.walk(top, followlinks=False):
            for d in list(dn):
                p = os.path.join(dp, d)
                if os.path.islink(p):
                    out.add(p)          # symlink naar een map (CoreTests/Sources/MyBuddyCore)
                    dn.remove(d)
                elif d in (".build", "build"):
                    dn.remove(d)
            for f in fn:
                out.add(os.path.join(dp, f))
    for f in ["README.md", "SECURITY.md", "implementation_plan.md", "project.yml", "system_architecture.md", "task.md", "docs/v3-spec.md"]:
        if os.path.exists(f):
            out.add(f)
    return sorted(out)

def matches(entry_path, f):
    if entry_path.endswith("/"):
        return f.startswith(entry_path)
    if entry_path.endswith("*"):
        return f.startswith(entry_path[:-1])
    return f == entry_path

def specificity(entry_path):
    return len(entry_path.rstrip("*"))

# dubbele paden
seen = {}
for path, owner, new in entries:
    if path in seen and seen[path] != owner:
        problems.append(f"pad staat bij twee eigenaren: {path} ({seen[path]} en {owner})")
    elif path in seen:
        problems.append(f"pad staat dubbel in het blok: {path}")
    seen[path] = owner

files = universe()
by_owner = {}
for f in files:
    cands = [(specificity(p), o, p) for p, o, n in entries if matches(p, f)]
    if not cands:
        problems.append(f"GEEN EIGENAAR: {f}"); continue
    best = max(c[0] for c in cands)
    top = {(o, p) for s, o, p in cands if s == best}
    owners = {o for o, p in top}
    if len(owners) > 1 or len(top) > 1:
        problems.append(f"DUBBELE EIGENAAR: {f} -> {sorted(top)}")
        continue
    by_owner.setdefault(next(iter(owners)), []).append(f)

for p, o, new in entries:
    if new:
        continue
    if not any(matches(p, f) for f in files) and not os.path.exists(p):
        problems.append(f"regel zonder bestaand bestand (zet er + voor als het nieuw is): {o} {p}")

if "--owner" in args:
    target = args[args.index("--owner") + 1]
    cands = [(specificity(p), o, p) for p, o, n in entries if matches(p, target)]
    if not cands:
        print("onbekend"); sys.exit(1)
    best = max(c[0] for c in cands)
    print(sorted({o for s, o, p in cands if s == best})[0]); sys.exit(0)

print(f"{len(files)} bestanden onderzocht, {len(entries)} regels in het blok")
for o in sorted(by_owner, key=lambda x: (len(x), x)):
    print(f"  {o:3} {len(by_owner[o]):3} bestanden")
if "--summary" not in args:
    pass
if problems:
    print()
    for p in problems:
        print("PROBLEEM:", p)
    print(f"\n{len(problems)} problemen"); sys.exit(1)
print("EIGENDOM KLOPT: elk bestand heeft precies een eigenaar")
