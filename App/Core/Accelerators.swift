import Foundation

/// Een aanpassing aan het basisscenario van een doel. Meerdere aanpassingen kunnen worden opgeteld.
struct ScenarioChange: Equatable {
    var extraMonthly: Double = 0
    var extraReturn: Double = 0
    var oneOff: Double = 0
    var stepUp: Double = 0
    var targetFactor: Double = 1

    func combined(with other: ScenarioChange) -> ScenarioChange {
        ScenarioChange(extraMonthly: extraMonthly + other.extraMonthly,
                       extraReturn: extraReturn + other.extraReturn,
                       oneOff: oneOff + other.oneOff,
                       stepUp: stepUp + other.stepUp,
                       targetFactor: targetFactor * other.targetFactor)
    }

    var isEmpty: Bool { self == ScenarioChange() }
}

/// Een manier om een doel sneller te halen, afgeleid van jouw eigen gegevens.
struct Accelerator: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var change: ScenarioChange
    /// Nieuwe looptijd in maanden met alleen deze versneller; nil = nog steeds niet binnen 100 jaar.
    var newMonths: Int?
    /// Maanden eerder dan nu. nil als het doel nu niet gehaald wordt.
    var monthsSaved: Int?
    /// Het doel wordt met deze versneller wel haalbaar (binnen 100 jaar).
    var makesReachable: Bool
}

struct GoalCurves: Equatable {
    var baseline: [Double]
    var scenario: [Double]
    var target: Double
    var scenarioTarget: Double
}

/// De soorten versnellers, herkend aan hun id (zie `FinanceData.accelerators`).
enum AcceleratorKind: Equatable {
    case free, income5, bank, costs, shift, hours, stepUp, target
    /// Tien procent minder op één uitgaveregel (het id van de regel van de huidige maand).
    case expense(UUID)
    /// Overschot in een andere spaarpot (het id van die pot).
    case pot(UUID)
    case unknown

    var isExpense: Bool {
        if case .expense = self { return true }
        return false
    }

    init(id: String) {
        switch id {
        case "free": self = .free
        case "income5": self = .income5
        case "bank": self = .bank
        case "costs": self = .costs
        case "shift": self = .shift
        case "hours": self = .hours
        case "stepup": self = .stepUp
        case "target": self = .target
        default:
            if id.hasPrefix("expense-"), let uuid = UUID(uuidString: String(id.dropFirst("expense-".count))) {
                self = .expense(uuid)
            } else if id.hasPrefix("pot-"), let uuid = UUID(uuidString: String(id.dropFirst("pot-".count))) {
                self = .pot(uuid)
            } else {
                self = .unknown
            }
        }
    }
}

// MARK: - Versnellers vinden

/// De belegging met de hoogste kosten en wat een goedkoper product de portefeuille oplevert.
fileprivate struct CostCandidate {
    var holding: Holding
    var gain: Double
}

/// Het deel van de portefeuille met het laagste rendement dat naar het hoogste kan.
fileprivate struct ShiftCandidate {
    var low: Holding
    var lowValue: Double
    var high: Holding
    var highValue: Double
    var share: Double
    var gain: Double
}

extension FinanceData {
    /// Vanaf dit bedrag per maand stelt de app voor een uitgave 10% te verlagen.
    fileprivate static let minimumExpenseForAccelerator: Double = 20

    /// Er staan uitgaven in deze maand die als "Verlaag ... met 10%" zouden worden voorgesteld, maar niet terugkerend zijn.
    /// Een eenmalige uitgave levert geen vaste maandinleg op; de pagina legt uit waarom ze niet verschijnen.
    func hasOneOffExpensesWorthCutting(current: YearMonth) -> Bool {
        plan(for: current).expenses.contains { $0.amount >= Self.minimumExpenseForAccelerator && !$0.isRecurring }
    }

    /// Looptijd van een doel met aanpassingen.
    func scenarioMonths(_ inputs: GoalInputs, change: ScenarioChange) -> Int? {
        Growth.monthsToReach(target: inputs.target * change.targetFactor,
                             start: inputs.start,
                             monthly: inputs.monthly + change.extraMonthly,
                             annualReturn: inputs.effectiveReturn + change.extraReturn,
                             stepUp: change.stepUp,
                             oneOff: change.oneOff)
    }

    func combine(_ accelerators: [Accelerator]) -> ScenarioChange {
        accelerators.reduce(ScenarioChange()) { $0.combined(with: $1.change) }
    }

    /// Grafiekdata: basis en scenario, beide t/m `months` maanden.
    func goalCurves(for goal: LifeGoal, change: ScenarioChange, months: Int, current: YearMonth) -> GoalCurves {
        let inputs = goalInputs(for: goal, current: current)
        let base = Growth.monthlySeries(start: inputs.start, monthly: inputs.monthly,
                                        annualReturn: inputs.effectiveReturn, months: months)
        let scen = Growth.monthlySeries(start: inputs.start, monthly: inputs.monthly + change.extraMonthly,
                                        annualReturn: inputs.effectiveReturn + change.extraReturn,
                                        months: months, stepUp: change.stepUp, oneOff: change.oneOff)
        return GoalCurves(baseline: base, scenario: scen, target: inputs.target,
                          scenarioTarget: inputs.target * change.targetFactor)
    }

    /// De belegging waarvan de kosten het zwaarst wegen (alleen als het verschil de moeite waard is).
    fileprivate func costSavingCandidate(current: YearMonth) -> CostCandidate? {
        let total = portfolioValue(current: current)
        guard total > 0 else { return nil }
        let valued = holdings.map { ($0, holdingValueNow($0, current: current)) }.filter { $0.1 > 0 }
        var best: (Holding, Double)?
        for (h, v) in valued where h.annualCost > 0.0035 {
            let gain = (v / total) * (h.annualCost - 0.002)
            if best == nil || gain > best!.1 { best = (h, gain) }
        }
        guard let (h, gain) = best, gain >= 0.0003 else { return nil }
        return CostCandidate(holding: h, gain: gain)
    }

    /// Het deel van de portefeuille dat van het laagste naar het hoogste verwachte rendement kan.
    fileprivate func shiftCandidate(current: YearMonth) -> ShiftCandidate? {
        let total = portfolioValue(current: current)
        guard total > 0 else { return nil }
        let valued = holdings.map { ($0, holdingValueNow($0, current: current)) }.filter { $0.1 > 0 }
        guard valued.count >= 2,
              let low = valued.min(by: { $0.0.netReturn < $1.0.netReturn }),
              let high = valued.max(by: { $0.0.netReturn < $1.0.netReturn }),
              low.0.id != high.0.id else { return nil }
        let share = low.1 / total
        let spread = high.0.netReturn - low.0.netReturn
        guard share >= 0.10, spread >= 0.02 else { return nil }
        return ShiftCandidate(low: low.0, lowValue: low.1, high: high.0, highValue: high.1,
                              share: share, gain: 0.5 * share * spread)
    }

