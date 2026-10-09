import Foundation

/// Wat voor soort regel het is in de geschiedenis van een spaarpot.
enum PotTimelineKind: String, Codable {
    /// Maandverdeling (overgeschreven op de overschrijfdatum).
    case allocation
    /// Handmatige boeking: storting, opname, overboeking, saldo-aanpassing.
    case manual
    /// Rente (opgeslagen of verwacht).
    case interest
    /// Een uitgave die (deels) uit deze pot betaald wordt. Het bedrag is negatief.
    case expense
}

/// Eén regel in de geschiedenis van een spaarpot.
struct PotTimelineItem: Identifiable, Equatable {
    var id: String
    var date: Date
    var title: String
    var note: String
    var amount: Double
    /// true = maandelijkse verdeling, false = handmatige boeking.
    var isMonthlyAllocation: Bool
    var kind: PotTimelineKind = .manual
    /// Ligt op een dag na de dag van `asOf` van `potTimeline`: nog niet gebeurd, dus nog niet in het saldo van nu.
    var isPlanned: Bool = false
}

/// Boekingen op datum met lopende som in hele centen, om snel een saldo op een moment te vinden.
struct CentsLedger: Equatable {
    private(set) var dates: [Date] = []
    private(set) var prefix: [Int] = [0]

    init(items: [(date: Date, cents: Int)] = []) {
        let sorted = items.sorted { $0.date < $1.date }
        dates = sorted.map { $0.date }
        var running = 0
        var sums = [0]
        sums.reserveCapacity(sorted.count + 1)
        for item in sorted {
            running = CentsMath.add(running, item.cents)
            sums.append(running)
        }
        prefix = sums
    }

