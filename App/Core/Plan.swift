import Foundation

// MARK: - Rekenen in hele centen

/// Bedragen worden bij het optellen eerst naar hele centen (Int) omgezet. Zo blijven er geen
/// zwevendekommaresten hangen (0,03 waar 0 hoort) en komen alle overzichten op hetzelfde uit.
enum CentsMath {
    /// Grootste bedrag (in centen) waarmee de rekenmotor rekent: 90 biljoen euro. Alles daarboven wordt begrensd,
    /// zodat een tikfout in een invulveld nooit tot een crash leidt.
    static let limit = 9_000_000_000_000_000

    static func int(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let scaled = (value * 100).rounded()
        if scaled > Double(limit) { return limit }
        if scaled < -Double(limit) { return -limit }
        return Int(scaled)
    }

    static func value(_ cents: Int) -> Double {
        Double(cents) / 100
    }

    /// Telt twee bedragen in centen op en begrenst het resultaat op ±`limit`. Een gewone `+` zou bij absurd
    /// grote bedragen (honderden maanden aan sommen) de app laten crashen.
    static func add(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        if overflow { return a > 0 ? limit : -limit }
        return min(max(sum, -limit), limit)
    }

    /// Som van bedragen in centen, begrensd zoals `add`.
    static func sum<S: Sequence>(_ values: S) -> Int where S.Element == Int {
        var total = 0
        for value in values { total = add(total, value) }
        return total
    }
}

/// Samenvatting van één maand.
struct MonthSummary: Identifiable, Equatable {
    var month: YearMonth
    var income: Double
    /// Totaal van alle uitgaven, ook het deel dat uit spaarpotten komt.
    var expenses: Double
    /// Het deel van de uitgaven dat uit spaarpotten betaald wordt (kost dit maandbudget niets).
    var fromPots: Double = 0
    var saved: Double      // verdeeld over spaarpotten
    var invested: Double   // verdeeld over beleggingen
    var isProjected: Bool  // ligt na de huidige maand

    var id: String { month.key }
    /// Wat er nog te verdelen is (kan negatief zijn: je hebt meer verdeeld dan je hebt).
    /// Dezelfde formule als `FinanceData.remaining(in:)`: inkomen − uitgaven van de bank − verdeeld − belegd.
    var remaining: Double {
        let bankExpenses = CentsMath.int(expenses) - CentsMath.int(fromPots)
        return CentsMath.value(CentsMath.int(income) - bankExpenses - CentsMath.int(saved) - CentsMath.int(invested))
    }

    /// Hoeveel er meer wordt verdeeld dan er te verdelen is (0 als het past). Zie `MonthFigures.overAllocated`.
    var overAllocated: Double {
        CentsMath.value(MonthFigures(income: CentsMath.int(income), expenses: CentsMath.int(expenses),
                                     fromPots: CentsMath.int(fromPots), saved: CentsMath.int(saved),
                                     invested: CentsMath.int(invested)).overAllocated)
    }
}

struct PeriodSummary: Equatable {
    var months: [MonthSummary]

    private func sum(_ value: (MonthSummary) -> Double) -> Double {
        CentsMath.value(CentsMath.sum(months.map { CentsMath.int(value($0)) }))
    }

    var income: Double { sum { $0.income } }
    var expenses: Double { sum { $0.expenses } }
    var fromPots: Double { sum { $0.fromPots } }
    var saved: Double { sum { $0.saved } }
    var invested: Double { sum { $0.invested } }
    /// Dezelfde formule als bij één maand, over de hele periode.
    var remaining: Double {
        let bankExpenses = CentsMath.int(expenses) - CentsMath.int(fromPots)
        return CentsMath.value(CentsMath.int(income) - bankExpenses - CentsMath.int(saved) - CentsMath.int(invested))
    }
    var count: Int { months.count }
    var hasProjected: Bool { months.contains { $0.isProjected } }
    var isFullyProjected: Bool { !months.isEmpty && months.allSatisfy { $0.isProjected } }
    func average(_ value: Double) -> Double { count == 0 ? 0 : (value / Double(count)).cents }
}

/// De cijfers van een maand in hele centen. Eén bron voor alle overzichten.
struct MonthFigures: Equatable {
    var income = 0
    var expenses = 0
    var fromPots = 0
    var saved = 0
    var invested = 0

