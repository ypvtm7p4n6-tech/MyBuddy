#!/usr/bin/env bash
# Poort voor de startdatum (docs/work/plan.md, par. 2.2): niemand loopt zomaar over de ruwe lijsten met boekingen.
#
# Met een startdatum tellen boekingen en ingevulde saldi van vóór die dag niet mee, ook al blijven ze bewaard. Daarom lopen alle
# lezers via `countedBankEntries`, `countedPotEntries` en `countedBankSnapshots` (App/Core/StartDate.swift). Deze controle zoekt in
# App/ naar een LUS of bewerking over de ruwe lijsten `bankEntries`, `bankSnapshots` en `potEntries` en eist daar het commentaar
# `// raw: <reden>` op dezelfde regel (of, bij een keten die over meer regels loopt, op de regel met de lijst of met de bewerking).
# Toegestaan met een reden: een boeking verwijderen (met de andere helft van een overboeking), zoeken op id, export, back-up.
#
# Gebruik: docs/work/start-check.sh            controle (exit 1 bij een treffer zonder `// raw:`)
#          docs/work/start-check.sh --list     toon ook alle plekken die WEL een reden hebben
#
# Wat telt als lus of bewerking (direct na de lijst, ook op de volgende regel van een keten):
#   map filter sorted sort min max reduce enumerated last first contains compactMap flatMap forEach allSatisfy firstIndex
#   lastIndex prefix suffix dropFirst dropLast reversed removeAll count isEmpty indices, een lus `for ... in ...<lijst>`, een
#   sluiting `{ x in ...<lijst> }` en `ForEach(...<lijst>)`. Aan de lijst toevoegen (`append`, `insert`, `+=`) of haar vervangen
#   (`= ...`) is geen lus en hoeft geen reden.
# Uitgezonderd (zij zijn de bron zelf, of lezen bewust alles): Models.swift, StartDate.swift, Accelerators.swift, Export.swift,
#   CloudSync.swift, Overview.swift en HomePreviews.swift.
# Een lijn die alleen commentaar of tekst bevat telt niet: tekst tussen aanhalingstekens en alles na `//` wordt genegeerd.
exec python3 - "$@" <<'PY'
import os, re, subprocess, sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "/home/user/MyBuddy"
os.chdir(ROOT)

EXEMPT = {"Models.swift", "StartDate.swift", "Accelerators.swift", "Export.swift", "CloudSync.swift", "Overview.swift", "HomePreviews.swift"}
LISTS = r"(?:bankEntries|bankSnapshots|potEntries)"
OPS = ("map|filter|sorted|sort|min|max|reduce|enumerated|last|first|contains|compactMap|flatMap|forEach|allSatisfy|firstIndex|"
       "lastIndex|prefix|suffix|dropFirst|dropLast|reversed|removeAll|count|isEmpty|indices")

LIST_RE = re.compile(r"\b" + LISTS + r"\b")
# De bewerking staat direct achter de lijst: `lijst.filter`, `lijst?.first`, of op het begin van de volgende regel van een keten.
OP_AFTER = re.compile(r"\b" + LISTS + r"\b\s*[?!]?\s*\.\s*(?:" + OPS + r")\b")
OP_START = re.compile(r"^\s*[?!]?\.\s*(?:" + OPS + r")\b")
LOOP_RE = re.compile(r"\bin\b[^{};]*\b" + LISTS + r"\b")
FOREACH_RE = re.compile(r"\bForEach\s*\([^)]*\b" + LISTS + r"\b")
STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"')

def code_of(line):
    """De regel zonder tekst tussen aanhalingstekens en zonder commentaar."""
    stripped = STRING_RE.sub('""', line)
    cut = stripped.find("//")
    return stripped if cut < 0 else stripped[:cut]

def has_reason(line):
    return re.search(r"//\s*raw:\s*\S", line) is not None

list_mode = "--list" in sys.argv[1:]
files = subprocess.run(["git", "ls-files", "App"], capture_output=True, text=True).stdout.split("\n")
files += subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "App"], capture_output=True, text=True).stdout.split("\n")
files = sorted({f for f in files if f.endswith(".swift") and os.path.basename(f) not in EXEMPT and os.path.exists(f)})

failures, allowed, scanned = [], [], 0
for path in files:
    lines = open(path, encoding="utf8").read().split("\n")
    scanned += 1
    for i, raw in enumerate(lines):
        code = code_of(raw)
        if not LIST_RE.search(code):
            continue
        # Het venster: deze regel en de regels erna zolang ze de keten voortzetten (beginnen met een punt).
        window = [i]
        j = i + 1
        while j < len(lines) and re.match(r"^\s*[?!]?\.", code_of(lines[j])):
            window.append(j)
            j += 1
        hit = bool(OP_AFTER.search(code) or LOOP_RE.search(code) or FOREACH_RE.search(code))
        if not hit and len(window) > 1 and OP_START.search(code_of(lines[window[1]])) and re.search(r"\b" + LISTS + r"\s*[?!]?\s*$", code):
            hit = True
        if not hit:
            continue
        # De keten kan op een volgende regel doorlopen: ook die bewerkingen zijn van de lijst.
        reason = any(has_reason(lines[k]) for k in window)
        entry = f"{path}:{i + 1}: {raw.strip()}"
        (allowed if reason else failures).append(entry)

print(f"Startdatum-poort: {scanned} bestanden onder App/ gecontroleerd ({len(EXEMPT)} namen uitgezonderd).")
if list_mode:
    for e in allowed:
        print("  met reden:", e)
print(f"  {len(allowed)} plekken met `// raw:`")
for e in failures:
    print("FOUT: lus of bewerking over een ruwe lijst zonder `// raw: <reden>`:", e)
if failures:
    print(f"START-CHECK: {len(failures)} FOUT(EN). Gebruik countedBankEntries / countedPotEntries / countedBankSnapshots, of leg met `// raw: <reden>` uit waarom alles moet tellen.")
    sys.exit(1)
print("START-CHECK PASS")
PY
