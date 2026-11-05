#!/usr/bin/env bash
# Contractcontrole (docs/work/plan2.md par. 3 en 5): bestaan de namen van het contract van deze fase in de code?
# Gebruik: docs/work/contract-check2.sh <fase 1|2|3>
# Per regel: een bestand en een reguliere expressie die de declaratie moet vinden (op code, zonder commentaar). Exit 1 bij een ontbrekende naam.
# Fase 1 = de namen van V1 (3.3 tot en met 3.5), fase 2 = ook die van G2V2, fase 3 = ook die van G3BV3C (de pagina's), V3A en V3B (4).
exec python3 - "$@" <<'PY'
import os, re, subprocess, sys
ROOT = os.environ.get("CHECK_ROOT") or subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "/home/user/MyBuddy"
os.chdir(ROOT)
phase = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] in ("1", "2", "3") else 3

V1 = [
 # 3.3: Core/Transfers.swift (D2)
 ("App/Core/Transfers.swift", r"struct TransferPart: Codable, Equatable, Hashable, Identifiable"),
 ("App/Core/Transfers.swift", r"var id: Int \{ day \}"),
 ("App/Core/Transfers.swift", r"init\(day: Int, amount: Double\)"),
 ("App/Core/Transfers.swift", r"struct TransferSlice: Equatable"),
 ("App/Core/Transfers.swift", r"var isStandard: Bool"),
 ("App/Core/Transfers.swift", r"enum TransferMath"),
 ("App/Core/Transfers.swift", r"static let maxParts = 12"),
 ("App/Core/Transfers.swift", r"static func normalized\(_ parts: \[TransferPart\]\) -> \[TransferPart\]"),
 ("App/Core/Transfers.swift", r"static func slices\(totalCents: Int, parts: \[TransferPart\], standardDay: Int, month: YearMonth\) -> \[TransferSlice\]"),
 ("App/Core/Transfers.swift", r"static func overflowCents\(totalCents: Int, parts: \[TransferPart\]\) -> Int"),
 ("App/Core/Transfers.swift", r"func standardTransferParts\(of id: UUID\) -> \[TransferPart\]"),
 ("App/Core/Transfers.swift", r"func transferParts\(for id: UUID, in month: YearMonth\) -> \[TransferPart\]"),
 ("App/Core/Transfers.swift", r"func hasTransferPartsOverride\(_ id: UUID, in month: YearMonth\) -> Bool"),
 ("App/Core/Transfers.swift", r"func transferSlices\(for id: UUID, in month: YearMonth, totalCents: Int\) -> \[TransferSlice\]"),
 ("App/Core/Transfers.swift", r"func transferSlices\(for id: UUID, in month: YearMonth\) -> \[TransferSlice\]"),
 ("App/Core/Transfers.swift", r"func uncountedTransferSlices\(for id: UUID, in month: YearMonth\) -> \[TransferSlice\]"),
 ("App/Core/Transfers.swift", r"func countedTransferCents\(_ totalCents: Int, id: UUID, in month: YearMonth, parts: \[TransferPart\]\) -> Int"),
 ("App/Core/Transfers.swift", r"static func transferEventID\(prefix: String, id: UUID, month: YearMonth, slice: TransferSlice\) -> String"),
 ("App/Core/Transfers.swift", r"mutating func setTransferParts\(_ id: UUID, in month: YearMonth, parts: \[TransferPart\]\)"),
 ("App/Core/Transfers.swift", r"mutating func clearTransferParts\(_ id: UUID, in month: YearMonth\)"),
 ("App/Core/Transfers.swift", r"mutating func setStandardTransferParts\(_ id: UUID, parts: \[TransferPart\], current: YearMonth\)"),
 ("App/Core/Transfers.swift", r"mutating func freezePastTransferParts\(_ id: UUID, parts: \[TransferPart\], start: YearMonth, before current: YearMonth\)"),
 # 3.3: Core/BankShare.swift (D3)
 ("App/Core/BankShare.swift", r"struct BankShare: Codable, Equatable, ContributionSource"),
 ("App/Core/BankShare.swift", r"static let id = UUID\(uuidString: \"00000000-0000-4000-8000-00000000BA4C\"\)!"),
 ("App/Core/BankShare.swift", r"static let key = id\.uuidString"),
 ("App/Core/BankShare.swift", r"var startMonth: YearMonth \{ YearMonth\(year: 1, month: 1\) \}"),
 ("App/Core/BankShare.swift", r"var extraTransfers: \[TransferPart\] \{ \[\] \}"),
 ("App/Core/BankShare.swift", r"var contributionExtra: Double"),
 ("App/Core/BankShare.swift", r"init\(\) \{\}"),
 ("App/Core/BankShare.swift", r"var unassigned: Int"),
 ("App/Core/BankShare.swift", r"var hasBankShare: Bool"),
 ("App/Core/BankShare.swift", r"func bankShareAmount\(in month: YearMonth\) -> Double"),
 ("App/Core/BankShare.swift", r"func unassigned\(in month: YearMonth\) -> Double"),
 ("App/Core/BankShare.swift", r"func estimatedUnassigned\(in month: YearMonth\) -> Double"),
 ("App/Core/BankShare.swift", r"mutating func freezePastBankShare\(rule: AllocationRule, before current: YearMonth\)"),
 ("App/Core/BankShare.swift", r"mutating func sendRemainingToBank\(in month: YearMonth\)"),
 # 3.3: Core/PotMoves.swift (D5)
 ("App/Core/PotMoves.swift", r"enum MoneyEnd: Hashable"),
 ("App/Core/PotMoves.swift", r"case outside\b"),
 ("App/Core/PotMoves.swift", r"case bank\b"),
 ("App/Core/PotMoves.swift", r"case pot\(UUID\)"),
 ("App/Core/PotMoves.swift", r"mutating func withdraw\(fromPot id: UUID, amount: Double, to destination: MoneyEnd, note: String = \"\", date: Date = Date\(\)\) -> Bool"),
 ("App/Core/PotMoves.swift", r"mutating func deposit\(toPot id: UUID, amount: Double, from source: MoneyEnd, note: String = \"\", date: Date = Date\(\)\) -> Bool"),
 # 3.3 (laatste alinea): opslag in de modellen
 ("App/Core/Models.swift", r"var bankShare = BankShare\(\)"),
 ("App/Core/Models.swift", r"var transferParts: \[String: \[TransferPart\]\]"),
 ("App/Core/Models.swift", r"var contributionExtra: Double"),
 ("App/Core/Models.swift", r"var extraTransfers: \[TransferPart\]"),
 ("App/Core/Models.swift", r"var morePotIDs: \[UUID\]\?"),
 ("App/Core/Goals.swift", r"var fundingPotIDs: \[UUID\]"),
 ("App/Core/Goals.swift", r"func isFunded\(by potID: UUID\) -> Bool"),
 ("App/Core/Goals.swift", r"mutating func setFundingPots\(_ ids: \[UUID\]\)"),
 ("App/Core/Goals.swift", r"func goals\(usingPot potID: UUID\) -> \[LifeGoal\]"),
 # 3.4: gewijzigde handtekeningen
 ("App/Core/Allocation.swift", r"var extra: Double = 0"),
 ("App/Core/Allocation.swift", r"init\(percent: Double, basis: IncomeBasis = \.salary, extra: Double = 0\)"),
 ("App/Core/Allocation.swift", r"var contributionExtra: Double \{ get \}"),
 ("App/Core/Allocation.swift", r"var extraTransfers: \[TransferPart\] \{ get \}"),
 ("App/Core/Allocation.swift", r"static func extraCents\(_ extra: Double\) -> Int"),
 ("App/Core/Allocation.swift", r"static func cleanExtra\(_ extra: Double\) -> Double"),
 ("App/Core/Allocation.swift", r"static func cents\(of rule: PercentRule, bases: IncomeBases\) -> Int"),
 ("App/Core/Allocation.swift", r"func rawCents\(of rule: AllocationRule, in month: YearMonth\) -> Int"),
 ("App/Core/Allocation.swift", r"func allocationTotalCents<E: ContributionSource>"),
 ("App/Core/Allocation.swift", r"mutating func setAllocationPercent\(_ id: UUID, in month: YearMonth, percent: Double, basis: IncomeBasis\? = nil,"),
 ("App/Core/Allocation.swift", r"mutating func setContributionPercent\(_ id: UUID, percent: Double, basis: IncomeBasis, extra: Double\? = nil,"),
 ("App/Core/Allocation.swift", r"func percentAmount\(_ percent: Double, of basis: IncomeBasis = \.salary, extra: Double = 0, in month: YearMonth\)"),
 ("App/Core/Plan.swift", r"var toBank = 0"),
 ("App/Core/Plan.swift", r"var toBank: Double = 0"),
 ("App/Core/Plan.swift", r"var toBank: Double \{ sum \{ \$0\.toBank \} \}"),
 ("App/Core/Ledger.swift", r"var toBank: Double = 0"),
 ("App/Core/Ledger.swift", r"var unassigned: Double"),
 ("App/UI/MoneyFigures.swift", r"static func left\(_ figures: MonthFigures, of month: YearMonth, current: YearMonth, isPeriod: Bool = false\) -> Int"),
 ("App/UI/MoneyFigures.swift", r"var toBank: Double \{ CentsMath\.value\(figures\.toBank\) \}"),
 ("App/UI/MoneyFigures.swift", r"var unassigned: Double \{ CentsMath\.value\(figures\.unassigned\) \}"),
 ("App/UI/MoneyFigures.swift", r"var distributed: Double"),
 ("App/UI/MoneyFigures.swift", r"func left\(current: YearMonth, isPeriod: Bool = false\) -> Double"),
 ("App/UI/MoneyFigures.swift", r"func leftIsNegative\(current: YearMonth, isPeriod: Bool = false\) -> Bool"),
 ("App/UI/MoneyFigures.swift", r"func distributedShown\(current: YearMonth, isPeriod: Bool = false\) -> Double"),
 ("App/UI/MoneyFigures.swift", r"func roundingHidesLeftSum\(current: YearMonth, isPeriod: Bool = false\) -> Bool"),
 ("App/UI/MoneyFigures.swift", r"func left\(current: YearMonth\) -> Double"),
 ("App/UI/MoneyFigures.swift", r"var slices: \[TransferSlice\]"),
 ("App/UI/MoneyFigures.swift", r"var hasParts: Bool"),
 ("App/UI/MoneyFigures.swift", r"static func resolve\(_ data: FinanceData, percent: Double, basis: IncomeBasis, extra: Double = 0, month: YearMonth\)"),
 ("App/UI/SavingsDisplay.swift", r"static func setExtra\(_ data: inout FinanceData, id: UUID, month: YearMonth, extra: Double\)"),
 ("App/UI/SavingsDisplay.swift", r"static func differsFromStandard\(_ data: FinanceData, id: UUID, month: YearMonth\) -> Bool"),
 ("App/UI/SavingsDisplay.swift", r"static func transferCaption\(_ data: FinanceData, id: UUID, month: YearMonth, today: Date\) -> String"),
 ("App/UI/Fields.swift", r"var extra: Binding<Double>\? = nil"),
 ("App/UI/Fields.swift", r"var extraTitle = ExtraAmountText\.title"),
 # 3.5: Foundation-only hulpen
 ("App/UI/DistributionText.swift", r"enum ExtraAmountText"),
 ("App/UI/DistributionText.swift", r"static let title = \"Extra bedrag erbij\""),
 ("App/UI/DistributionText.swift", r"static let footer"),
 ("App/UI/DistributionText.swift", r"static func breakdown\(percentAmount: Double, extra: Double\) -> String\?"),
 ("App/UI/DistributionText.swift", r"enum TransferPartsText"),
 ("App/UI/DistributionText.swift", r"static let title = \"Extra overschrijfdagen\""),
 ("App/UI/DistributionText.swift", r"addTitle = \"Dag toevoegen\""),
 ("App/UI/DistributionText.swift", r"resetTitle = \"Terug naar standaard\""),
 ("App/UI/DistributionText.swift", r"makeStandardTitle = \"Maak dit je standaard\""),
 ("App/UI/DistributionText.swift", r"static func partTitle\(_ part: TransferPart\) -> String"),
 ("App/UI/DistributionText.swift", r"static func summary\(slices: \[TransferSlice\], standardDay: Int\) -> String"),
 ("App/UI/DistributionText.swift", r"static func explanation\(standardDay: Int\) -> String"),
 ("App/UI/DistributionText.swift", r"static func overflowWarning\(overflowCents: Int\) -> String\?"),
 ("App/UI/DistributionText.swift", r"static func shortMonthNote\(parts: \[TransferPart\]\) -> String\?"),
 ("App/UI/DistributionText.swift", r"static func accessibilityLabel\(_ part: TransferPart\) -> String"),
 ("App/UI/DistributionText.swift", r"static func beforeStartNote\(_ slices: \[TransferSlice\]\) -> String\?"),
 ("App/UI/DistributionText.swift", r"static func standardParts\(_ parts: \[TransferPart\]\) -> String\?"),
 ("App/UI/DistributionText.swift", r"enum TransferPartsDraft"),
 ("App/UI/DistributionText.swift", r"static func displayed\(draft: \[TransferPart\], stored: \[TransferPart\]\) -> \[TransferPart\]"),
 ("App/UI/DistributionText.swift", r"enum BankShareText"),
 ("App/UI/DistributionText.swift", r"static let title = \"Bankrekening\""),
 ("App/UI/DistributionText.swift", r"subtitle = \"Blijft op je rekening\""),
 ("App/UI/DistributionText.swift", r"symbol = \"building\.columns\""),
 ("App/UI/DistributionText.swift", r"restTitle = \"Rest naar bankrekening\""),
 ("App/UI/DistributionText.swift", r"static let explanation"),
 ("App/UI/DistributionText.swift", r"static func caption\(toBankCents: Int\) -> String"),
 ("App/UI/DistributionText.swift", r"static func summaryNote\(toBankCents: Int\) -> String\?"),
 ("App/UI/PotMoveText.swift", r"enum PotMoveDirection"),
 ("App/UI/PotMoveText.swift", r"case withdraw, deposit"),
 ("App/UI/PotMoveText.swift", r"enum PotMoveText"),
 ("App/UI/PotMoveText.swift", r"outsideTitle = \"Nergens \(uit je overzicht\)\""),
 ("App/UI/PotMoveText.swift", r"bankTitle = \"Bankrekening\""),
 ("App/UI/PotMoveText.swift", r"static func question\(_ direction: PotMoveDirection\) -> String"),
 ("App/UI/PotMoveText.swift", r"\"Waar gaat het naartoe\?\""),
 ("App/UI/PotMoveText.swift", r"\"Waar komt het vandaan\?\""),
 ("App/UI/PotMoveText.swift", r"static func title\(_ end: MoneyEnd, in data: FinanceData\) -> String"),
 ("App/UI/PotMoveText.swift", r"static func choices\(excluding potID: UUID, in data: FinanceData\) -> \[MoneyEnd\]"),
 ("App/UI/PotMoveText.swift", r"static func footer\(_ direction: PotMoveDirection, end: MoneyEnd, amount: Double, in data: FinanceData\) -> String"),
 ("App/UI/PotMoveText.swift", r"static func bankUnknownNote\(amount: Double\) -> String"),
 ("App/UI/GoalPotsText.swift", r"enum GoalPotsText"),
 ("App/UI/GoalPotsText.swift", r"pickerTitle = \"Spaarpotten\""),
 ("App/UI/GoalPotsText.swift", r"static let pickerFooter"),
 ("App/UI/GoalPotsText.swift", r"needsOnePot = \"Kies minstens één spaarpot\.\""),
 ("App/UI/GoalPotsText.swift", r"static let acceleratorNote"),
 ("App/UI/GoalPotsText.swift", r"static func potNames\(_ names: \[String\]\) -> String"),
 ("App/UI/GoalPotsText.swift", r"static func sharedWarning\(otherGoalNames: \[String\]\) -> String\?"),
 ("App/UI/GoalPotsText.swift", r"static func potLine\(goalNames: \[String\]\) -> String\?"),
 ("App/UI/GoalPotsText.swift", r"static func sourceLine\(potNames names: \[String\]\) -> String"),
 # 4.1 en 4.7 (voor zover van V1): de editor, de voorbeelddata en de zoektermen
 ("App/UI/TransferPartsEditor.swift", r"struct TransferPartsEditor: View"),
 ("App/UI/TransferPartsEditor.swift", r"@Binding var parts: \[TransferPart\]"),
 ("App/UI/TransferPartsEditor.swift", r"let standardDay: Int"),
 ("App/UI/TransferPartsEditor.swift", r"var totalCents: Int\? = nil"),
 ("App/UI/TransferPartsEditor.swift", r"var emptyHint"),
 ("App/Core/SampleData.swift", r"static func sampleWithDistribution\(now: Date = Date\(\)\) -> FinanceData"),
 ("App/Navigation/PageCatalog.swift", r"\"extra overschrijfdagen\""),
 ("App/Navigation/PageCatalog.swift", r"\"rest naar bankrekening\""),
 ("App/Navigation/PageCatalog.swift", r"\"loon per maand\""),
 ("App/Navigation/PageCatalog.swift", r"\"opnemen naar\""),
 ("App/Navigation/PageCatalog.swift", r"\"meer spaarpotten\""),
 # de symlinks van de Foundation-only hulpen in het testpakket
 ("CoreTests/Tests/MyBuddyCoreTests/DistributionText.swift", r"enum TransferPartsText"),
 ("CoreTests/Tests/MyBuddyCoreTests/PotMoveText.swift", r"enum PotMoveText"),
 ("CoreTests/Tests/MyBuddyCoreTests/GoalPotsText.swift", r"enum GoalPotsText"),
]
V2 = [
 ("App/Core/WageHistory.swift", r"struct SalaryChange: Codable, Equatable, Identifiable"),
 ("App/Core/WageHistory.swift", r"func salarySettings\(in month: YearMonth\) -> SalarySettings"),
 ("App/Core/WageHistory.swift", r"func salarySettings\(forPayoutOn day: CalendarDay\) -> SalarySettings"),
 ("App/Core/WageHistory.swift", r"var latestSalarySettings: SalarySettings"),
 ("App/Core/WageHistory.swift", r"func salaryChange\(effectiveIn month: YearMonth\) -> SalaryChange\?"),
 ("App/Core/WageHistory.swift", r"func salaryChange\(startingIn month: YearMonth\) -> SalaryChange\?"),
 ("App/Core/WageHistory.swift", r"mutating func setSalaryChange\(_ change: SalaryChange\)"),
 ("App/Core/WageHistory.swift", r"mutating func removeSalaryChange\(from month: YearMonth\)"),
 ("App/Core/WageHistory.swift", r"func hasSalary\(before current: YearMonth\) -> Bool"),
 ("App/Core/WageHistory.swift", r"mutating func setWage\(current: YearMonth, hourlyRate: Double\? = nil, fixedMonthly: Double\? = nil, hoursPerWeek: Double\? = nil\)"),
 ("App/Core/WageHistory.swift", r"struct LossyBox<T: Decodable>: Decodable"),
 ("App/Core/Models.swift", r"var salaryChanges: \[SalaryChange\] = \[\]"),
 ("App/Core/Purchase.swift", r"func effectiveHourlyWage\(in month: YearMonth\? = nil\) -> Double\?"),
 ("App/Core/Purchase.swift", r"static func resolvedWage\(manual: Double, data: FinanceData, in month: YearMonth\? = nil\) -> Double\?"),
 ("App/Core/Goals.swift", r"func monthlyIncomeGap\(for goal: LifeGoal, in month: YearMonth\? = nil\) -> Double"),
 ("App/Core/Goals.swift", r"func neededCapital\(for goal: LifeGoal, drawdownReturn: Double, in month: YearMonth\? = nil\) -> Double"),
 ("App/UI/WageText.swift", r"enum WageText"),
 ("App/UI/WageText.swift", r"enum WageEdit"),
 ("App/UI/WageText.swift", r"static func change\(_ data: FinanceData, month: YearMonth, hourlyRate: Double, fixedMonthly: Double, hoursPerWeek: Double\) -> SalaryChange"),
 ("App/UI/WageText.swift", r"static func payoutPreview\(_ data: FinanceData, month: YearMonth, change: SalaryChange\) -> \(old: Double, new: Double\)"),
 ("App/Navigation/NavigationModel.swift", r"case wageChange\(YearMonth\)"),
 ("App/Pages/DestinationView.swift", r"case \.wageChange\(let month\): WageChangePage\(month: month\)"),
]
V3 = [
 ("App/Pages/Month/WageChangePage.swift", r"struct WageChangePage: View"),
 ("App/UI/ChartModels.swift", r"var toBank: Double = 0"),
 ("App/UI/CashflowDisplay.swift", r"func left\(current: YearMonth\) -> Double"),
 ("App/Pages/Month/DistributeParts.swift", r"TransferPartsEditor"),
]
STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"')
def code_of(line):
    # voor deze controle blijven aanhalingstekens staan (UUID, titels); alleen commentaar valt weg
    cut = line.find("//")
    return line if cut < 0 else line[:cut]
lists = V1 + (V2 if phase >= 2 else []) + (V3 if phase >= 3 else [])
missing = []
cache = {}
for path, rx in lists:
    if path not in cache:
        cache[path] = "\n".join(code_of(l) for l in open(path, encoding="utf8").read().split("\n")) if os.path.exists(path) else None
    text = cache[path]
    if text is None:
        missing.append(f"{path}: bestand ontbreekt (zoekt {rx})")
    elif not re.search(rx, text):
        missing.append(f"{path}: ontbreekt: {rx}")
print(f"Contractcontrole fase {phase}: {len(lists)} namen")
for m in missing:
    print("FOUT:", m)
if missing:
    print(f"CONTRACT-CHECK: {len(missing)} FOUT(EN). Zie docs/work/plan2.md par. 3.")
    sys.exit(1)
print("CONTRACT-CHECK PASS")
PY