    /// inkomen − uitgaven van de bank − verdeeld over potten − belegd.
    var remaining: Int { income - (expenses - fromPots) - saved - invested }

    /// Wat er te verdelen is voordat er iets is verdeeld: inkomen − uitgaven van de bank (kan negatief zijn).
    var available: Int { income - (expenses - fromPots) }

    /// Hoeveel er meer wordt verdeeld (potten en beleggingen) dan er te verdelen is. 0 als het past of als er niets
    /// wordt verdeeld. Voor de waarschuwing bij een verdeling die groter is dan het inkomen.
    var overAllocated: Int {
        let allocated = saved + invested
        guard allocated > 0 else { return 0 }
        return max(0, allocated - max(0, available))
    }
}

/// Rekent de cijfers van veel maanden achter elkaar uit, zonder voor elke maand een plan met nieuwe regel-id's op te
/// bouwen. Geeft dezelfde cijfers als `FinanceData.monthFigures(_:)`: de regels van een maand komen uit dezelfde plek
/// (de opgeslagen regels plus de terugkerende reeksen, zie `SeriesIndex.completed`), de verdeling uit het opgeslagen
/// plan of de standaardinleg.
final class MonthFiguresBuilder {
    private let data: FinanceData
    private let potKeys: [String]
    private let holdingKeys: [String]
    private let stored: StoredPlans

    fileprivate init(_ data: FinanceData) {
        self.data = data
        self.potKeys = data.pots.map { $0.id.uuidString }
        self.holdingKeys = data.holdings.map { $0.id.uuidString }
        self.stored = data.storedPlans
    }

    func figures(_ month: YearMonth) -> MonthFigures {
        guard month >= data.startMonth else { return MonthFigures() }
        let storedPlan = stored.plan(at: month)
        // De id's van aangevulde regels doen voor de bedragen niet ter zake: ze worden niet afgeleid.
        let plan = data.completedPlan(storedPlan ?? MonthPlan(), in: month, using: stored, deriveIDs: false)
        return data.monthFigures(of: plan, in: month, storedPlan: storedPlan, potKeys: potKeys, holdingKeys: holdingKeys)
    }
}

/// Een deel van een uitgave dat uit één spaarpot komt, in hele centen.
struct PotPayment: Equatable {
    var shareID: UUID
    var potID: UUID
    var cents: Int
}

/// Hoe een uitgave verdeeld wordt over spaarpotten en bankrekening.
struct ExpenseSplit: Equatable {
    var totalCents: Int
    var pots: [PotPayment]

    var potsCents: Int { CentsMath.sum(pots.map { $0.cents }) }
    /// Wat van de bankrekening gaat.
    var bankCents: Int { totalCents - potsCents }
}

extension FinanceData {
    // MARK: Maandplannen

    /// Standaardverdeling van een maand uit de instellingen van potten en beleggingen: het vaste bedrag, of bij een
    /// percentage het bedrag dat daar in die maand uit volgt.
    func defaultAllocation(_ id: UUID, in month: YearMonth) -> Double {
        guard let rule = defaultAllocationRule(id, in: month) else { return 0 }
        return amount(of: rule, in: month)
    }

    /// Plan afgeleid uit standaarden (voor maanden die nog niet zijn vastgelegd): de standaardverdeling en de
    /// terugkerende reeksen die in die maand lopen (zie `RecurringSeries.swift`), zonder rekening te houden met wat er
    /// in het opgeslagen plan van die maand staat.
    /// `transferDay` blijft nil: de overschrijfdag volgt dan de pot, belegging of salarisdag.
    func synthesizedPlan(for month: YearMonth) -> MonthPlan {
        synthesizedPlan(for: month, using: storedPlans)
    }

    /// Zoals `synthesizedPlan(for:)`, met vooraf bepaalde opgeslagen plannen en reeksen (sneller in lussen).
    func synthesizedPlan(for month: YearMonth, using stored: StoredPlans) -> MonthPlan {
        var plan = MonthPlan()
        for pot in pots where month >= pot.startMonth { putDefault(pot, in: month, into: &plan) }
        for h in holdings where month >= h.startMonth { putDefault(h, in: month, into: &plan) }
        return completedPlan(plan, in: month, using: stored)
    }

