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
}

/// De opgeslagen maandplannen oplopend op maand. Voor lussen over veel maanden: zo hoeft het laatste plan vóór een
/// maand niet bij elke maand opnieuw te worden gezocht.
struct StoredPlans {
    private var keys: [YearMonth] = []
    private var plans: [MonthPlan] = []

    init(_ months: [String: MonthPlan]) {
        var list: [(month: YearMonth, plan: MonthPlan)] = []
        for (key, plan) in months {
            if let m = YearMonth(key: key) { list.append((m, plan)) }
        }
        list.sort { $0.month < $1.month }
        keys = list.map { $0.month }
        plans = list.map { $0.plan }
    }

    /// Het laatst opgeslagen plan vóór `month`.
    func latest(before month: YearMonth) -> MonthPlan? {
        var lo = 0
        var hi = keys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if keys[mid] < month { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 ? nil : plans[lo - 1]
    }
}

/// Rekent de cijfers van veel maanden achter elkaar uit, zonder voor elke maand een plan met nieuwe regel-id's op te
/// bouwen. Geeft dezelfde cijfers als `FinanceData.monthFigures(_:)` (een maand zonder opgeslagen plan krijgt de
/// terugkerende regels van het laatst opgeslagen plan, de verdeling uit de standaardinleg).
struct MonthFiguresBuilder {
    private let data: FinanceData
    private let stored: StoredPlans
    private let potKeys: [String]
    private let holdingKeys: [String]

    fileprivate init(_ data: FinanceData) {
        self.data = data
        self.stored = StoredPlans(data.months)
        self.potKeys = data.pots.map { $0.id.uuidString }
        self.holdingKeys = data.holdings.map { $0.id.uuidString }
    }