    /// Alle versnellers die voor dit doel iets opleveren, met de grootste winst bovenaan.
    /// `today` is het moment waarop het banksaldo wordt bekeken (voor tests).
    func accelerators(for goal: LifeGoal, current: YearMonth, today: Date = Date()) -> [Accelerator] {
        let inputs = goalInputs(for: goal, current: current)
        let baseline = Growth.monthsToReach(target: inputs.target, start: inputs.start,
                                            monthly: inputs.monthly, annualReturn: inputs.effectiveReturn)
        if baseline == 0 { return [] }

        var candidates: [(id: String, title: String, detail: String, symbol: String, change: ScenarioChange)] = []

        // 1. Vrije ruimte van deze maand
        let free = remaining(in: current)
        if free >= 10 {
            candidates.append(("free", "Zet je vrije ruimte in",
                               "Deze maand heb je \(Fmt.euro(free)) nog niet verdeeld. Elke maand extra inleggen versnelt je doel.",
                               "tray.and.arrow.down",
                               ScenarioChange(extraMonthly: free)))
        }

        // 2. 5% van het inkomen
        let monthlyIncome = income(in: current)
        let fivePercent = (monthlyIncome * 0.05).cents
        if monthlyIncome > 0, fivePercent >= 10 {
            candidates.append(("income5", "Leg 5% van je inkomen extra in",
                               "Dat is \(Fmt.euro(fivePercent)) per maand op een inkomen van \(Fmt.euro(monthlyIncome)).",
                               "percent",
                               ScenarioChange(extraMonthly: fivePercent)))
        }

        // 3. Grootste terugkerende uitgaven 10% omlaag (een eenmalige uitgave levert geen vaste inleg op)
        let topExpenses = plan(for: current).expenses.filter { $0.amount >= Self.minimumExpenseForAccelerator && $0.isRecurring }
            .sorted { $0.amount > $1.amount }.prefix(3)
        for line in topExpenses {
            let saving = (line.amount * 0.10).cents
            candidates.append(("expense-\(line.id.uuidString)", "Verlaag \(line.name) met 10%",
                               "\(line.name) kost \(Fmt.euro(line.amount)) per maand. 10% minder is \(Fmt.euro(saving)) per maand voor je doel.",
                               "scissors",
                               ScenarioChange(extraMonthly: saving)))
        }

        // 4. Overtollig geld op de bankrekening
        let surplus = bankSurplusAboveBuffer(current: current, today: today)
        if surplus >= 100 {
            candidates.append(("bank", "Zet overtollig bankgeld in",
                               "Je rekening staat op \(Fmt.euro(bankBalanceNow(current: current, today: today))). Je buffer van \(Fmt.duration(months: Int(settings.bankBufferMonths))) aan uitgaven is \(Fmt.euro(bankBuffer(current: current))). De overige \(Fmt.euro(surplus)) kan werken.",
                               "building.columns",
                               ScenarioChange(oneOff: surplus)))
        }

        // 5. Spaarpotten boven hun doel
        for pot in pots {
            if case .pot(let fundingID) = goal.funding, fundingID == pot.id { continue }
            guard let g = pot.goalAmount, g > 0 else { continue }
            // Het overschot van nu: toepassen boekt het bedrag nu af, dus de inleg die later deze maand volgt telt niet mee.
            let over = (potBalanceNow(pot.id, current: current, today: today) - g).cents
            if over >= 50 {
                candidates.append(("pot-\(pot.id.uuidString)", "Overschot in \(pot.name) inzetten",
                                   "Spaarpot \(pot.name) staat \(Fmt.euro(over)) boven het doel van \(Fmt.euro(g)).",
                                   pot.symbol,
                                   ScenarioChange(oneOff: over)))
            }
        }

        // 6 en 7 gelden alleen als het doel uit je beleggingen komt
        if case .portfolio = goal.funding {
            // 6. Hoge kosten
            if let c = costSavingCandidate(current: current) {
                candidates.append(("costs", "Verlaag de kosten van \(c.holding.name)",
                                   "\(c.holding.name) kost \(Fmt.percent(c.holding.annualCost, digits: 2)) per jaar. Een gelijkwaardig product met 0,20% kosten levert je portefeuille gemiddeld \(Fmt.percent(c.gain, digits: 2)) extra rendement per jaar op.",
                                   "eurosign.arrow.circlepath",
                                   ScenarioChange(extraReturn: c.gain)))
            }

            // 7. Herverdelen naar hoger rendement
            if let s = shiftCandidate(current: current) {
                candidates.append(("shift", "Verschuif deel van \(s.low.name) naar \(s.high.name)",
                                   "\(s.low.name) verwacht \(Fmt.percent(s.low.netReturn)) en is \(Fmt.percent(s.share, digits: 0)) van je portefeuille; \(s.high.name) verwacht \(Fmt.percent(s.high.netReturn)). De helft verschuiven levert ongeveer \(Fmt.percent(s.gain, digits: 2)) extra per jaar op. Let op: een hoger verwacht rendement gaat meestal samen met meer risico.",
                                   "arrow.left.arrow.right",
                                   ScenarioChange(extraReturn: s.gain)))
            }
        }

        // 8. Meer uren werken (bij uurloon)
        if salary.mode == .hourly, salary.hourlyRate > 0 {
            let extra = (salary.hourlyRate * 2 * 52 / 12).cents
            if extra >= 10 {
                candidates.append(("hours", "Werk 2 uur extra per week",
                                   "Bij je uurloon van \(Fmt.euroExact(salary.hourlyRate)) levert dat ongeveer \(Fmt.euro(extra)) extra per maand op.",
                                   "clock.badge.plus",
                                   ScenarioChange(extraMonthly: extra)))
            }
        }

        // 9. Inleg jaarlijks verhogen
        if inputs.monthly > 0 {
            candidates.append(("stepup", "Verhoog je inleg elk jaar met 3%",
                               "Past bij een jaarlijkse loonsverhoging. Je begint bij \(Fmt.euro(inputs.monthly)) per maand en groeit mee.",
                               "chart.line.uptrend.xyaxis",
                               ScenarioChange(stepUp: 0.03)))
        }

        // 10. Doel 10% lager
        if inputs.target > 0 {
            let lower = (inputs.target * 0.9).cents
            let title: String
            let detail: String
            switch goal.kind {
            case .retirement:
                title = "Leef in je pensioen van 10% minder"
                detail = "Het benodigde kapitaal daalt van \(Fmt.euroWhole(inputs.target)) naar \(Fmt.euroWhole(lower))."
            case .partTime:
                title = "Houd het inkomensgat 10% kleiner"
                detail = "Het benodigde kapitaal daalt van \(Fmt.euroWhole(inputs.target)) naar \(Fmt.euroWhole(lower))."
            default:
                title = "Kies een doel dat 10% goedkoper is"
                detail = "Het doelbedrag daalt van \(Fmt.euroWhole(inputs.target)) naar \(Fmt.euroWhole(lower))."
            }
            candidates.append(("target", title, detail, "target", ScenarioChange(targetFactor: 0.9)))
        }

        var result: [Accelerator] = []
        for c in candidates {
            let months = scenarioMonths(inputs, change: c.change)
            var saved: Int?
            var reachable = false
            switch (baseline, months) {
            case (let b?, let m?):
                if m < b { saved = b - m } else { continue }
            case (nil, _?):
                reachable = true
            default:
                continue
            }
            result.append(Accelerator(id: c.id, title: c.title, detail: c.detail, symbol: c.symbol,
                                      change: c.change, newMonths: months, monthsSaved: saved,
                                      makesReachable: reachable))
        }

        return result.sorted { a, b in
            if a.makesReachable != b.makesReachable { return a.makesReachable }
            let sa = a.monthsSaved ?? (a.newMonths.map { -$0 } ?? Int.min)
            let sb = b.monthsSaved ?? (b.newMonths.map { -$0 } ?? Int.min)
            return sa > sb
        }
    }
}

// MARK: - Toepassen: beschrijving voor de bevestiging

/// Eén regel in de bevestiging: wat er verandert, van oud naar nieuw.
struct AcceleratorPlanLine: Identifiable, Equatable {
    var id: String
    var symbol: String
    /// Waar het over gaat, bijvoorbeeld "Inleg Vakantie".
    var title: String
    /// Oude en nieuwe waarde, al opgemaakt ("€ 100", "0,70%"). nil als er geen oude of nieuwe waarde is.
    var oldValue: String?
    var newValue: String?
    /// Toelichting achter de waarde, bijvoorbeeld "per maand, vanaf oktober 2026".
    var detail: String
    /// De hele regel als gewone zin. Dit komt in de samenvatting van de toepassing.
    var sentence: String
}

/// Wat een versneller zou veranderen, zonder iets te veranderen.
struct AcceleratorPlan: Equatable {
    var lines: [AcceleratorPlanLine] = []
    /// Aandachtspunten onder de regels.
    var notes: [String] = []
    /// Een uitleg die boven de regels moet staan, omdat toepassen iets anders doet dan de titel zegt (nil = niet nodig).
    var headline: String?
    /// Looptijd van het doel nu en na het toepassen (nil = niet haalbaar binnen 100 jaar).
    var monthsBefore: Int?
    var monthsAfter: Int?
    /// Waarom er niets te doen valt (alleen gevuld als `lines` leeg is).
    var message: String?
    /// Deze versneller is al toegepast en moet eerst hersteld worden.
    var alreadyApplied = false

    var isEmpty: Bool { lines.isEmpty }
}

/// Resultaat van één keer uitvoeren (op een kopie voor de beschrijving, op de echte gegevens bij toepassen).
fileprivate struct AcceleratorRun {
    var lines: [AcceleratorPlanLine] = []
    var notes: [String] = []
    var message: String?
    /// Uitleg die boven de regels hoort (zie `AcceleratorPlan.headline`).
    var headline: String?
    /// Een eerlijker titel voor in "Toegepast", als de titel van de versneller niet zegt wat er echt gebeurt.
    var recordTitle: String?

    mutating func add(symbol: String, title: String, old: String?, new: String?, detail: String, sentence: String) {
        lines.append(AcceleratorPlanLine(id: "regel-\(lines.count)", symbol: symbol, title: title,
                                         oldValue: old, newValue: new, detail: detail, sentence: sentence))
    }
}

/// Vaste id's voor alles wat een toepassing aanmaakt, zodat herstellen precies dat kan terugvinden.
fileprivate enum AcceleratorIDs {
    static func entry(_ record: UUID, _ tag: String) -> UUID {
        StableID.uuid("accel|\(record.uuidString)|\(tag)")
    }

    static func snapshot(_ record: UUID, holding: UUID) -> UUID {
        entry(record, "snap|\(holding.uuidString)")
    }

    /// Dezelfde afleiding als `FinanceData.copiedRecurring`: de kopie van een terugkerende regel in een volgende maand.
    static func line(after previous: UUID, in monthKey: String) -> UUID {
        StableID.uuid("line|\(previous.uuidString)|\(monthKey)")
    }

    static let entryCount = 16

    /// Alle id's van bank- en potboekingen die een toepassing kan hebben gemaakt.
    static func entries(of record: UUID) -> Set<UUID> {
        var ids = Set<UUID>()
        for n in 0..<entryCount {
            ids.insert(entry(record, "bank-\(n)"))
            ids.insert(entry(record, "pot-\(n)"))
        }
        return ids
    }
}

/// Welke velden een soort versneller aanpast. Herstellen zet alleen die velden terug.
fileprivate struct AcceleratorFields: OptionSet {
    let rawValue: Int
    static let contribution = AcceleratorFields(rawValue: 1)
    static let cost = AcceleratorFields(rawValue: 2)
    static let value = AcceleratorFields(rawValue: 4)
    static let target = AcceleratorFields(rawValue: 8)
    static let funding = AcceleratorFields(rawValue: 16)
    static let plans = AcceleratorFields(rawValue: 32)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(kind: AcceleratorKind) {
        switch kind {
        case .free, .income5, .hours, .stepUp, .expense:
            self = [.contribution, .funding, .plans]
        case .bank, .pot:
            self = [.value, .funding]
        case .costs:
            self = [.cost]
        case .shift:
            self = [.value]
        case .target:
            self = [.target]
        case .unknown:
            self = [.contribution, .cost, .value, .target, .funding, .plans]
        }
    }
}

fileprivate extension GoalFunding {
    /// Eigen waarden: er is geen echte rekening, een versneller verplaatst hier geen geld.
    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}

fileprivate extension Pot {
    mutating func restoreAcceleratorFields(_ fields: AcceleratorFields, from old: Pot) {
        if fields.contains(.contribution) { monthlyContribution = old.monthlyContribution }
    }
}

fileprivate extension Holding {
    mutating func restoreAcceleratorFields(_ fields: AcceleratorFields, from old: Holding, removingSnapshot snapshotID: UUID) {
        if fields.contains(.contribution) { monthlyContribution = old.monthlyContribution }
        if fields.contains(.cost) { annualCost = old.annualCost }
        if fields.contains(.value) {
            units = old.units
            investedTotal = old.investedTotal
            snapshots.removeAll { $0.id == snapshotID }
        }
    }
}