    /// Het plan van een maand: het opgeslagen plan, aangevuld met de terugkerende regels die in die maand lopen maar niet
    /// zijn opgeslagen (een maand die vastgelegd is vóór de regel werd toegevoegd, krijgt hem dus ook), of een afgeleid
    /// plan als de maand niet is opgeslagen. Eén bron van waarheid voor "welke regels heeft maand X".
    func plan(for month: YearMonth) -> MonthPlan {
        plan(for: month, using: storedPlans)
    }

    /// Zoals `plan(for:)`, met vooraf bepaalde opgeslagen plannen en reeksen (sneller in lussen).
    func plan(for month: YearMonth, using stored: StoredPlans) -> MonthPlan {
        guard let base = stored.plan(at: month) else { return synthesizedPlan(for: month, using: stored) }
        return completedPlan(base, in: month, using: stored)
    }

    /// Past een maandplan aan en slaat het op.
    ///
    /// Het plan waarmee `body` werkt is het plan zoals de maand het heeft (`plan(for:)`). Daarna: een nieuwe terugkerende
    /// regel krijgt een reeks, en een regel van een reeks die `body` weghaalt wordt voor deze maand overgeslagen (zodat hij
    /// er niet ongemerkt terugkomt). Bepaalde de weggehaalde regel wat de volgende maanden zijn, dan houden die maanden
    /// hem (zie `carryBaseline`). Stoppen vanaf een maand en alleen-deze-maand-bewerken staan in
    /// `removeLine(id:kind:in:scope:)` en `updateLine(_:kind:in:scope:)`.
    mutating func editPlan(_ month: YearMonth, _ body: (inout MonthPlan) -> Void) {
        let stored = storedPlans
        let before = plan(for: month, using: stored)
        var p = before
        body(&p)
        let dropped = FinanceData.droppedSeriesLines(before: before, after: p)
        FinanceData.settleSeries(in: &p, before: before)
        months[month.key] = p
        for item in dropped {
            carryBaseline(of: item.line, income: item.income, from: month, using: stored)
        }
    }

    /// Legt alle maanden t/m `current` vast, zodat latere wijzigingen van standaarden het verleden niet veranderen.
    /// Schrijft ook de reeks-id's van oude data weg (`migrateRecurringSeries`).
    mutating func materialize(upTo current: YearMonth) {
        migrateRecurringSeries()
        // Voor de reeksen maakt het niet uit welke maanden we onderweg vastleggen: een nieuw vastgelegde maand krijgt
        // precies de regels die hij toch al had.
        let stored = storedPlans
        var m = startMonth
        var guardCount = 0
        while m <= current && guardCount < 1200 {
            if var existing = months[m.key] {
                var changed = false
                for pot in pots where m >= pot.startMonth && !hasAllocation(pot.id, in: existing) {
                    putDefault(pot, in: m, into: &existing)
                    changed = true
                }
                for h in holdings where m >= h.startMonth && !hasAllocation(h.id, in: existing) {
                    putDefault(h, in: m, into: &existing)
                    changed = true
                }
                if changed { months[m.key] = existing }
            } else {
                months[m.key] = synthesizedPlan(for: m, using: stored)
            }
            m = m.adding(1)
            guardCount += 1
        }
    }

    // MARK: Dagen

    /// Dag van de maand waarop het salaris binnenkomt (1...31): de `payDay`. Korte maanden gebruiken hun laatste dag.
    /// Bij een schema om de zoveel weken of dagen is dit alleen de terugval voor een maand zonder uitbetaling; welke dag
    /// "de salarisdag" van een bepaalde maand is, zegt `salaryDay(in:)`.
    func salaryDay() -> Int {
        YearMonth.clampedDay(salary.payDay)
    }

    /// Dag waarop een inkomstenregel binnenkomt: de eigen dag, anders de salarisdag (`salaryDay()`, de `payDay`).
    /// Gebruik `incomeDay(of:in:)` als de maand bekend is: bij een salaris om de zoveel weken of dagen volgt de regel
    /// zonder eigen dag de eerste uitbetaling van die maand.
    func incomeDay(of line: MoneyLine) -> Int {
        YearMonth.clampedDay(line.day ?? salaryDay())
    }