    /// Aantal boekingen met een datum vóór `limit`.
    func countBefore(_ limit: Date) -> Int {
        var lo = 0
        var hi = dates.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if dates[mid] < limit { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Aantal boekingen met een datum op of vóór `date`.
    func countUpTo(_ date: Date) -> Int {
        var lo = 0
        var hi = dates.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if dates[mid] <= date { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Som van alle boekingen vóór `limit`.
    func sum(before limit: Date) -> Int {
        prefix[countBefore(limit)]
    }

    /// Som van de boekingen na `base` (exclusief) en vóór `limit`.
    func sum(after base: Date, before limit: Date) -> Int {
        let hi = countBefore(limit)
        let lo = min(countUpTo(base), hi)
        return prefix[hi] - prefix[lo]
    }
}

extension FinanceData {
    func pot(_ id: UUID) -> Pot? { pots.first { $0.id == id } }

    // MARK: Saldo

    /// Alle boekingen van een pot tot en met `last`, in twee lijsten op datum: de handmatige boekingen (eigen
    /// tijdstip) en wat uit het plan komt: de maandverdelingen op hun overschrijfdatum en de potdelen van uitgaven op
    /// hun uitgavedatum (negatief). Planboekingen tellen per kalenderdag, zie `PotFlows`.
    /// `managed` zijn de id's van opgeslagen rente-uitbetalingen; die tellen apart mee (zie `potFlows`).
    func potLedger(for pot: Pot, throughMonth last: YearMonth, excluding managed: Set<UUID> = []) -> PotLedgers {
        potLedgers(for: [pot], throughMonth: last, excluding: [pot.id: managed])[pot.id]
            ?? PotLedgers(entries: CentsLedger(), plan: CentsLedger())
    }

    /// Zoals `potLedger(for:throughMonth:excluding:)`, voor meer potten in één keer: de maanden en uitgaven worden één
    /// keer doorlopen in plaats van één keer per pot. `managed` per pot (op pot-id) zijn de uitbetalingen die apart meetellen.
    func potLedgers(for targets: [Pot], throughMonth last: YearMonth,
                    excluding managed: [UUID: Set<UUID>] = [:]) -> [UUID: PotLedgers] {
        var entryItems: [UUID: [(date: Date, cents: Int)]] = [:]
        var planItems: [UUID: [(date: Date, cents: Int)]] = [:]
        var wanted = Set<UUID>()
        for pot in targets { wanted.insert(pot.id) }
        for e in potEntries where wanted.contains(e.potID) {
            if managed[e.potID]?.contains(e.id) == true { continue }
            entryItems[e.potID, default: []].append((e.date, CentsMath.int(e.amount)))
        }

        // Zelfde regels als `allocation(_:in:)` en `transferDay(for:in:)`, maar zonder elke maand alles opnieuw op te zoeken.
        let potKeys = targets.map { $0.id.uuidString }
        let anyShares = months.values.contains { plan in plan.expenses.contains { !$0.potShares.isEmpty } }
        let stored = StoredPlans(anyShares ? months : [:])
        let cal = YearMonth.calendar
        var m = startMonth
        var count = 0
        while m <= last && count < 2_400 {
            let storedPlan = months[m.key]
            for (i, pot) in targets.enumerated() {
                let planned = storedPlan?.allocations[potKeys[i]] ?? (m >= pot.startMonth ? pot.monthlyContribution : 0)
                let cents = CentsMath.int(planned)
                if cents != 0 {
                    let day = min(YearMonth.clampedDay(storedPlan?.transferDay ?? pot.transferDay ?? salary.payDay), m.dayCount)
                    planItems[pot.id, default: []].append((m.date(day: day, calendar: cal), cents))
                }
            }
            if anyShares {
                // Een nog niet vastgelegde maand krijgt de terugkerende uitgaven van het laatst opgeslagen plan.
                let lines = storedPlan?.expenses ?? (stored.latest(before: m)?.expenses.filter { $0.isRecurring } ?? [])
                for line in lines where !line.potShares.isEmpty {
                    var date: Date?
                    for payment in expenseSplit(of: line).pots where wanted.contains(payment.potID) {
                        if date == nil { date = m.date(day: expenseDay(of: line), calendar: cal) }
                        planItems[payment.potID, default: []].append((date ?? m.firstDay, -payment.cents))
                    }
                }
            }
            m = m.adding(1)
            count += 1
        }
        var result: [UUID: PotLedgers] = [:]
        for pot in targets {
            result[pot.id] = PotLedgers(entries: CentsLedger(items: entryItems[pot.id] ?? []),
                                        plan: CentsLedger(items: planItems[pot.id] ?? []))
        }
        return result
    }

    /// Saldo aan het EIND van `date`. Inleg telt vanaf de overschrijfdatum, uitgaven uit de pot vanaf de
    /// uitgavedatum en rente vanaf de uitbetaaldatum (ook de verwachte rente die nog niet is opgeslagen).
    /// Gebeurtenissen van die dag tellen helemaal mee, ook die later op de dag. Voor "wat staat er nu" is
    /// `potBalanceNow` (of `potBalance(_:atMoment:)`) bedoeld.
    func potBalance(_ potID: UUID, asOf date: Date) -> Double {
        guard let pot = self.pot(potID) else { return 0 }
        let flows = potFlows(pot, throughMonth: YearMonth(date: date))
        return CentsMath.value(flows.cents(before: DayMath.nextDayStart(after: date)))
    }

    /// Saldo van het moment `moment` ("nu"). Alles gebeurt per KALENDERDAG: inleg, uitgaven uit de pot en rente tellen
    /// mee zodra hun dag op of voor de dag van `moment` ligt, de hele dag dus, ook voor 12:00 (precies het omgekeerde
    /// van `DayEvent.isPlanned`: gepland is wat op een latere dag valt). Handmatige boekingen houden hun eigen
    /// tijdstip (tot en met `moment`).
    func potBalance(_ potID: UUID, atMoment moment: Date) -> Double {
        guard let pot = self.pot(potID) else { return 0 }
        let flows = potFlows(pot, throughMonth: YearMonth(date: moment))
        return CentsMath.value(flows.cents(entriesBefore: DayMath.limit(including: moment),
                                           planBefore: DayMath.planLimit(for: moment)))
    }

    /// Saldo aan het EIND van `month`. Toekomstige maanden tellen de geplande verdeling en verwachte rente mee,
    /// en ook in de lopende maand telt wat nog moet komen (de inleg van de 25e) al mee. Dit is dus NIET het saldo
    /// van vandaag: toon je "nu", gebruik dan `potBalanceNow`. Voor grafieken en prognoses is dit de juiste.
    func potBalance(_ potID: UUID, at month: YearMonth) -> Double {
        potBalance(potID, asOf: month.date(day: month.dayCount))
    }

    /// Saldo van nu: op de dag van `today` als die in `current` valt (wat op een latere dag komt, zoals de inleg van
    /// de 25e, telt niet mee; wat vandaag valt de hele dag wel), anders het saldo aan het eind van `current`.
    func potBalanceNow(_ potID: UUID, current: YearMonth, today: Date = Date()) -> Double {
        if YearMonth(date: today) == current { return potBalance(potID, atMoment: today) }
        return potBalance(potID, at: current)
    }

    /// Totaal van alle spaarpotten nu (zoals `potBalanceNow`).
    func totalSaved(current: YearMonth, today: Date = Date()) -> Double {
        CentsMath.value(CentsMath.sum(pots.map { CentsMath.int(potBalanceNow($0.id, current: current, today: today)) }))
    }

    /// Totaal van alle spaarpotten aan het eind van `date`.
    func totalSaved(asOf date: Date) -> Double {
        CentsMath.value(CentsMath.sum(pots.map { CentsMath.int(potBalance($0.id, asOf: date)) }))
    }

    /// Som van alle doelbedragen van spaarpotten die een doel hebben.
    func totalGoal() -> Double {
        pots.compactMap { $0.goalAmount }.filter { $0 > 0 }.reduce(0, +).cents
    }

    /// Wat er gespaard is in de potten die een doel hebben (om te vergelijken met `totalGoal`).
    /// Zonder `today` het saldo aan het eind van `current`; met `today` het saldo van nu (zoals `potBalanceNow`).
    func savedTowardGoals(current: YearMonth, today: Date? = nil) -> Double {
        CentsMath.value(CentsMath.sum(pots.filter { ($0.goalAmount ?? 0) > 0 }
            .map { CentsMath.int(progressBalance($0.id, current: current, today: today)) }))
    }

    /// 0...1 (kan boven 1 uitkomen als je het doel hebt gehaald); nil zonder doel.
    /// Zonder `today` het saldo aan het eind van `current`; met `today` het saldo van nu. Geef dezelfde `today`
    /// mee als aan `potBalanceNow`, anders toont de balk een ander saldo dan de tekst.
    func potProgress(_ potID: UUID, current: YearMonth, today: Date? = nil) -> Double? {
        guard let pot = self.pot(potID), let goal = pot.goalAmount, goal > 0 else { return nil }
        return max(0, progressBalance(potID, current: current, today: today) / goal)
    }

    /// Eind van `current` zonder `today`, anders het saldo van nu.
    private func progressBalance(_ potID: UUID, current: YearMonth, today: Date?) -> Double {
        guard let today else { return potBalance(potID, at: current) }
        return potBalanceNow(potID, current: current, today: today)
    }

    /// Maand waarin het doel gehaald wordt bij de huidige inleg (met verwachte rente). nil = geen doel of wordt niet gehaald.
    func potGoalMonth(_ potID: UUID, current: YearMonth) -> YearMonth? {
        guard let pot = self.pot(potID), let goal = pot.goalAmount, goal > 0 else { return nil }
        let balance = potBalance(potID, at: current)
        if balance >= goal { return current }
        // Kijk vooruit met de geplande verdeling per maand (maximaal 50 jaar).
        let flows = potFlows(pot, throughMonth: current.adding(600))
        for step in 1...600 {
            let m = current.adding(step)
            if CentsMath.value(flows.cents(before: m.endExclusive)) >= goal { return m }
        }
        return nil
    }

    // MARK: Geschiedenis

    /// Alles wat het saldo van een pot veranderde of verandert t/m `current`, nieuwste eerst:
    /// handmatige boekingen, rente (opgeslagen en verwacht), maandverdelingen op hun overschrijfdatum
    /// en uitgaven die uit de pot betaald worden (negatief).
    ///
    /// Regels op een dag na de dag van `today` zijn `isPlanned` (per kalenderdag, zoals `DayEvent.isPlanned`): de som
    /// van de regels die dat niet zijn is het saldo van nu (`potBalanceNow`), de som van alle regels het saldo aan
    /// het eind van `current` (`potBalance(_:at:)`).
    func potTimeline(_ potID: UUID, current: YearMonth, asOf today: Date = Date()) -> [PotTimelineItem] {
        guard let pot = self.pot(potID) else { return [] }
        var items: [PotTimelineItem] = []

        for e in potEntries where e.potID == potID {
            let kind: PotTimelineKind
            switch e.kind {
            case .interest: kind = .interest
            case .expense: kind = .expense
            default: kind = .manual
            }
            var id = e.id.uuidString
            // Een opgeslagen uitbetaling houdt dezelfde id als de verwachte, zodat de lijst niet verspringt.
            if e.kind == .interest {
                let month = YearMonth(date: e.date)
                if e.id == InterestRules.entryID(for: potID, month: month) { id = InterestRules.paymentID(for: potID, month: month) }
            }
            items.append(PotTimelineItem(id: id, date: e.date, title: e.kind.title, note: e.note,
                                         amount: e.amount, isMonthlyAllocation: false, kind: kind))
        }

        let flows = potFlows(pot, throughMonth: current)
        for payment in flows.payments where payment.isProjected && payment.date < current.endExclusive {
            items.append(PotTimelineItem(id: payment.id, date: payment.date, title: PotEntryKind.interest.title,
                                         note: "Verwacht", amount: payment.amount, isMonthlyAllocation: false, kind: .interest))
        }

        let cal = YearMonth.calendar
        let stored = StoredPlans(months)
        var m = startMonth
        var count = 0
        while m <= current && count < 2_400 {
            let a = allocation(potID, in: m)
            if CentsMath.int(a) != 0 {
                items.append(PotTimelineItem(id: "alloc-\(m.key)",
                                             date: m.date(day: transferDay(for: potID, in: m), calendar: cal),
                                             title: "Maandverdeling \(Fmt.month(m))", note: "",
                                             amount: CentsMath.value(CentsMath.int(a)), isMonthlyAllocation: true, kind: .allocation))
            }
            for line in plan(for: m, using: stored).expenses where !line.potShares.isEmpty {
                for payment in expenseSplit(of: line).pots where payment.potID == potID {
                    items.append(PotTimelineItem(id: "expense-\(line.id.uuidString)-\(payment.shareID.uuidString)-\(m.key)",
                                                 date: m.date(day: expenseDay(of: line), calendar: cal),
                                                 title: line.name.isEmpty ? "Uitgave" : line.name,
                                                 note: PotEntryKind.expense.title,
                                                 amount: -CentsMath.value(payment.cents), isMonthlyAllocation: false, kind: .expense))
                }
            }
            m = m.adding(1)
            count += 1
        }
        let planLimit = DayMath.planLimit(for: today, calendar: cal)
        for i in items.indices { items[i].isPlanned = items[i].date >= planLimit }
        return items.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id < rhs.id
        }
    }

    // MARK: Wijzigen

    mutating func addPot(_ pot: Pot, openingBalance: Double = 0, now: Date = Date()) {
        pots.append(pot)
        if openingBalance != 0 {
            potEntries.append(PotEntry(potID: pot.id, date: now, amount: openingBalance.cents, kind: .opening, note: ""))
        }
    }

    mutating func updatePot(_ updated: Pot, current: YearMonth) {
        guard let i = pots.firstIndex(where: { $0.id == updated.id }) else { return }
        let old = pots[i]
        pots[i] = updated
        // Een nieuwe standaardinleg geldt ook meteen voor de lopende maand.
        if old.monthlyContribution != updated.monthlyContribution, current >= updated.startMonth {
            setAllocation(updated.id, in: current, amount: updated.monthlyContribution)
        }
    }

    /// Verwijdert een spaarpot. Met `returningBalanceToBank` boekt hij eerst het saldo van nu naar de bankrekening
    /// (`transferPotToBank`, op het moment `today`); een leeg of negatief saldo geeft geen boeking. Zonder dat is het
    /// gewoon `deletePot(_:)`: het geld in de pot verdwijnt dan uit het overzicht.
    ///
    /// Met een pot verdwijnen ook zijn geplande overboekingen uit het bankverloop. Ligt een deel daarvan al achter
    /// ons maar na het laatste ingevulde banksaldo (de inleg van de 25e), dan zou de bank dat geld dubbel krijgen: één
    /// keer doordat die overboeking verdwijnt en nog eens in het teruggeboekte saldo. Dat verschil boekt deze functie
    /// daarom als tweede, losse bankboeking terug. Bank en potten samen veranderen dus alleen door het verwijderen
    /// zelf niet. De boekingen staan los (zonder `pairID` of pot): hun potkant verdwijnt met de pot.
    mutating func deletePot(_ id: UUID, returningBalanceToBank: Bool, current: YearMonth = YearMonth.current(),
                            today: Date = Date()) {
        guard returningBalanceToBank, let removed = pot(id) else {
            deletePot(id)
            return
        }
        let balance = potBalanceNow(id, current: current, today: today)
        // Wat de bank door het verdwijnen van de pot er in het saldo van nu bij of af krijgt.
        var without = self
        without.deletePot(id)
        let shift = CentsMath.int(without.bankBalanceNow(current: current, today: today))
            - CentsMath.int(bankBalanceNow(current: current, today: today))

        let countBefore = bankEntries.count
        transferPotToBank(potID: id, amount: balance, date: today)
        if shift != 0 {
            let name = removed.name.isEmpty ? "spaarpot" : removed.name
            bankEntries.append(BankEntry(date: today, amount: CentsMath.value(-shift), kind: shift > 0 ? .toPot : .fromPot,
                                         note: shift > 0 ? "Eerder overgemaakt naar \(name)" : "Eerder betaald uit \(name)"))
        }
        let created = Set(bankEntries.dropFirst(countBefore).map { $0.id })
        deletePot(id)
        for i in bankEntries.indices where created.contains(bankEntries[i].id) {
            bankEntries[i].pairID = nil
            bankEntries[i].potID = nil
        }
    }

    mutating func deletePot(_ id: UUID) {
        pots.removeAll { $0.id == id }
        potEntries.removeAll { $0.potID == id }
        for key in Array(months.keys) {
            months[key]?.allocations.removeValue(forKey: id.uuidString)
            // Uitgaven die deels uit deze pot kwamen: de bank betaalt dat deel dan zelf.
            if let plan = months[key], plan.expenses.contains(where: { $0.potShares.contains { $0.potID == id } }) {
                months[key]?.expenses = plan.expenses.map { line in
                    var copy = line
                    copy.potShares.removeAll { $0.potID == id }
                    return copy
                }
            }
        }
        homePotIDs = homePotIDs?.filter { $0 != id }
        for i in goals.indices {
            if case .pot(let potID) = goals[i].funding, potID == id { goals[i].funding = .portfolio }
        }
    }

    mutating func addPotEntry(potID: UUID, amount: Double, kind: PotEntryKind, note: String = "", date: Date = Date()) {
        guard pot(potID) != nil, amount != 0 else { return }
        potEntries.append(PotEntry(potID: potID, date: date, amount: amount.cents, kind: kind, note: note))
    }

    /// Verwijdert een boeking. Hoort ze bij een overboeking (`pairID`), dan verdwijnt de andere helft ook (de
    /// bankboeking, of de boeking in de andere pot): zo ontstaat er geen geld uit het niets. Boekingen zonder
    /// `pairID` (van vóór deze regel) blijven los verwijderbaar.
    mutating func deletePotEntry(_ id: UUID) {
        let pair = potEntries.first { $0.id == id }?.pairID
        potEntries.removeAll { $0.id == id || (pair != nil && $0.pairID == pair) }
        if let pair { bankEntries.removeAll { $0.pairID == pair } }
    }

    /// Zet het saldo op een nieuw bedrag via een correctieboeking.
    /// Standaard wordt vergeleken met het saldo aan het eind van `current`. Toon je het saldo van nu
    /// (`potBalanceNow`), geef dan `asOf` mee (het moment van nu, bijvoorbeeld `store.today`): het verschil wordt
    /// dan gemeten op dat moment, dus precies tegen het getal dat de gebruiker zag.
    mutating func setPotBalance(_ potID: UUID, to newBalance: Double, current: YearMonth, note: String = "",
                                date: Date = Date(), asOf: Date? = nil) {
        let reference = asOf.map { potBalance(potID, atMoment: $0) } ?? potBalance(potID, at: current)
        let diff = CentsMath.value(CentsMath.int(newBalance) - CentsMath.int(reference))
        guard diff != 0 else { return }
        addPotEntry(potID: potID, amount: diff, kind: .adjustment, note: note, date: date)
    }

    /// Boekt geld van de ene spaarpot naar de andere. Beide helften delen een `pairID`.
    mutating func transfer(from: UUID, to: UUID, amount: Double, note: String = "", date: Date = Date()) {
        guard from != to, amount > 0, let source = pot(from), let target = pot(to) else { return }
        let pair = UUID()
        potEntries.append(PotEntry(potID: from, date: date, amount: -amount.cents, kind: .transferOut,
                                   note: note.isEmpty ? "Naar \(target.name)" : note, pairID: pair))
        potEntries.append(PotEntry(potID: to, date: date, amount: amount.cents, kind: .transferIn,
                                   note: note.isEmpty ? "Van \(source.name)" : note, pairID: pair))
    }

    // MARK: Home-keuze

    /// De spaarpotten die op Home staan (maximaal 3).
    func homePots() -> [Pot] {
        if let ids = homePotIDs {
            return ids.compactMap { id in pots.first { $0.id == id } }.prefix(3).map { $0 }
        }
        return Array(pots.prefix(3))
    }
}