fileprivate extension LifeGoal {
    mutating func restoreAcceleratorFields(_ fields: AcceleratorFields, from old: LifeGoal) {
        if fields.contains(.target) {
            targetAmount = old.targetAmount
            monthlySpending = old.monthlySpending
            monthlyGapOverride = old.monthlyGapOverride
        }
        if fields.contains(.funding) { funding = old.funding }
    }
}

/// Wat er bij herstellen ook terug moet in maanden die na het toepassen zijn ontstaan.
fileprivate struct AcceleratorRevert {
    /// De maand waarin de versneller is toegepast; alleen latere maanden komen in aanmerking.
    var applyMonth: YearMonth
    /// Maanden die de toepassing zelf aanraakte (die worden apart teruggezet).
    var recordedKeys: Set<String>
    /// Per pot of belegging: de vaste inleg vóór en na het terugzetten.
    var allocation: [String: (pre: Double, post: Double)]
    /// Bedrag van de verlaagde uitgaveregel vóór en na het terugzetten.
    var expenseAmount: (pre: Double, post: Double)?
}

fileprivate enum AcceleratorMath {
    /// Verdeelt `total` cent naar verhouding van de gewichten, zonder dat er een cent zoekraakt.
    static func distribute(cents total: Int, weights: [Int]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        guard total > 0 else { return weights.map { _ in 0 } }
        let w = weights.map { max(0, $0) }
        let sum = w.reduce(0, +)
        guard sum > 0 else {
            var all = Array(repeating: 0, count: w.count)
            all[0] = total
            return all
        }
        let exact = w.map { Double(total) * Double($0) / Double(sum) }
        var shares = exact.map { Int($0.rounded(.down)) }
        var rest = total - shares.reduce(0, +)
        let order = w.indices.sorted { a, b in
            let fa = exact[a] - Double(shares[a])
            let fb = exact[b] - Double(shares[b])
            if fa != fb { return fa > fb }
            return a < b
        }
        var k = 0
        while rest > 0 {
            shares[order[k % order.count]] += 1
            rest -= 1
            k += 1
        }
        while rest < 0 {
            if let biggest = shares.indices.max(by: { shares[$0] < shares[$1] }), shares[biggest] > 0 {
                shares[biggest] -= 1
            }
            rest += 1
        }
        return shares
    }

    /// De regels die bij elkaar horen: de regel `first` en alle afgeleide kopieën in latere maanden.
    /// Een kopie herken je aan zijn id (zie `AcceleratorIDs.line`); in welke volgorde de maanden zijn vastgelegd maakt niet uit.
    static func lineIDs(plans: [String: MonthPlan], first: UUID, lines: KeyPath<MonthPlan, [MoneyLine]>) -> [String: UUID] {
        var members: [UUID] = []
        var result: [String: UUID] = [:]
        for month in plans.keys.compactMap({ YearMonth(key: $0) }).sorted() {
            guard let plan = plans[month.key] else { continue }
            var found: UUID?
            if members.isEmpty {
                if plan[keyPath: lines].contains(where: { $0.id == first }) { found = first }
            } else {
                let candidates = Set(members.map { AcceleratorIDs.line(after: $0, in: month.key) })
                found = plan[keyPath: lines].first(where: { candidates.contains($0.id) })?.id
            }
            if let id = found {
                members.append(id)
                result[month.key] = id
            }
        }
        return result
    }

    /// Dezelfde uitgave? Een terugkerende regel krijgt elke maand een nieuw id; dit volgt die keten (in beide richtingen).
    static func sameLine(_ a: UUID, _ b: UUID, plans: [String: MonthPlan]) -> Bool {
        if a == b { return true }
        return lineIDs(plans: plans, first: a, lines: \.expenses).values.contains(b)
            || lineIDs(plans: plans, first: b, lines: \.expenses).values.contains(a)
    }

    /// Zet de plekken in een maandplan terug die een versneller aanpast; de rest van het plan blijft zoals het is.
    static func restoreSlots(in plan: inout MonthPlan, from base: MonthPlan, allocationIDs: Set<String>,
                             expenseLineID: UUID?, incomeLineID: UUID?) {
        for key in allocationIDs {
            if let value = base.allocations[key] {
                plan.allocations[key] = value
            } else {
                plan.allocations.removeValue(forKey: key)
            }
        }
        if let id = expenseLineID,
           let i = plan.expenses.firstIndex(where: { $0.id == id }),
           let j = base.expenses.firstIndex(where: { $0.id == id }) {
            plan.expenses[i].amount = base.expenses[j].amount
        }
        if let id = incomeLineID {
            plan.extraIncome.removeAll { $0.id == id }
        }
    }

    /// Zet terug wat uit een versneller is overgenomen in maanden die ná het toepassen zijn ontstaan (bijvoorbeeld
    /// doordat er een nieuwe maand begon): vaste inleg die nog de nieuwe standaard is, de verlaagde uitgave en de
    /// toegevoegde inkomstenregel. Maanden die de toepassing zelf aanraakte laat deze functie met rust.
    fileprivate static func revertDerived(in plans: inout [String: MonthPlan], revert: AcceleratorRevert,
                                          expenseLines: [String: UUID], incomeLines: [String: UUID],
                                          allocationPre: [String: Double]) {
        for key in Array(plans.keys) {
            guard let month = YearMonth(key: key), month > revert.applyMonth, !revert.recordedKeys.contains(key),
                  var plan = plans[key] else { continue }
            var changed = false
            for (id, values) in revert.allocation {
                let pre = allocationPre[id] ?? values.pre
                if let value = plan.allocations[id], value == pre {
                    plan.allocations[id] = values.post
                    changed = true
                }
            }
            if let lineID = expenseLines[key], let amounts = revert.expenseAmount,
               let i = plan.expenses.firstIndex(where: { $0.id == lineID }), plan.expenses[i].amount == amounts.pre {
                plan.expenses[i].amount = amounts.post
                changed = true
            }
            if let lineID = incomeLines[key], plan.extraIncome.contains(where: { $0.id == lineID }) {
                plan.extraIncome.removeAll { $0.id == lineID }
                changed = true
            }
            if changed { plans[key] = plan }
        }
    }

    /// Zin over de nieuwe looptijd van het doel (nil als er niets veranderde).
    static func outcomeSentence(goal: String, before: Int?, after: Int?) -> String? {
        switch (before, after) {
        case (let b?, let a?):
            guard a < b else { return nil }
            if a == 0 { return "Je hebt het benodigde bedrag voor \(goal) daarmee binnen." }
            return "Je haalt \(goal) nu over \(Fmt.duration(months: a)) in plaats van over \(Fmt.duration(months: b))."
        case (nil, let a?):
            if a == 0 { return "Je hebt het benodigde bedrag voor \(goal) daarmee binnen." }
            return "\(goal) wordt haalbaar: over \(Fmt.duration(months: a))."
        default:
            return nil
        }
    }
}

// MARK: - Toepassen

extension FinanceData {
    /// Het record van een versneller die al is toegepast voor dit doel (en nog niet hersteld).
    func appliedAccelerator(_ acceleratorID: String, for goalID: UUID) -> AppliedAccelerator? {
        appliedAccelerators.first { $0.acceleratorID == acceleratorID && $0.goalID == goalID }
    }

    /// Toegepaste versnellers voor een doel, de nieuwste laatst.
    func appliedAccelerators(for goalID: UUID) -> [AppliedAccelerator] {
        appliedAccelerators.filter { $0.goalID == goalID }
    }

    /// De toepassing waardoor deze versneller nu niet nog eens kan (nil = geen eerdere toepassing in de weg):
    /// - dezelfde versneller voor dit doel;
    /// - dezelfde uitgave in een latere maand (het id van een terugkerende regel verandert elke maand);
    /// - een uitgave of extra uren die al voor een ander doel zijn toegepast (dat effect geldt voor je hele budget).
    func applicationBlocking(_ acc: Accelerator, for goalID: UUID, current: YearMonth) -> AppliedAccelerator? {
        if let same = appliedAccelerator(acc.id, for: goalID) { return same }
        switch AcceleratorKind(id: acc.id) {
        case .hours:
            return appliedAccelerators.first { $0.acceleratorID == acc.id }
        case .expense(let lineID):
            if let same = appliedAccelerators.first(where: { $0.acceleratorID == acc.id }) { return same }
            guard appliedAccelerators.contains(where: { AcceleratorKind(id: $0.acceleratorID).isExpense }) else { return nil }
            var plans = months
            plans[current.key] = plan(for: current)
            return appliedAccelerators.first { record in
                guard case .expense(let first) = AcceleratorKind(id: record.acceleratorID) else { return false }
                return AcceleratorMath.sameLine(first, lineID, plans: plans)
            }
        default:
            return nil
        }
    }

    /// Waarom een versneller nu niet toegepast kan worden (nil = het mag).
    fileprivate func applyBlockReason(_ acc: Accelerator, goalID: UUID, current: YearMonth) -> String? {
        if let other = applicationBlocking(acc, for: goalID, current: current) {
            let name = other.goalID == goalID ? nil : other.goalID.flatMap { goal($0)?.name }
            return "Deze versneller is al toegepast" + (name.map { " voor \($0)" } ?? "") + ". Herstel hem eerst als je hem opnieuw wilt toepassen."
        }
        if case .unknown = AcceleratorKind(id: acc.id) { return "Deze versneller kan niet worden toegepast." }
        return nil
    }