    /// Dag waarop een inkomstenregel in `month` binnenkomt: de eigen dag, anders de salarisdag van die maand
    /// (`salaryDay(in:)`: de eerste uitbetaling van de maand, of de `payDay`-terugval). Bij het maandelijkse schema gelijk
    /// aan `incomeDay(of:)`.
    func incomeDay(of line: MoneyLine, in month: YearMonth) -> Int {
        YearMonth.clampedDay(line.day ?? salaryDay(in: month))
    }

    /// Dag waarop een uitgave van de rekening gaat: de eigen dag, anders de 1e.
    func expenseDay(of line: MoneyLine) -> Int {
        YearMonth.clampedDay(line.day ?? 1)
    }

    /// Dag van `month` waarop de verdeling voor een spaarpot of belegging wordt overgeboekt.
    /// Volgorde: de dag van de hele maandverdeling, dan de dag van de pot of belegging zelf, dan de salarisdag van die maand
    /// (`salaryDay(in:)`: de eerste uitbetaling van de maand, of de `payDay`).
    /// Het resultaat past in de maand (31 in februari is de laatste dag van februari).
    func transferDay(for id: UUID, in month: YearMonth) -> Int {
        let raw = months[month.key]?.transferDay
            ?? pots.first(where: { $0.id == id })?.transferDay
            ?? holdings.first(where: { $0.id == id })?.transferDay
            ?? salaryDay(in: month)
        return min(YearMonth.clampedDay(raw), month.dayCount)
    }

    // MARK: Uitgaven en spaarpotten

    /// Verdeelt een uitgave over spaarpotten en bank. Delen van onbekende potten betaalt de bank.
    /// Delen die samen meer zijn dan het bedrag worden in volgorde afgekapt.
    func expenseSplit(of line: MoneyLine) -> ExpenseSplit {
        let total = CentsMath.int(line.amount)
        var left = max(0, total)
        var payments: [PotPayment] = []
        for share in line.potShares where left > 0 {
            let wanted = CentsMath.int(share.amount)
            guard wanted > 0, pot(share.potID) != nil else { continue }
            let take = min(wanted, left)
            payments.append(PotPayment(shareID: share.id, potID: share.potID, cents: take))
            left -= take
        }
        return ExpenseSplit(totalCents: total, pots: payments)
    }

    /// Het deel van een uitgave dat uit spaarpotten betaald wordt, precies zoals de rekenmotor het boekt.
    /// Gebruik dit in schermen in plaats van `MoneyLine.fromPots`: dat telt ook delen van potten die niet (meer)
    /// bestaan en delen van nul of minder mee, terwijl de bank die delen betaalt.
    func fromPots(of line: MoneyLine) -> Double {
        CentsMath.value(expenseSplit(of: line).potsCents)
    }

    /// Het deel van een uitgave dat van de bankrekening gaat, precies zoals de rekenmotor het boekt (zie `fromPots(of:)`).
    func fromBank(of line: MoneyLine) -> Double {
        CentsMath.value(expenseSplit(of: line).bankCents)
    }

    /// Het deel van de uitgaven van een maand dat uit spaarpotten betaald wordt.
    func expensesFromPots(in month: YearMonth) -> Double {
        CentsMath.value(monthFigures(month).fromPots)
    }

    /// Het deel van de uitgaven dat van de bankrekening gaat: totaal min het deel uit spaarpotten.
    func expensesFromBank(in month: YearMonth) -> Double {
        let f = monthFigures(month)
        return CentsMath.value(f.expenses - f.fromPots)
    }

    // MARK: Bedragen per maand

    /// Alle cijfers van een maand in hele centen, uit één keer het plan opzoeken.
    func monthFigures(_ month: YearMonth) -> MonthFigures {
        guard month >= startMonth else { return MonthFigures() }
        let stored = storedPlans
        return monthFigures(of: plan(for: month, using: stored), in: month, storedPlan: months[month.key],
                            potKeys: pots.map { $0.id.uuidString }, holdingKeys: holdings.map { $0.id.uuidString })
    }

