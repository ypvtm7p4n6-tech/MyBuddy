#!/usr/bin/env bash
# Poort voor Verdelen en het loon per maand (docs/work/plan2.md, par. 6.3): één bron per grootheid.
#
# Gebruik: docs/work/verdelen-check.sh <fase> [onderdeel] [--list]
#   fase 1                    controle C en D (de dagen van een inleg; geen nieuw geval in GoalFunding)
#   fase 2 core               controle B in App/Core (het loon komt uit salarySettings) en C
#   fase 2 maandcijfers       controle A (Nog te verdelen komt uit een functie)
#   fase 3 (of 2 zonder onderdeel is "alles wat in die fase kan kloppen")   alle controles, B ook in App/Pages en App/UI
# Een regel met `// remaining: <reden>` of `// wage: <reden>` hoort bij een bewuste uitzondering. Exit 1 bij een treffer zonder reden.
#
# A  `.remaining` (de eigenschap of functie van MonthFigures, MonthBoard, MonthSummary, PeriodSummary, MonthLedger en FinanceData) staat
#    in App/Pages en App/UI alleen met `// remaining: <reden>`, behalve in MoneyFigures.swift. Een bestand met `MoneyLabels.remaining` of
#    `remainingLabel(` bevat ook `MoneyLabels.left(` of `.left(current:`.
# B  `salary.hourlyRate`, `.fixedMonthly`, `.hoursPerWeek`, `.monthlyAmount(`, `.payoutAmount(`, `.averageMonthly`, `.defaultMonthlyHours`,
#    `.hoursPerCycle` en `.exactHourlyPay` staan niet buiten Models.swift, WageHistory.swift en SampleData.swift, tenzij `// wage: <reden>`.
# C  DayEvents.swift, Pots.swift en Invest.swift bevatten TransferMath.slices( en Transfers.swift bevat countedTransferCents; DayEvents.swift
#    roept allocationCents( niet aan (alleen allocationTotalCents().
# D  `enum GoalFunding` heeft precies de gevallen portfolio, pot en custom.
# (De proefregels van golf 1, `start-check.sh`, blijven apart: draai ook docs/work/start-check.sh.)
exec python3 - "$@" <<'PY'
import os, re, subprocess, sys

ROOT = os.environ.get("CHECK_ROOT") or subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "/home/user/MyBuddy"
os.chdir(ROOT)
args = [a for a in sys.argv[1:] if not a.startswith("--")]
list_mode = "--list" in sys.argv[1:]
phase = int(args[0]) if args and args[0] in ("1", "2", "3") else 3
part = args[1] if len(args) > 1 else "all"

STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"')
INTERP_RE = re.compile(r'\\\((.*?)\)')
def code_of(line):
    # Tekst tussen aanhalingstekens telt niet, maar wat in een \( ... ) staat wel: dat is code.
    stripped = STRING_RE.sub(lambda m: " " + " ".join(INTERP_RE.findall(m.group(0))) + " ", line)
    cut = stripped.find("//")
    return stripped if cut < 0 else stripped[:cut]
def has_reason(line, tag):
    return re.search(r"//\s*" + tag + r":\s*\S", line) is not None

def swift_files(*roots):
    out = []
    for root in roots:
        for dp, _, fn in os.walk(root):
            for f in fn:
                if f.endswith(".swift"):
                    out.append(os.path.join(dp, f))
    return sorted(out)

failures, allowed = [], []

def scan(files, pattern, tag, exempt=()):
    rx = re.compile(pattern)
    for path in files:
        if os.path.basename(path) in exempt:
            continue
        for i, raw in enumerate(open(path, encoding="utf8").read().split("\n")):
            if rx.search(code_of(raw)):
                entry = f"{path}:{i + 1}: {raw.strip()}"
                (allowed if has_reason(raw, tag) else failures).append((tag, entry))

def need(path, needle, why, absent=False):
    if not os.path.exists(path):
        failures.append(("C", f"{path}: bestand ontbreekt ({why})")); return
    text = open(path, encoding="utf8").read()
    present = re.search(needle, "\n".join(code_of(l) for l in text.split("\n"))) is not None
    if present == absent:
        failures.append(("C", f"{path}: {why}"))

run_a = (phase == 3 and part in ("all",)) or (phase == 2 and part in ("maandcijfers",))
run_b_core = (phase == 2 and part == "core") or (phase == 3 and part == "all")
run_b_all = phase == 3 and part == "all"
run_c = True
run_d = True
if phase == 1: run_a = run_b_core = run_b_all = False
if phase == 2 and part == "all": run_a = run_b_core = True

if run_a:
    files = swift_files("App/Pages", "App/UI")
    scan(files, r"(?<!MoneyLabels)\.remaining\b", "remaining", exempt=("MoneyFigures.swift",))
    for path in files:
        if os.path.basename(path) == "MoneyFigures.swift":
            continue
        text = "\n".join(code_of(l) for l in open(path, encoding="utf8").read().split("\n"))
        if re.search(r"MoneyLabels\.remaining\b|\bremainingLabel\(", text) and not re.search(r"MoneyLabels\.left\(|\.left\(current:", text):
            failures.append(("A", f"{path}: toont het label Nog te verdelen/Overgehouden maar leest het getal niet via MoneyLabels.left of left(current:)"))

if run_b_core or run_b_all:
    wage = r"\bsalary\.(hourlyRate|fixedMonthly|hoursPerWeek|monthlyAmount\(|payoutAmount\(|averageMonthly|defaultMonthlyHours|hoursPerCycle|exactHourlyPay)"
    roots = ["App/Core"] if not run_b_all else ["App/Core", "App/Pages", "App/UI"]
    scan(swift_files(*roots), wage, "wage", exempt=("Models.swift", "WageHistory.swift", "SampleData.swift"))

if run_c:
    need("App/Core/DayEvents.swift", r"TransferMath\.slices\(", "geen TransferMath.slices: de dagen van een inleg komen uit een andere plek")
    need("App/Core/DayEvents.swift", r"\ballocationCents\(", "roept allocationCents( aan: gebruik allocationTotalCents( en TransferMath.slices", absent=True)
    need("App/Core/Pots.swift", r"TransferMath\.slices\(", "potLedgers en potTimeline moeten TransferMath.slices gebruiken")
    need("App/Core/Invest.swift", r"TransferMath\.slices\(", "settledAllocation moet TransferMath.slices gebruiken")
    need("App/Core/Transfers.swift", r"\bcountedTransferCents\(", "countedTransferCents ontbreekt: wat vóór de startdag valt telt niet mee")

if run_d:
    text = open("App/Core/Models.swift", encoding="utf8").read()
    m = re.search(r"enum GoalFunding[^{]*\{(.*?)\n\}", text, re.S)
    if m:
        cases = re.findall(r"^\s*case\s+(\w+)", m.group(1), re.M)
        if cases != ["portfolio", "pot", "custom"]:
            failures.append(("D", f"App/Core/Models.swift: GoalFunding heeft de gevallen {cases}; een nieuw geval laat een oudere app het hele bestand weigeren"))
    else:
        failures.append(("D", "App/Core/Models.swift: enum GoalFunding niet gevonden"))

print(f"Verdelen-poort fase {phase} ({part}): {len(allowed)} plekken met een reden")
if list_mode:
    for tag, e in allowed:
        print("  met reden:", e)
for tag, e in failures:
    print(f"FOUT {tag}:", e)
if failures:
    print(f"VERDELEN-CHECK: {len(failures)} FOUT(EN). Zie docs/work/plan2.md par. 6.3.")
    sys.exit(1)
print("VERDELEN-CHECK PASS")
PY