    /// Beschrijft wat `apply` zou doen, zonder iets te wijzigen. De regels zijn precies de wijzigingen die
    /// `apply` doorvoert (oud naar nieuw). `lines` is leeg als er niets te doen valt; `message` zegt dan waarom.
    func applyPlan(_ acc: Accelerator, for goal: LifeGoal, current: YearMonth, now: Date = Date()) -> AcceleratorPlan {
        var plan = AcceleratorPlan()
        if let reason = applyBlockReason(acc, goalID: goal.id, current: current) {
            plan.message = reason
            plan.alreadyApplied = applicationBlocking(acc, for: goal.id, current: current)?.goalID == goal.id
            return plan
        }
        let g = self.goal(goal.id) ?? goal
        plan.monthsBefore = analyze(g, current: current).monthsToGoal
        var simulation = self
        let run = simulation.performAccelerator(acc, goal: g, current: current, now: now, recordID: UUID())
        guard !run.lines.isEmpty else {
            plan.message = run.message ?? "Hier valt niets te doen."
            return plan
        }
        plan.lines = run.lines
        plan.notes = run.notes
        plan.headline = run.headline
        plan.monthsAfter = simulation.analyze(simulation.goal(goal.id) ?? g, current: current).monthsToGoal
        return plan
    }

    /// Voert een versneller echt door in je gegevens en legt de oude toestand vast, zodat je hem kunt herstellen.
    /// Geeft nil als er niets te doen valt of als dezelfde versneller voor dit doel al is toegepast
    /// (zie `applyPlan` voor de reden).
    @discardableResult
    mutating func apply(_ acc: Accelerator, for goal: LifeGoal, current: YearMonth, now: Date) -> AppliedAccelerator? {
        guard applyBlockReason(acc, goalID: goal.id, current: current) == nil else { return nil }
        let original = self
        let g = self.goal(goal.id) ?? goal
        let before = analyze(g, current: current).monthsToGoal
        let recordID = UUID()
        let run = performAccelerator(acc, goal: g, current: current, now: now, recordID: recordID)
        guard !run.lines.isEmpty else {
            self = original
            return nil
        }
        let after = analyze(self.goal(goal.id) ?? g, current: current).monthsToGoal

        var summary = run.lines.map(\.sentence)
        if let outcome = AcceleratorMath.outcomeSentence(goal: g.name, before: before, after: after) {
            summary.append(outcome)
        }
        let record = AppliedAccelerator(id: recordID, acceleratorID: acc.id, goalID: goal.id, title: run.recordTitle ?? acc.title,
                                        date: now, summary: summary,
                                        before: Self.acceleratorBackup(from: original, to: self))
        appliedAccelerators.append(record)
        return record
    }

    /// Alleen wat er is veranderd, in de toestand van vóór het toepassen.
    private static func acceleratorBackup(from old: FinanceData, to new: FinanceData) -> AcceleratorBackup {
        var backup = AcceleratorBackup()
        for pot in new.pots {
            if let before = old.pots.first(where: { $0.id == pot.id }), before != pot { backup.pots.append(before) }
        }
        for holding in new.holdings {
            if let before = old.holdings.first(where: { $0.id == holding.id }), before != holding { backup.holdings.append(before) }
        }
        for goal in new.goals {
            if let before = old.goals.first(where: { $0.id == goal.id }), before != goal { backup.goals.append(before) }
        }
        for (key, plan) in new.months {
            if let before = old.months[key] {
                if before != plan { backup.plans[key] = before }
            } else {
                backup.newPlanKeys.append(key)
            }
        }
        backup.newPlanKeys.sort()
        if new.settings != old.settings { backup.settings = old.settings }
        if new.salary != old.salary { backup.salary = old.salary }
        return backup
    }

    // MARK: Uitvoeren per soort

    /// Voert de versneller uit op `self`. Laat `lines` leeg (en zet `message`) als er niets te doen valt;
    /// de gegevens zijn dan nog onaangeroerd.
    fileprivate mutating func performAccelerator(_ acc: Accelerator, goal g: LifeGoal, current: YearMonth,
                                                 now: Date, recordID: UUID) -> AcceleratorRun {
        var run = AcceleratorRun()
        let remainingBefore = remaining(in: current)

        switch AcceleratorKind(id: acc.id) {
        case .free, .income5:
            if let problem = contributionProblem(for: g, current: current) {
                run.message = problem
            } else {
                raiseContribution(by: acc.change.extraMonthly, goal: g, current: current, run: &run)
            }

        case .expense(let lineID):
            applyExpenseCut(lineID: lineID, goal: g, current: current, run: &run)

        case .hours:
            applyExtraHours(extra: acc.change.extraMonthly, goal: g, current: current, recordID: recordID, run: &run)

        case .stepUp:
            applyStepUp(acc, goal: g, current: current, run: &run)

        case .bank:
            applyBankSurplus(acc.change.oneOff, accelerator: acc, goal: g, current: current, now: now,
                             recordID: recordID, run: &run)

        case .pot(let sourceID):
            applyPotSurplus(acc.change.oneOff, from: sourceID, accelerator: acc, goal: g, current: current, now: now,
                            recordID: recordID, run: &run)

        case .costs:
            applyLowerCosts(goal: g, current: current, run: &run)

        case .shift:
            applyShift(goal: g, current: current, now: now, recordID: recordID, run: &run)

        case .target:
            applyLowerTarget(goal: g, current: current, run: &run)

        case .unknown:
            run.message = "Deze versneller kan niet worden toegepast."
        }

        if !run.lines.isEmpty {
            let after = remaining(in: current)
            if after < 0, after < remainingBefore {
                run.notes.append("Let op: je verdeelt dan \(Fmt.euro(-after)) meer dan je inkomen van deze maand.")
            }
        }
        return run
    }

    // MARK: Extra maandinleg

    /// Controle vooraf: kan de maandinleg voor dit doel omhoog? Zo niet, de reden in gewone woorden.
    fileprivate func contributionProblem(for goal: LifeGoal, current: YearMonth) -> String? {
        switch goal.funding {
        case .pot(let id):
            guard let target = self.pot(id) else { return "De spaarpot van dit doel bestaat niet meer." }
            if target.startMonth > current {
                return "De inleg van \(target.name) begint pas in \(Fmt.month(target.startMonth)). Pas eerst de startmaand van de spaarpot aan."
            }
            return nil
        case .portfolio:
            if holdings.isEmpty { return "Je hebt nog geen beleggingen waar de extra inleg naartoe kan." }
            if !holdings.contains(where: { $0.startMonth <= current }) {
                return "Je beleggingen beginnen pas later. Pas eerst hun startmaand aan."
            }
            return nil
        case .custom:
            return goals.contains(where: { $0.id == goal.id }) ? nil : "Dit doel staat niet in je gegevens."
        }
    }

    private func storedMonths(after current: YearMonth) -> [YearMonth] {
        months.keys.compactMap { YearMonth(key: $0) }.filter { $0 > current }.sorted()
    }

    /// Legt de verdeling van maanden vóór `current` vast die nog op de standaardinleg terugvalt,
    /// zodat een nieuwe standaardinleg het verleden niet verandert.
    private mutating func freezePastAllocations(_ id: UUID, contribution: Double, start: YearMonth, before current: YearMonth) {
        let key = id.uuidString
        for k in Array(months.keys) {
            guard let m = YearMonth(key: k), m < current, m >= start, months[k]?.allocations[key] == nil else { continue }
            months[k]?.allocations[key] = contribution
        }
    }

    /// Verhoogt de verdeling van een pot of belegging in de huidige maand en in alle al vastgelegde latere maanden.
    private mutating func raiseAllocation(_ id: UUID, from old: Double, by delta: Double, current: YearMonth) {
        setAllocation(id, in: current, amount: old + delta)
        let key = id.uuidString
        for m in storedMonths(after: current) {
            if let value = months[m.key]?.allocations[key] {
                months[m.key]?.allocations[key] = (value + delta).cents
            }
        }
    }

    private func contributionText(_ name: String, old: Double, new: Double, current: YearMonth) -> (detail: String, sentence: String) {
        let detail = "per maand, vanaf \(Fmt.month(current))"
        return (detail, "Inleg \(name) gaat van \(Fmt.euro(old)) naar \(Fmt.euro(new)) \(detail).")
    }

    /// Verhoogt de maandinleg van waaruit het doel gefinancierd wordt: de spaarpot, de beleggingen
    /// (naar verhouding van hun huidige inleg) of de eigen maandinleg van het doel.
    fileprivate mutating func raiseContribution(by extra: Double, goal g: LifeGoal, current: YearMonth,
                                                run: inout AcceleratorRun) {
        let delta = extra.cents
        guard delta > 0 else { return }

        switch g.funding {
        case .pot(let id):
            guard let i = pots.firstIndex(where: { $0.id == id }) else { return }
            let old = allocation(id, in: current)
            freezePastAllocations(id, contribution: pots[i].monthlyContribution, start: pots[i].startMonth, before: current)
            pots[i].monthlyContribution = (pots[i].monthlyContribution + delta).cents
            raiseAllocation(id, from: old, by: delta, current: current)
            let new = (old + delta).cents
            let text = contributionText(pots[i].name, old: old, new: new, current: current)
            run.add(symbol: pots[i].symbol, title: "Inleg \(pots[i].name)", old: Fmt.euro(old), new: Fmt.euro(new),
                    detail: text.detail, sentence: text.sentence)

        case .portfolio:
            let eligible = holdings.indices.filter { holdings[$0].startMonth <= current }
            guard !eligible.isEmpty else { return }
            var weights = eligible.map { max(0, CentsMath.int(allocation(holdings[$0].id, in: current))) }
            if weights.reduce(0, +) <= 0 {
                weights = eligible.map { max(0, CentsMath.int(holdingValueNow(holdings[$0], current: current))) }
            }
            if weights.reduce(0, +) <= 0 { weights = eligible.map { _ in 1 } }
            let shares = AcceleratorMath.distribute(cents: CentsMath.int(delta), weights: weights)
            for (n, i) in eligible.enumerated() where shares[n] > 0 {
                let share = CentsMath.value(shares[n])
                let id = holdings[i].id
                let old = allocation(id, in: current)
                freezePastAllocations(id, contribution: holdings[i].monthlyContribution, start: holdings[i].startMonth, before: current)
                holdings[i].monthlyContribution = (holdings[i].monthlyContribution + share).cents
                raiseAllocation(id, from: old, by: share, current: current)
                let new = (old + share).cents
                let text = contributionText(holdings[i].name, old: old, new: new, current: current)
                run.add(symbol: holdings[i].kind.symbol, title: "Inleg \(holdings[i].name)",
                        old: Fmt.euro(old), new: Fmt.euro(new), detail: text.detail, sentence: text.sentence)
            }

        case .custom(let start, let monthly, let annualReturn):
            guard let gi = goals.firstIndex(where: { $0.id == g.id }) else { return }
            let new = (monthly + delta).cents
            goals[gi].funding = .custom(start: start, monthly: new, annualReturn: annualReturn)
            let detail = "per maand"
            run.add(symbol: "calendar.badge.plus", title: "Maandinleg \(g.name)", old: Fmt.euro(monthly), new: Fmt.euro(new),
                    detail: detail,
                    sentence: "Maandinleg van \(g.name) gaat van \(Fmt.euro(monthly)) naar \(Fmt.euro(new)) \(detail).")
        }
    }