    /// De cijfers van `month` uit een plan. `storedPlan` is het opgeslagen plan van de maand (of nil): alleen de
    /// verdeling daaruit telt, zoals bij `allocation(_:in:)`. `potKeys` en `holdingKeys` zijn de id's van de potten en
    /// beleggingen als tekst, in de volgorde van `pots` en `holdings`.
    ///
    /// Het inkomen komt eerst en hangt nooit van de verdeling af; een verdeling als percentage rekent daar overheen
    /// (`allocationCents`), dezelfde som als overal. Het salaris is de som van de uitbetalingen van de maand
    /// (`salaryCents(in:plan:)`). Alleen voor SCHATTINGEN (`estimatedFigures`) komt het salaris van buiten: `salaryCents`.
    func monthFigures(of p: MonthPlan, in month: YearMonth, storedPlan: MonthPlan?,
                      potKeys: [String], holdingKeys: [String], salaryCents given: Int? = nil) -> MonthFigures {
        var f = MonthFigures()
        var extra = 0
        for line in p.extraIncome { extra = CentsMath.add(extra, CentsMath.int(line.amount)) }
        let salaryCents = given ?? self.salaryCents(in: month, plan: p)
        f.income = CentsMath.add(salaryCents, extra)
        let bases = IncomeBases(salary: salaryCents, all: f.income)
        var expenses = 0
        var fromPots = 0
        for line in p.expenses {
            expenses = CentsMath.add(expenses, CentsMath.int(line.amount))
            // Een uitgave zonder delen uit een pot komt helemaal van de bank (spaart een `expenseSplit`).
            if !line.potShares.isEmpty { fromPots = CentsMath.add(fromPots, expenseSplit(of: line).potsCents) }
        }
        f.expenses = expenses
        f.fromPots = fromPots
        var saved = 0
        for (i, pot) in pots.enumerated() {
            saved = CentsMath.add(saved, allocationCents(pot, key: potKeys[i], in: month, storedPlan: storedPlan, bases: bases))
        }
        f.saved = saved
        var invested = 0
        for (i, holding) in holdings.enumerated() {
            invested = CentsMath.add(invested, allocationCents(holding, key: holdingKeys[i], in: month, storedPlan: storedPlan, bases: bases))
        }
        f.invested = invested
        return f
    }

    /// Voorbereiding om de cijfers van veel maanden achter elkaar snel uit te rekenen (zie `MonthFiguresBuilder`).
    func monthFiguresBuilder() -> MonthFiguresBuilder {
        MonthFiguresBuilder(self)
    }

    /// Verdeling voor één pot of belegging in een maand, in euro's. Bij een percentage van het inkomen is dit het bedrag
    /// dat daar in deze maand uit volgt (zie `allocationCents`). Overal waar de app een verdeling leest, komt dit getal.
    func allocation(_ id: UUID, in month: YearMonth) -> Double {
        switch allocationRule(id, in: month) {
        // Een vast bedrag met meer dan twee decimalen (import, oud bestand) telt overal op hele centen, zoals de som.
        case .amount(let value): return CentsMath.value(CentsMath.int(value))
        case .percent(let rule): return CentsMath.value(AllocationMath.cents(of: rule, bases: incomeBases(in: month)))
        }
    }

    /// Zet de verdeling van een maand op een vast bedrag (een eventuele overschrijving met een percentage vervalt).
    mutating func setAllocation(_ id: UUID, in month: YearMonth, amount: Double) {
        editPlan(month) {
            $0.allocations[id.uuidString] = amount.cents
            $0.percentAllocations.removeValue(forKey: id.uuidString)
        }
    }

    /// Het salaris van een maand volgens zijn plan: de SOM van de uitbetalingen van die maand (`salaryCents(in:plan:)`).
    /// Bij het maandelijkse schema is dat het maandsalaris (of de overschrijving van de maand), zoals altijd. Nooit een
    /// gemiddelde: voor schattingen zie `SalarySettings.averageMonthlyAmount`.
    func salaryAmount(in month: YearMonth, plan p: MonthPlan) -> Double {
        CentsMath.value(salaryCents(in: month, plan: p))
    }

    func salaryAmount(in month: YearMonth) -> Double {
        guard month >= startMonth else { return 0 }
        return salaryAmount(in: month, plan: plan(for: month))
    }

    func extraIncomeTotal(in month: YearMonth) -> Double {
        guard month >= startMonth else { return 0 }
        return CentsMath.value(CentsMath.sum(plan(for: month).extraIncome.map { CentsMath.int($0.amount) }))
    }

    func income(in month: YearMonth) -> Double {
        CentsMath.value(monthFigures(month).income)
    }

    /// Totaal van alle uitgaven, ook het deel dat uit spaarpotten komt.
    func expensesTotal(in month: YearMonth) -> Double {
        CentsMath.value(monthFigures(month).expenses)
    }