    func figures(_ month: YearMonth) -> MonthFigures {
        guard month >= data.startMonth else { return MonthFigures() }
        let storedPlan = data.months[month.key]
        var plan = storedPlan ?? MonthPlan()
        if storedPlan == nil, let previous = stored.latest(before: month) {
            // Alleen de terugkerende regels; de id's blijven zoals ze waren (voor de bedragen maken ze niet uit).
            plan.extraIncome = previous.extraIncome.filter { $0.isRecurring }
            plan.expenses = previous.expenses.filter { $0.isRecurring }
        }
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

    /// Het laatst opgeslagen plan vóór `month`.
    private func latestStoredPlan(before month: YearMonth) -> MonthPlan? {
        var best: (YearMonth, MonthPlan)?
        for (key, plan) in months {
            guard let m = YearMonth(key: key), m < month else { continue }
            if best == nil || m > best!.0 { best = (m, plan) }
        }
        return best?.1
    }

    /// Kopieert de terugkerende regels naar `month`. De nieuwe id is afgeleid van de oude regel en de maand,
    /// zodat een verwachte regel van een nog niet vastgelegde maand elke keer dezelfde id heeft.
    private func copiedRecurring(_ lines: [MoneyLine], into month: YearMonth) -> [MoneyLine] {
        lines.filter { $0.isRecurring }.map { line in
            var copy = line
            copy.id = StableID.uuid("line|\(line.id.uuidString)|\(month.key)")
            return copy
        }
    }

    /// Standaardverdeling van een maand uit de instellingen van potten en beleggingen.
    func defaultAllocation(_ id: UUID, in month: YearMonth) -> Double {
        if let pot = pots.first(where: { $0.id == id }) {
            return month >= pot.startMonth ? pot.monthlyContribution : 0
        }
        if let h = holdings.first(where: { $0.id == id }) {
            return month >= h.startMonth ? h.monthlyContribution : 0
        }
        return 0
    }

    /// Plan afgeleid uit standaarden (voor maanden die nog niet zijn vastgelegd).
    /// `transferDay` blijft nil: de overschrijfdag volgt dan de pot, belegging of salarisdag.
    func synthesizedPlan(for month: YearMonth) -> MonthPlan {
        synthesizedPlan(for: month, previous: latestStoredPlan(before: month))
    }

    /// Zoals `synthesizedPlan(for:)`, met een vooraf gesorteerde lijst van opgeslagen plannen (sneller in lussen).
    func synthesizedPlan(for month: YearMonth, using stored: StoredPlans) -> MonthPlan {
        synthesizedPlan(for: month, previous: stored.latest(before: month))
    }

    private func synthesizedPlan(for month: YearMonth, previous prev: MonthPlan?) -> MonthPlan {
        var plan = MonthPlan()
        if let prev = prev {
            plan.extraIncome = copiedRecurring(prev.extraIncome, into: month)
            plan.expenses = copiedRecurring(prev.expenses, into: month)
        }
        for pot in pots where month >= pot.startMonth {
            plan.allocations[pot.id.uuidString] = pot.monthlyContribution
        }
        for h in holdings where month >= h.startMonth {
            plan.allocations[h.id.uuidString] = h.monthlyContribution
        }
        return plan
    }

    /// Opgeslagen plan, of een afgeleid plan.
    func plan(for month: YearMonth) -> MonthPlan {
        months[month.key] ?? synthesizedPlan(for: month)
    }

    /// Zoals `plan(for:)`, met een vooraf gesorteerde lijst van opgeslagen plannen (sneller in lussen).
    func plan(for month: YearMonth, using stored: StoredPlans) -> MonthPlan {
        months[month.key] ?? synthesizedPlan(for: month, using: stored)
    }

    /// Past een maandplan aan en slaat het op.
    mutating func editPlan(_ month: YearMonth, _ body: (inout MonthPlan) -> Void) {
        var p = plan(for: month)
        body(&p)
        months[month.key] = p
    }

    /// Legt alle maanden t/m `current` vast, zodat latere wijzigingen van standaarden het verleden niet veranderen.
    mutating func materialize(upTo current: YearMonth) {
        var m = startMonth
        var guardCount = 0
        while m <= current && guardCount < 1200 {
            if var existing = months[m.key] {
                var changed = false
                for pot in pots where m >= pot.startMonth && existing.allocations[pot.id.uuidString] == nil {
                    existing.allocations[pot.id.uuidString] = pot.monthlyContribution
                    changed = true
                }
                for h in holdings where m >= h.startMonth && existing.allocations[h.id.uuidString] == nil {
                    existing.allocations[h.id.uuidString] = h.monthlyContribution
                    changed = true
                }
                if changed { months[m.key] = existing }
            } else {
                months[m.key] = synthesizedPlan(for: m)
            }
            m = m.adding(1)
            guardCount += 1
        }
    }

    // MARK: Dagen

    /// Dag van de maand waarop het salaris binnenkomt (1...31). Korte maanden gebruiken hun laatste dag.
    func salaryDay() -> Int {
        YearMonth.clampedDay(salary.payDay)
    }

    /// Dag waarop een inkomstenregel binnenkomt: de eigen dag, anders de salarisdag.
    func incomeDay(of line: MoneyLine) -> Int {
        YearMonth.clampedDay(line.day ?? salaryDay())
    }

    /// Dag waarop een uitgave van de rekening gaat: de eigen dag, anders de 1e.
    func expenseDay(of line: MoneyLine) -> Int {
        YearMonth.clampedDay(line.day ?? 1)
    }

    /// Dag van `month` waarop de verdeling voor een spaarpot of belegging wordt overgeboekt.
    /// Volgorde: de dag van de hele maandverdeling, dan de dag van de pot of belegging zelf, dan de salarisdag.
    /// Het resultaat past in de maand (31 in februari is de laatste dag van februari).
    func transferDay(for id: UUID, in month: YearMonth) -> Int {
        let raw = months[month.key]?.transferDay
            ?? pots.first(where: { $0.id == id })?.transferDay
            ?? holdings.first(where: { $0.id == id })?.transferDay
            ?? salary.payDay
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
        return monthFigures(of: plan(for: month), in: month, storedPlan: months[month.key],
                            potKeys: pots.map { $0.id.uuidString }, holdingKeys: holdings.map { $0.id.uuidString })
    }

    /// De cijfers van `month` uit een plan. `storedPlan` is het opgeslagen plan van de maand (of nil): alleen de
    /// verdeling daaruit telt, zoals bij `allocation(_:in:)`. `potKeys` en `holdingKeys` zijn de id's van de potten en
    /// beleggingen als tekst, in de volgorde van `pots` en `holdings`.
    fileprivate func monthFigures(of p: MonthPlan, in month: YearMonth, storedPlan: MonthPlan?,
                                  potKeys: [String], holdingKeys: [String]) -> MonthFigures {
        var f = MonthFigures()
        f.income = CentsMath.add(CentsMath.int(salaryAmount(in: month, plan: p)),
                                 CentsMath.sum(p.extraIncome.map { CentsMath.int($0.amount) }))
        f.expenses = CentsMath.sum(p.expenses.map { CentsMath.int($0.amount) })
        f.fromPots = CentsMath.sum(p.expenses.map { expenseSplit(of: $0).potsCents })
        var saved = 0
        for (i, pot) in pots.enumerated() {
            let a = storedPlan?.allocations[potKeys[i]] ?? (month >= pot.startMonth ? pot.monthlyContribution : 0)
            saved = CentsMath.add(saved, CentsMath.int(a))
        }
        f.saved = saved
        var invested = 0
        for (i, holding) in holdings.enumerated() {
            let a = storedPlan?.allocations[holdingKeys[i]] ?? (month >= holding.startMonth ? holding.monthlyContribution : 0)
            invested = CentsMath.add(invested, CentsMath.int(a))
        }
        f.invested = invested
        return f
    }

    /// Voorbereiding om de cijfers van veel maanden achter elkaar snel uit te rekenen (zie `MonthFiguresBuilder`).
    func monthFiguresBuilder() -> MonthFiguresBuilder {
        MonthFiguresBuilder(self)
    }

    /// Verdeling voor één pot of belegging in een maand.
    func allocation(_ id: UUID, in month: YearMonth) -> Double {
        if let stored = months[month.key], let v = stored.allocations[id.uuidString] { return v }
        return defaultAllocation(id, in: month)
    }

    mutating func setAllocation(_ id: UUID, in month: YearMonth, amount: Double) {
        editPlan(month) { $0.allocations[id.uuidString] = amount.cents }
    }

    func salaryAmount(in month: YearMonth, plan p: MonthPlan) -> Double {
        if let override = p.salaryOverride { return override.cents }
        return salary.monthlyAmount(hoursOverride: p.hoursOverride)
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

    mutating func upsertLine(_ line: MoneyLine, kind: LineKind, in month: YearMonth) {
        editPlan(month) { plan in
            switch kind {
            case .income:
                if let i = plan.extraIncome.firstIndex(where: { $0.id == line.id }) { plan.extraIncome[i] = line } else { plan.extraIncome.append(line) }
            case .expense:
                if let i = plan.expenses.firstIndex(where: { $0.id == line.id }) { plan.expenses[i] = line } else { plan.expenses.append(line) }
            }
        }
    }

    mutating func deleteLine(id: UUID, kind: LineKind, in month: YearMonth) {
        editPlan(month) { plan in
            switch kind {
            case .income: plan.extraIncome.removeAll { $0.id == id }
            case .expense: plan.expenses.removeAll { $0.id == id }
            }
        }
    }

    // MARK: Verdeelhulpjes

    /// Zet de verdeling van een maand terug naar de standaardinleg.
    mutating func applyDefaultAllocations(in month: YearMonth) {
        var fresh: [String: Double] = [:]
        for pot in pots { fresh[pot.id.uuidString] = month >= pot.startMonth ? pot.monthlyContribution : 0 }
        for h in holdings { fresh[h.id.uuidString] = month >= h.startMonth ? h.monthlyContribution : 0 }
        editPlan(month) { $0.allocations = fresh }
    }

    mutating func clearAllocations(in month: YearMonth) {
        let ids = pots.map(\.id) + holdings.map(\.id)
        editPlan(month) { plan in
            for id in ids { plan.allocations[id.uuidString] = 0 }
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