    // MARK: Uitgave 10% omlaag

    /// De maanden vanaf `current` waarin dezelfde regel staat: de huidige maand en elke al vastgelegde maand daarna
    /// met een afgeleide kopie. Maanden die nog niet zijn vastgelegd volgen vanzelf.
    private func lineChain(from firstID: UUID, current: YearMonth,
                           lines: KeyPath<MonthPlan, [MoneyLine]>) -> [(month: YearMonth, lineID: UUID)] {
        var plans = months
        plans[current.key] = plan(for: current)
        var chain: [(month: YearMonth, lineID: UUID)] = []
        for (key, id) in AcceleratorMath.lineIDs(plans: plans, first: firstID, lines: lines) {
            if let m = YearMonth(key: key), m >= current { chain.append((month: m, lineID: id)) }
        }
        return chain.sorted { $0.month < $1.month }
    }

    fileprivate mutating func applyExpenseCut(lineID: UUID, goal g: LifeGoal, current: YearMonth, run: inout AcceleratorRun) {
        guard let line = plan(for: current).expenses.first(where: { $0.id == lineID }), line.amount > 0 else {
            run.message = "Deze uitgave staat niet meer in \(Fmt.month(current))."
            return
        }
        if let problem = contributionProblem(for: g, current: current) {
            run.message = problem
            return
        }
        guard line.isRecurring else {
            run.message = "\(line.name.isEmpty ? "Deze uitgave" : line.name) komt maar één keer voor. Verlagen levert je doel geen vaste maandinleg op."
            return
        }
        let cut = (line.amount * 0.10).cents
        var smaller = line
        smaller.amount = (line.amount - cut).cents
        // Alleen wat van de bank afgaat komt vrij voor je doel; een deel uit een spaarpot niet.
        let freed = CentsMath.value(expenseSplit(of: line).bankCents - expenseSplit(of: smaller).bankCents)
        guard cut > 0, freed > 0 else {
            run.message = "Deze uitgave wordt vooral uit een spaarpot betaald. Verlagen levert je maandbudget niets extra op."
            return
        }

        for link in lineChain(from: lineID, current: current, lines: \.expenses) {
            editPlan(link.month) { plan in
                guard let i = plan.expenses.firstIndex(where: { $0.id == link.lineID }) else { return }
                let amount = plan.expenses[i].amount
                plan.expenses[i].amount = (amount - min(cut, amount)).cents
            }
        }

        let name = line.name.isEmpty ? "Uitgave" : line.name
        let detail = "per maand, vanaf \(Fmt.month(current))"
        run.add(symbol: "scissors", title: "Uitgave \(name)", old: Fmt.euro(line.amount), new: Fmt.euro(smaller.amount),
                detail: detail,
                sentence: "Uitgave \(name) gaat van \(Fmt.euro(line.amount)) naar \(Fmt.euro(smaller.amount)) \(detail).")
        raiseContribution(by: freed, goal: g, current: current, run: &run)
    }

    // MARK: Extra uren

    fileprivate mutating func applyExtraHours(extra: Double, goal g: LifeGoal, current: YearMonth,
                                              recordID: UUID, run: inout AcceleratorRun) {
        let amount = extra.cents
        guard amount > 0 else { return }
        if let problem = contributionProblem(for: g, current: current) {
            run.message = problem
            return
        }
        // Een terugkerende inkomstenregel: de maanden daarna nemen hem vanzelf over. Het verleden blijft zoals het was.
        let name = "Extra uren (2 uur per week)"
        var previous: UUID?
        for m in [current] + storedMonths(after: current) {
            let id = previous.map { AcceleratorIDs.line(after: $0, in: m.key) } ?? AcceleratorIDs.entry(recordID, "hours")
            editPlan(m) { $0.extraIncome.append(MoneyLine(id: id, name: name, amount: amount, isRecurring: true)) }
            previous = id
        }
        let detail = "per maand erbij, vanaf \(Fmt.month(current))"
        let rate = salary.mode == .hourly && salary.hourlyRate > 0 ? " Bij een uurloon van \(Fmt.euroExact(salary.hourlyRate))." : ""
        run.add(symbol: "clock.badge.plus", title: "Extra inkomsten", old: nil, new: Fmt.euro(amount), detail: detail,
                sentence: "Extra inkomsten van \(Fmt.euro(amount)) \(detail), als \"\(name)\".\(rate)")
        raiseContribution(by: amount, goal: g, current: current, run: &run)
        run.notes.append("Dit is een verwachting. Haal de regel \"\(name)\" weg bij je inkomsten als je de extra uren niet werkt.")
    }

    // MARK: Jaarlijkse stijging

    fileprivate mutating func applyStepUp(_ acc: Accelerator, goal g: LifeGoal, current: YearMonth, run: inout AcceleratorRun) {
        if let problem = contributionProblem(for: g, current: current) {
            run.message = problem
            return
        }
        let inputs = goalInputs(for: g, current: current)
        guard let goalMonths = acc.newMonths else {
            run.message = "Deze versneller kan niet worden toegepast."
            return
        }
        // De app kent geen automatische jaarlijkse verhoging van je inleg. Daarom verhogen we de inleg nu met het vaste
        // bedrag dat je doel even snel laat halen als elk jaar 3% meer inleggen (op hele euro's naar boven afgerond).
        func reaches(_ extra: Int) -> Bool {
            guard let m = Growth.monthsToReach(target: inputs.target, start: inputs.start,
                                               monthly: inputs.monthly + Double(extra),
                                               annualReturn: inputs.effectiveReturn) else { return false }
            return m <= goalMonths
        }
        if reaches(0) { return }
        var high = max(1, Int((inputs.monthly * acc.change.stepUp).rounded(.up)))
        while !reaches(high), high < 10_000_000 { high *= 2 }
        guard reaches(high) else { return }
        var low = 0
        while high - low > 1 {
            let mid = (low + high) / 2
            if reaches(mid) { high = mid } else { low = mid }
        }
        raiseContribution(by: Double(high), goal: g, current: current, run: &run)
        if !run.lines.isEmpty {
            // De titel van de versneller zegt "elk jaar"; wat er gebeurt is eenmalig. Zeg dat vooraf en in "Toegepast".
            let increase = Fmt.euro(Double(high))
            run.recordTitle = "Inleg eenmalig \(increase) per maand verhoogd"
            run.headline = "Dit is geen jaarlijkse verhoging. Je inleg gaat nu één keer omhoog met \(increase) per maand, een bedrag dat je doel even snel laat halen als elk jaar 3% meer inleggen."
            run.notes.append("De app kent geen automatische jaarlijkse verhoging. Wil je later weer meer inleggen, pas de inleg dan zelf aan.")
        }
    }

    // MARK: Eenmalige inleg uit bank of spaarpot

    /// Zet een eenmalig bedrag in de beleggingen, naar verhouding van hun waarde.
    fileprivate mutating func injectIntoHoldings(_ amount: Double, current: YearMonth, now: Date,
                                                 recordID: UUID, run: inout AcceleratorRun) {
        guard !holdings.isEmpty else { return }
        let all = Array(holdings.indices)
        var weights = all.map { max(0, CentsMath.int(holdingValueNow(holdings[$0], current: current))) }
        if weights.reduce(0, +) <= 0 { weights = all.map { _ in 1 } }
        let shares = AcceleratorMath.distribute(cents: CentsMath.int(amount), weights: weights)
        for (n, i) in all.enumerated() where shares[n] > 0 {
            let share = CentsMath.value(shares[n])
            let result = adjustHolding(at: i, valueDelta: share, investedDelta: share, current: current, date: now, recordID: recordID)
            run.add(symbol: holdings[i].kind.symbol, title: holdings[i].name, old: Fmt.euro(result.old), new: Fmt.euro(result.new),
                    detail: "waarde nu",
                    sentence: "\(holdings[i].name) gaat van \(Fmt.euro(result.old)) naar \(Fmt.euro(result.new)).")
        }
    }

    /// Zet de waarde en het ingelegde bedrag van een belegging met een nieuw meetpunt op `date`.
    /// Bij een belegging met koers verandert ook het aantal stuks.
    private mutating func adjustHolding(at i: Int, valueDelta: Double, investedDelta: Double, current: YearMonth,
                                        date: Date, recordID: UUID) -> (old: Double, new: Double) {
        let holding = holdings[i]
        let state = holdingStateNow(holding, current: current)
        let oldValue = state?.value ?? 0
        let oldInvested = state?.invested ?? 0
        let newValue = max(0, oldValue + valueDelta).cents
        let newInvested = max(0, oldInvested + investedDelta).cents
        if holding.isTracked, let price = holding.lastPrice, price > 0, let units = holding.units {
            holdings[i].units = max(0, units + (newValue - oldValue) / price)
        }
        holdings[i].investedTotal = newInvested
        // Het nieuwe meetpunt komt altijd na alle bestaande, zodat het meetelt als de laatste waarde.
        var when = date
        if let last = holding.snapshots.map(\.date).max(), last >= when { when = last.addingTimeInterval(1) }
        let snapshot = ValueSnapshot(id: AcceleratorIDs.snapshot(recordID, holding: holding.id), date: when,
                                     value: newValue, invested: newInvested)
        let position = holdings[i].snapshots.firstIndex(where: { $0.date > when }) ?? holdings[i].snapshots.count
        holdings[i].snapshots.insert(snapshot, at: position)
        return (oldValue, newValue)
    }