    func savedTotal(in month: YearMonth) -> Double {
        CentsMath.value(monthFigures(month).saved)
    }

    func investedTotal(in month: YearMonth) -> Double {
        CentsMath.value(monthFigures(month).invested)
    }

    /// Wat er nog te verdelen is in een maand: inkomen − uitgaven van de bank − verdeeld − belegd.
    /// Uitgaven die uit een spaarpot komen kosten het maandbudget niets.
    func remaining(in month: YearMonth) -> Double {
        CentsMath.value(monthFigures(month).remaining)
    }

    func summary(of month: YearMonth, current: YearMonth) -> MonthSummary {
        let f = monthFigures(month)
        return MonthSummary(month: month,
                            income: CentsMath.value(f.income),
                            expenses: CentsMath.value(f.expenses),
                            fromPots: CentsMath.value(f.fromPots),
                            saved: CentsMath.value(f.saved),
                            invested: CentsMath.value(f.invested),
                            isProjected: month > current)
    }

    func periodSummary(_ mode: PeriodMode, containing focus: YearMonth, current: YearMonth) -> PeriodSummary {
        PeriodSummary(months: mode.months(containing: focus).map { summary(of: $0, current: current) })
    }

    func summaries(from start: YearMonth, count: Int, current: YearMonth) -> [MonthSummary] {
        start.range(count: count).map { summary(of: $0, current: current) }
    }

    // MARK: Regels (inkomsten en uitgaven)

    enum LineKind { case income, expense }

    /// Slaat een regel op in een maand: een nieuwe regel wordt toegevoegd, een bestaande (zelfde id) vervangen.
    /// Een terugkerende regel geldt vanaf deze maand voor alle volgende maanden (`.thisAndFollowing`), ook voor maanden
    /// die al zijn opgeslagen. Voor de keuze "alleen deze maand" zie `updateLine(_:kind:in:scope:)`.
    mutating func upsertLine(_ line: MoneyLine, kind: LineKind, in month: YearMonth, scope: SeriesScope = .thisAndFollowing) {
        updateLine(line, kind: kind, in: month, scope: scope)
    }

    /// Haalt een regel weg. Een terugkerende regel stopt daarmee vanaf deze maand (`.thisAndFollowing`); voor de keuze
    /// "alleen deze maand" zie `removeLine(id:kind:in:scope:)`.
    mutating func deleteLine(id: UUID, kind: LineKind, in month: YearMonth, scope: SeriesScope = .thisAndFollowing) {
        removeLine(id: id, kind: kind, in: month, scope: scope)
    }

    // MARK: Verdeelhulpjes

    /// Zet de verdeling van een maand terug naar de standaardinleg (een vast bedrag of een percentage, per pot en belegging).
    mutating func applyDefaultAllocations(in month: YearMonth) {
        var fresh = MonthPlan()
        for pot in pots { putDefault(pot, in: month, into: &fresh, zeroBeforeStart: true) }
        for h in holdings { putDefault(h, in: month, into: &fresh, zeroBeforeStart: true) }
        editPlan(month) {
            $0.allocations = fresh.allocations
            $0.percentAllocations = fresh.percentAllocations
        }
    }

    /// Zet de verdeling van een maand op nul (ook een percentage: de overschrijving wordt een bedrag van nul).
    mutating func clearAllocations(in month: YearMonth) {
        let ids = pots.map(\.id) + holdings.map(\.id)
        editPlan(month) { plan in
            for id in ids {
                plan.allocations[id.uuidString] = 0
                plan.percentAllocations.removeValue(forKey: id.uuidString)
            }
        }
    }

    /// Verdeelt wat er over is gelijk over alle spaarpotten (alleen als er iets over is).
    /// Er blijft geen cent liggen: de resterende centen gaan naar de eerste potten.
    mutating func spreadRemainingOverPots(in month: YearMonth) {
        let left = monthFigures(month).remaining
        guard left > 0, !pots.isEmpty else { return }
        let count = pots.count
        let base = left / count
        let extra = left % count
        for (i, pot) in pots.enumerated() {
            let share = base + (i < extra ? 1 : 0)
            let current = CentsMath.int(allocation(pot.id, in: month))
            setAllocation(pot.id, in: month, amount: CentsMath.value(current + share))
        }
    }
}