    /// Geeft de nieuwe bank- en potboekingen vanaf de gegeven aantallen een vast id, zodat herstellen ze terugvindt.
    private mutating func relabelNewEntries(bankFrom bankCount: Int, potFrom potCount: Int, recordID: UUID) {
        if bankEntries.count > bankCount {
            for k in bankCount..<bankEntries.count {
                bankEntries[k].id = AcceleratorIDs.entry(recordID, "bank-\(k - bankCount)")
            }
        }
        if potEntries.count > potCount {
            for k in potCount..<potEntries.count {
                potEntries[k].id = AcceleratorIDs.entry(recordID, "pot-\(k - potCount)")
            }
        }
    }

    private func balanceLine(title: String, old: Double, new: Double) -> (old: String, new: String, sentence: String) {
        (Fmt.euro(old), Fmt.euro(new), "\(title) gaat van \(Fmt.euro(old)) naar \(Fmt.euro(new)).")
    }

    fileprivate mutating func applyBankSurplus(_ rawAmount: Double, accelerator acc: Accelerator, goal g: LifeGoal,
                                               current: YearMonth, now: Date, recordID: UUID, run: inout AcceleratorRun) {
        var amount = rawAmount.cents
        guard amount > 0 else { return }
        let note = "Versneller: \(acc.title)"
        let bankBefore = bankBalanceNow(current: current, today: now)

        // Het voorstel kan verouderd zijn (bijvoorbeeld na een eerdere toepassing): haal nooit meer van de bank
        // dan er nu boven je buffer staat. Een doel met eigen waarden verplaatst geen echt geld.
        var smaller = false
        if !g.funding.isCustom {
            let available = bankSurplusAboveBuffer(current: current, today: now)
            guard available > 0 else {
                run.message = "Je bankrekening staat nu niet meer boven je buffer. Er is niets om in te zetten."
                return
            }
            if available < amount {
                amount = available
                smaller = true
            }
        }

        switch g.funding {
        case .pot(let id):
            guard let target = self.pot(id) else {
                run.message = "De spaarpot van dit doel bestaat niet meer."
                return
            }
            let potBefore = potBalanceNow(id, current: current, today: now)
            let (nb, np) = (bankEntries.count, potEntries.count)
            transferBankToPot(potID: id, amount: amount, note: note, date: now)
            relabelNewEntries(bankFrom: nb, potFrom: np, recordID: recordID)
            let bankAfter = bankBalanceNow(current: current, today: now)
            let potAfter = potBalanceNow(id, current: current, today: now)
            let bank = balanceLine(title: "Bankrekening", old: bankBefore, new: bankAfter)
            run.add(symbol: "building.columns", title: "Bankrekening", old: bank.old, new: bank.new,
                    detail: "\(Fmt.euro(amount)) gaat naar \(target.name)", sentence: bank.sentence)
            let potLine = balanceLine(title: "Spaarpot \(target.name)", old: potBefore, new: potAfter)
            run.add(symbol: target.symbol, title: "Spaarpot \(target.name)", old: potLine.old, new: potLine.new,
                    detail: "saldo nu", sentence: potLine.sentence)

        case .portfolio:
            guard !holdings.isEmpty else {
                run.message = "Je hebt nog geen beleggingen waar het geld naartoe kan."
                return
            }
            bankEntries.append(BankEntry(id: AcceleratorIDs.entry(recordID, "bank-0"), date: now, amount: -amount,
                                         kind: .withdrawal, note: "Versneller: naar beleggingen"))
            let bankAfter = bankBalanceNow(current: current, today: now)
            let bank = balanceLine(title: "Bankrekening", old: bankBefore, new: bankAfter)
            run.add(symbol: "building.columns", title: "Bankrekening", old: bank.old, new: bank.new,
                    detail: "\(Fmt.euro(amount)) gaat naar je beleggingen", sentence: bank.sentence)
            injectIntoHoldings(amount, current: current, now: now, recordID: recordID, run: &run)

        case .custom(let start, let monthly, let annualReturn):
            guard let gi = goals.firstIndex(where: { $0.id == g.id }) else {
                run.message = "Dit doel staat niet in je gegevens."
                return
            }
            let new = (start + amount).cents
            goals[gi].funding = .custom(start: new, monthly: monthly, annualReturn: annualReturn)
            run.add(symbol: "flag.checkered", title: "Startbedrag \(g.name)", old: Fmt.euro(start), new: Fmt.euro(new),
                    detail: "eigen waarden",
                    sentence: "Startbedrag van \(g.name) gaat van \(Fmt.euro(start)) naar \(Fmt.euro(new)).")
            run.notes.append("Dit doel rekent met eigen waarden. Het geld op je bankrekening blijft waar het staat.")
            return
        }
        if smaller {
            run.notes.append("Er staat nu minder boven je buffer dan voorgesteld; daarom is het bedrag lager.")
        }
        run.notes.append("Dit past alleen de app aan. Maak het geld ook zelf over bij je bank of broker.")
    }

    fileprivate mutating func applyPotSurplus(_ rawAmount: Double, from sourceID: UUID, accelerator acc: Accelerator,
                                              goal g: LifeGoal, current: YearMonth, now: Date, recordID: UUID,
                                              run: inout AcceleratorRun) {
        var amount = rawAmount.cents
        guard amount > 0 else { return }
        guard let source = self.pot(sourceID) else {
            run.message = "Die spaarpot bestaat niet meer."
            return
        }
        let note = "Versneller: \(acc.title)"
        let sourceBefore = potBalanceNow(sourceID, current: current, today: now)

        // Het voorstel kan verouderd zijn, en de inleg van later deze maand staat nog niet in de pot: haal nooit
        // meer uit de pot dan er nu boven het doel staat, zodat het saldo niet onder het doel of onder nul komt.
        // Een doel met eigen waarden verplaatst geen echt geld.
        var smaller = false
        if !g.funding.isCustom {
            guard let limit = source.goalAmount, limit > 0 else {
                run.message = "\(source.name) heeft geen doelbedrag meer, dus er is geen overschot."
                return
            }
            let available = max(0, (sourceBefore - limit).cents)
            guard available > 0 else {
                run.message = "\(source.name) staat nu niet meer boven het doel. Er is niets om in te zetten."
                return
            }
            if available < amount {
                amount = available
                smaller = true
            }
        }

        switch g.funding {
        case .pot(let id):
            guard id != sourceID, let target = self.pot(id) else {
                run.message = "De spaarpot van dit doel bestaat niet meer."
                return
            }
            let targetBefore = potBalanceNow(id, current: current, today: now)
            let (nb, np) = (bankEntries.count, potEntries.count)
            transfer(from: sourceID, to: id, amount: amount, note: note, date: now)
            relabelNewEntries(bankFrom: nb, potFrom: np, recordID: recordID)
            let from = balanceLine(title: "Spaarpot \(source.name)", old: sourceBefore,
                                   new: potBalanceNow(sourceID, current: current, today: now))
            run.add(symbol: source.symbol, title: "Spaarpot \(source.name)", old: from.old, new: from.new,
                    detail: "\(Fmt.euro(amount)) gaat naar \(target.name)", sentence: from.sentence)
            let to = balanceLine(title: "Spaarpot \(target.name)", old: targetBefore,
                                 new: potBalanceNow(id, current: current, today: now))
            run.add(symbol: target.symbol, title: "Spaarpot \(target.name)", old: to.old, new: to.new,
                    detail: "saldo nu", sentence: to.sentence)

        case .portfolio:
            guard !holdings.isEmpty else {
                run.message = "Je hebt nog geen beleggingen waar het geld naartoe kan."
                return
            }
            let (nb, np) = (bankEntries.count, potEntries.count)
            addPotEntry(potID: sourceID, amount: -amount, kind: .withdrawal, note: "Versneller: naar beleggingen", date: now)
            relabelNewEntries(bankFrom: nb, potFrom: np, recordID: recordID)
            let from = balanceLine(title: "Spaarpot \(source.name)", old: sourceBefore,
                                   new: potBalanceNow(sourceID, current: current, today: now))
            run.add(symbol: source.symbol, title: "Spaarpot \(source.name)", old: from.old, new: from.new,
                    detail: "\(Fmt.euro(amount)) gaat naar je beleggingen", sentence: from.sentence)
            injectIntoHoldings(amount, current: current, now: now, recordID: recordID, run: &run)

        case .custom(let start, let monthly, let annualReturn):
            guard let gi = goals.firstIndex(where: { $0.id == g.id }) else {
                run.message = "Dit doel staat niet in je gegevens."
                return
            }
            let new = (start + amount).cents
            goals[gi].funding = .custom(start: new, monthly: monthly, annualReturn: annualReturn)
            run.add(symbol: "flag.checkered", title: "Startbedrag \(g.name)", old: Fmt.euro(start), new: Fmt.euro(new),
                    detail: "eigen waarden",
                    sentence: "Startbedrag van \(g.name) gaat van \(Fmt.euro(start)) naar \(Fmt.euro(new)).")
            run.notes.append("Dit doel rekent met eigen waarden. Het geld in de spaarpot blijft waar het staat.")
            return
        }
        if smaller {
            run.notes.append("Er staat nu minder boven het doel van \(source.name) dan voorgesteld; daarom is het bedrag lager.")
        }
        run.notes.append("Dit past alleen de app aan. Maak het geld ook zelf over bij je bank of broker.")
    }

    // MARK: Rendement en kosten

    fileprivate mutating func applyLowerCosts(goal g: LifeGoal, current: YearMonth, run: inout AcceleratorRun) {
        guard case .portfolio = g.funding else {
            run.message = "Dit doel wordt niet uit je beleggingen gefinancierd."
            return
        }
        guard let candidate = costSavingCandidate(current: current),
              let i = holdings.firstIndex(where: { $0.id == candidate.holding.id }) else {
            run.message = "Je beleggingen hebben geen kosten meer die lager kunnen."
            return
        }
        let returnBefore = weightedNetReturn(current: current)
        let old = holdings[i].annualCost
        holdings[i].annualCost = 0.002
        let name = holdings[i].name
        run.add(symbol: "eurosign.arrow.circlepath", title: "Kosten \(name)", old: Fmt.percent(old, digits: 2),
                new: Fmt.percent(0.002, digits: 2), detail: "per jaar",
                sentence: "Kosten van \(name) gaan van \(Fmt.percent(old, digits: 2)) naar \(Fmt.percent(0.002, digits: 2)) per jaar.")
        let returnAfter = weightedNetReturn(current: current)
        run.add(symbol: "chart.line.uptrend.xyaxis", title: "Verwacht rendement beleggingen", old: Fmt.percent(returnBefore, digits: 2),
                new: Fmt.percent(returnAfter, digits: 2), detail: "per jaar na kosten",
                sentence: "Het verwachte rendement van je beleggingen gaat van \(Fmt.percent(returnBefore, digits: 2)) naar \(Fmt.percent(returnAfter, digits: 2)) per jaar.")
        run.notes.append("De app rekent voortaan met de lagere kosten. Kies zelf een gelijkwaardig product met lage kosten bij je broker.")
    }

    fileprivate mutating func applyShift(goal g: LifeGoal, current: YearMonth, now: Date, recordID: UUID, run: inout AcceleratorRun) {
        guard case .portfolio = g.funding else {
            run.message = "Dit doel wordt niet uit je beleggingen gefinancierd."
            return
        }
        guard let candidate = shiftCandidate(current: current),
              let lowIndex = holdings.firstIndex(where: { $0.id == candidate.low.id }),
              let highIndex = holdings.firstIndex(where: { $0.id == candidate.high.id }) else {
            run.message = "Er is geen belegging meer om naartoe te verschuiven."
            return
        }
        let moved = (candidate.lowValue * 0.5).cents
        guard moved > 0 else { return }
        let returnBefore = weightedNetReturn(current: current)
        let lowInvested = holdingStateNow(holdings[lowIndex], current: current)?.invested ?? 0
        let lowResult = adjustHolding(at: lowIndex, valueDelta: -moved, investedDelta: -(lowInvested * 0.5).cents,
                                      current: current, date: now, recordID: recordID)
        let highResult = adjustHolding(at: highIndex, valueDelta: moved, investedDelta: moved,
                                       current: current, date: now, recordID: recordID)
        let lowName = holdings[lowIndex].name
        let highName = holdings[highIndex].name
        run.add(symbol: holdings[lowIndex].kind.symbol, title: lowName, old: Fmt.euro(lowResult.old), new: Fmt.euro(lowResult.new),
                detail: "\(Fmt.euro(moved)) gaat naar \(highName)",
                sentence: "\(Fmt.euro(moved)) van \(lowName) gaat naar \(highName); \(lowName) gaat van \(Fmt.euro(lowResult.old)) naar \(Fmt.euro(lowResult.new)).")
        run.add(symbol: holdings[highIndex].kind.symbol, title: highName, old: Fmt.euro(highResult.old), new: Fmt.euro(highResult.new),
                detail: "waarde nu",
                sentence: "\(highName) gaat van \(Fmt.euro(highResult.old)) naar \(Fmt.euro(highResult.new)).")
        let returnAfter = weightedNetReturn(current: current)
        run.add(symbol: "chart.line.uptrend.xyaxis", title: "Verwacht rendement beleggingen", old: Fmt.percent(returnBefore, digits: 2),
                new: Fmt.percent(returnAfter, digits: 2), detail: "per jaar na kosten",
                sentence: "Het verwachte rendement van je beleggingen gaat van \(Fmt.percent(returnBefore, digits: 2)) naar \(Fmt.percent(returnAfter, digits: 2)) per jaar.")
        run.notes.append("Dit past alleen de app aan. Een hoger verwacht rendement gaat meestal samen met meer risico. Doe de verschuiving zelf ook bij je broker.")
    }

    // MARK: Doel 10% lager

    fileprivate mutating func applyLowerTarget(goal g: LifeGoal, current: YearMonth, run: inout AcceleratorRun) {
        guard let gi = goals.firstIndex(where: { $0.id == g.id }) else {
            run.message = "Dit doel staat niet in je gegevens."
            return
        }
        let needBefore = goalInputs(for: g, current: current).target
        guard needBefore > 0 else { return }

        let title: String
        let detail: String
        let old: Double
        let new: Double
        let sentence: String
        switch g.kind {
        case .retirement:
            // Het benodigde kapitaal volgt het bedrag dat je netto per maand opneemt: 10% minder daarvan.
            let net = max(0, g.monthlySpending - g.otherMonthlyIncome)
            old = g.monthlySpending
            new = (g.otherMonthlyIncome + net * 0.9).cents
            goals[gi].monthlySpending = new
            title = "Gewenst bedrag per maand"
            detail = "in euro's van vandaag"
            sentence = "Je gewenste pensioen gaat van \(Fmt.euro(old)) naar \(Fmt.euro(new)) per maand."
        case .partTime:
            let gap = monthlyIncomeGap(for: g)
            let net = max(0, gap - g.otherMonthlyIncome)
            old = gap
            new = (g.otherMonthlyIncome + net * 0.9).cents
            goals[gi].monthlyGapOverride = new
            title = "Inkomensverlies per maand"
            detail = "zelf ingevuld bedrag"
            sentence = "Het inkomensverlies van \(g.name) gaat van \(Fmt.euro(old)) naar \(Fmt.euro(new)) per maand."
        case .vacation, .custom:
            old = g.targetAmount
            new = (g.targetAmount * 0.9).cents
            goals[gi].targetAmount = new
            title = "Doelbedrag"
            detail = g.name
            sentence = "Het doelbedrag van \(g.name) gaat van \(Fmt.euro(old)) naar \(Fmt.euro(new))."
        }
        let needAfter = goalInputs(for: goals[gi], current: current).target
        run.add(symbol: "target", title: title, old: Fmt.euro(old), new: Fmt.euro(new), detail: detail, sentence: sentence)
        // Bij een vakantie of eigen doel is het doelbedrag zelf het benodigde bedrag; dan is een tweede regel dubbel.
        if g.kind == .retirement || g.kind == .partTime {
            run.add(symbol: "banknote", title: "Benodigd kapitaal", old: Fmt.euro(needBefore), new: Fmt.euro(needAfter),
                    detail: "om dit vol te houden",
                    sentence: "Het benodigde kapitaal gaat van \(Fmt.euro(needBefore)) naar \(Fmt.euro(needAfter)).")
        }
    }

    // MARK: Herstellen

    /// Wat een toepassing aanpast: per pot, belegging of doel de velden die haar soort versneller wijzigt.
    /// Alleen wat nog bestaat telt mee (een verwijderde pot kan niets meer blokkeren).
    private func touchedSlots(of record: AppliedAccelerator) -> Set<String> {
        let fields = AcceleratorFields(kind: AcceleratorKind(id: record.acceleratorID))
        var slots = Set<String>()
        for old in record.before.pots where pot(old.id) != nil {
            if fields.contains(.contribution) { slots.insert("\(old.id.uuidString)|inleg") }
        }
        for old in record.before.holdings where holding(old.id) != nil {
            if fields.contains(.contribution) { slots.insert("\(old.id.uuidString)|inleg") }
            if fields.contains(.cost) { slots.insert("\(old.id.uuidString)|kosten") }
            if fields.contains(.value) { slots.insert("\(old.id.uuidString)|waarde") }
        }
        for old in record.before.goals where goal(old.id) != nil {
            if fields.contains(.target) { slots.insert("\(old.id.uuidString)|doel") }
            if fields.contains(.funding) { slots.insert("\(old.id.uuidString)|financiering") }
        }
        if record.before.settings != nil { slots.insert("instellingen") }
        if record.before.salary != nil { slots.insert("salaris") }
        return slots
    }

    /// De toepassing die eerst hersteld moet worden voordat `id` kan: een nieuwere die hetzelfde veld van dezelfde
    /// pot, belegging of hetzelfde doel aanpast. Zet je de oudste terug terwijl de nieuwere nog staat, dan verdwijnt ook
    /// het effect van de nieuwere terwijl die als toegepast blijft staan. nil = meteen te herstellen.
    /// Het antwoord is altijd een toepassing die zelf wel meteen te herstellen is.
    func restoreBlocker(for id: UUID) -> AppliedAccelerator? {
        guard var index = appliedAccelerators.firstIndex(where: { $0.id == id }) else { return nil }
        var found: AppliedAccelerator?
        while true {
            let mine = touchedSlots(of: appliedAccelerators[index])
            guard !mine.isEmpty,
                  let next = ((index + 1)..<appliedAccelerators.count).first(where: {
                      !touchedSlots(of: appliedAccelerators[$0]).isDisjoint(with: mine)
                  }) else { return found }
            found = appliedAccelerators[next]
            index = next
        }
    }

    /// Zet alles terug zoals het was vóór deze toepassing en verwijdert het record. Alleen wat de versneller aanpaste
    /// gaat terug; wat je daarna in andere dingen veranderde blijft. Heb je zelf ditzelfde veld daarna nog aangepast
    /// (bijvoorbeeld de inleg van dezelfde pot), dan gaat dat veld ook terug: "herstel" betekent terug naar vóór de
    /// versneller. Wat niet meer bestaat (een verwijderde pot of belegging) wordt overgeslagen.
    ///
    /// Geeft false als het record niet (meer) bestaat, of als een nieuwere toepassing hetzelfde aanpast en eerst
    /// hersteld moet worden (zie `restoreBlocker(for:)`). Met `ignoringOrder` herstelt hij toch; de nieuwere toepassing
    /// verliest dan haar effect op die velden en blijft wel als toegepast staan. Alleen voor wie weet wat hij doet.
    @discardableResult
    mutating func restoreAccelerator(_ id: UUID, ignoringOrder: Bool = false) -> Bool {
        guard let index = appliedAccelerators.firstIndex(where: { $0.id == id }) else { return false }
        if !ignoringOrder, restoreBlocker(for: id) != nil { return false }
        let record = appliedAccelerators[index]
        let revert = restoreData(of: record)
        // Latere toepassingen die dezelfde dingen aanpasten, moeten bij hun herstel niet terug naar de toestand
        // van vóór deze toepassing: pas hun bewaarde oude toestand aan.
        var next = index + 1
        while next < appliedAccelerators.count {
            Self.rebase(&appliedAccelerators[next].before, onto: record, revert: revert)
            next += 1
        }
        appliedAccelerators.remove(at: index)
        return true
    }

    /// Herstelt alle toegepaste versnellers, de nieuwste eerst.
    mutating func restoreAllAccelerators() {
        for record in appliedAccelerators.reversed() {
            restoreAccelerator(record.id, ignoringOrder: true)
        }
        appliedAccelerators.removeAll()
    }

    /// Herstelt de toepassingen van één doel, de nieuwste eerst. Een toepassing die door een nieuwere van een ander doel
    /// geblokkeerd wordt (dezelfde pot of belegging) blijft staan. Geeft het aantal herstelde toepassingen.
    @discardableResult
    mutating func restoreAccelerators(for goalID: UUID) -> Int {
        var restored = 0
        while let record = appliedAccelerators.last(where: { $0.goalID == goalID && restoreBlocker(for: $0.id) == nil }) {
            guard restoreAccelerator(record.id) else { break }
            restored += 1
        }
        return restored
    }

    /// Hoeveel toepassingen "alles herstellen" nu terugzet: van één doel, of van alle doelen (nil).
    func restorableAcceleratorCount(for goalID: UUID?) -> Int {
        guard let goalID else { return appliedAccelerators.count }
        var copy = self
        return copy.restoreAccelerators(for: goalID)
    }

    /// De vaste maandinleg van een pot of belegging.
    private func contribution(ofEntity id: UUID) -> Double? {
        pot(id)?.monthlyContribution ?? holding(id)?.monthlyContribution
    }

    private mutating func restoreData(of record: AppliedAccelerator) -> AcceleratorRevert? {
        let fields = AcceleratorFields(kind: AcceleratorKind(id: record.acceleratorID))
        let backup = record.before
        // De inleg zoals hij nu is: maanden die daarna zijn ontstaan hebben die als eigen waarde.
        var contributionBefore: [String: Double] = [:]
        for old in backup.pots {
            if let value = contribution(ofEntity: old.id) { contributionBefore[old.id.uuidString] = value }
        }
        for old in backup.holdings {
            if let value = contribution(ofEntity: old.id) { contributionBefore[old.id.uuidString] = value }
        }

        for old in backup.pots {
            if let i = pots.firstIndex(where: { $0.id == old.id }) { pots[i].restoreAcceleratorFields(fields, from: old) }
        }
        for old in backup.holdings {
            if let i = holdings.firstIndex(where: { $0.id == old.id }) {
                holdings[i].restoreAcceleratorFields(fields, from: old,
                                                     removingSnapshot: AcceleratorIDs.snapshot(record.id, holding: old.id))
            }
        }
        for old in backup.goals {
            if let i = goals.firstIndex(where: { $0.id == old.id }) { goals[i].restoreAcceleratorFields(fields, from: old) }
        }
        if let oldSettings = backup.settings { settings = oldSettings }
        if let oldSalary = backup.salary { salary = oldSalary }
        let revert = restorePlans(of: record, fields: fields, contributionBefore: contributionBefore)

        let ids = AcceleratorIDs.entries(of: record.id)
        bankEntries.removeAll { ids.contains($0.id) }
        potEntries.removeAll { ids.contains($0.id) }
        return revert
    }

    /// Sleutels van de maandplannen die een toepassing raakte, oplopend op maand.
    private static func touchedKeys(of backup: AcceleratorBackup) -> [String] {
        (Array(backup.plans.keys) + backup.newPlanKeys).compactMap { YearMonth(key: $0) }.sorted().map(\.key)
    }

    /// Per maand de regel die de versneller aanpaste (uitgave) of toevoegde (inkomsten).
    private static func chains(of record: AppliedAccelerator, plans: [String: MonthPlan])
        -> (expense: [String: UUID], income: [String: UUID]) {
        switch AcceleratorKind(id: record.acceleratorID) {
        case .expense(let lineID):
            return (AcceleratorMath.lineIDs(plans: plans, first: lineID, lines: \.expenses), [:])
        case .hours:
            return ([:], AcceleratorMath.lineIDs(plans: plans, first: AcceleratorIDs.entry(record.id, "hours"),
                                                 lines: \.extraIncome))
        default:
            return ([:], [:])
        }
    }

    private mutating func restorePlans(of record: AppliedAccelerator, fields: AcceleratorFields,
                                       contributionBefore: [String: Double]) -> AcceleratorRevert? {
        guard fields.contains(.plans) else { return nil }
        let keys = Self.touchedKeys(of: record.before)
        // Alleen verdelingen van potten en beleggingen die er nog zijn (een verwijderde pot krijgt geen verdeling terug).
        let allocationIDs = Set(record.before.pots.map(\.id).filter { pot($0) != nil }.map(\.uuidString)
                                + record.before.holdings.map(\.id).filter { holding($0) != nil }.map(\.uuidString))
        let lineChains = Self.chains(of: record, plans: months)

        var revert = AcceleratorRevert(applyMonth: YearMonth(date: record.date), recordedKeys: Set(keys),
                                       allocation: [:], expenseAmount: nil)
        for idString in allocationIDs {
            if let id = UUID(uuidString: idString), let before = contributionBefore[idString],
               let after = contribution(ofEntity: id), before != after {
                revert.allocation[idString] = (before, after)
            }
        }

        for key in keys {
            guard var current = months[key], let month = YearMonth(key: key) else { continue }
            let stored = record.before.plans[key]
            // Een maand die er eerst niet was, ging terug naar het afgeleide plan; staat er daarna niets anders in, dan verdwijnt hij.
            let base = stored ?? synthesizedPlan(for: month)
            if revert.expenseAmount == nil, let lineID = lineChains.expense[key],
               let i = current.expenses.firstIndex(where: { $0.id == lineID }),
               let j = base.expenses.firstIndex(where: { $0.id == lineID }) {
                revert.expenseAmount = (current.expenses[i].amount, base.expenses[j].amount)
            }
            AcceleratorMath.restoreSlots(in: &current, from: base, allocationIDs: allocationIDs,
                                         expenseLineID: lineChains.expense[key], incomeLineID: lineChains.income[key])
            if stored == nil, current == synthesizedPlan(for: month) {
                months.removeValue(forKey: key)
            } else {
                months[key] = current
            }
        }
        // Maanden die daarna zijn ontstaan (bijvoorbeeld bij het begin van een nieuwe maand) hebben de nieuwe waarden overgenomen.
        AcceleratorMath.revertDerived(in: &months, revert: revert, expenseLines: lineChains.expense,
                                      incomeLines: lineChains.income, allocationPre: [:])
        return revert
    }

    /// Past de bewaarde oude toestand van een latere toepassing aan, nu `record` is hersteld.
    private static func rebase(_ later: inout AcceleratorBackup, onto record: AppliedAccelerator, revert: AcceleratorRevert?) {
        let fields = AcceleratorFields(kind: AcceleratorKind(id: record.acceleratorID))
        let backup = record.before
        var contributionBefore: [String: Double] = [:]
        for pot in later.pots { contributionBefore[pot.id.uuidString] = pot.monthlyContribution }
        for holding in later.holdings { contributionBefore[holding.id.uuidString] = holding.monthlyContribution }

        for old in backup.pots {
            if let i = later.pots.firstIndex(where: { $0.id == old.id }) { later.pots[i].restoreAcceleratorFields(fields, from: old) }
        }
        for old in backup.holdings {
            if let i = later.holdings.firstIndex(where: { $0.id == old.id }) {
                later.holdings[i].restoreAcceleratorFields(fields, from: old,
                                                           removingSnapshot: AcceleratorIDs.snapshot(record.id, holding: old.id))
            }
        }
        for old in backup.goals {
            if let i = later.goals.firstIndex(where: { $0.id == old.id }) { later.goals[i].restoreAcceleratorFields(fields, from: old) }
        }
        if let oldSettings = backup.settings, later.settings != nil { later.settings = oldSettings }
        if let oldSalary = backup.salary, later.salary != nil { later.salary = oldSalary }

        guard fields.contains(.plans) else { return }
        let allocationIDs = Set(backup.pots.map { $0.id.uuidString } + backup.holdings.map { $0.id.uuidString })
        let lineChains = chains(of: record, plans: later.plans)
        for key in later.plans.keys.compactMap({ YearMonth(key: $0) }).sorted().map(\.key) {
            if backup.newPlanKeys.contains(key) {
                // Na herstellen bestond deze maand eerst niet: voor de latere toepassing is hij dan ook nieuw.
                later.plans.removeValue(forKey: key)
                if !later.newPlanKeys.contains(key) { later.newPlanKeys.append(key) }
            } else if let base = backup.plans[key], var plan = later.plans[key] {
                AcceleratorMath.restoreSlots(in: &plan, from: base, allocationIDs: allocationIDs,
                                             expenseLineID: lineChains.expense[key], incomeLineID: lineChains.income[key])
                later.plans[key] = plan
            }
        }
        if let revert {
            AcceleratorMath.revertDerived(in: &later.plans, revert: revert, expenseLines: lineChains.expense,
                                          incomeLines: lineChains.income, allocationPre: contributionBefore)
        }
        later.newPlanKeys.sort()
    }
}
