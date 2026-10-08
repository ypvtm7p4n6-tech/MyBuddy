import Foundation

/// Eén regel in de geschiedenis van een spaarpot.
struct PotTimelineItem: Identifiable, Equatable {
    var id: String
    var date: Date
    var title: String
    var note: String
    var amount: Double
    /// true = maandelijkse verdeling, false = handmatige boeking.
    var isMonthlyAllocation: Bool
}

extension FinanceData {
    func pot(_ id: UUID) -> Pot? { pots.first { $0.id == id } }

    /// Saldo aan het eind van `month`. Toekomstige maanden tellen de geplande verdeling mee.
    func potBalance(_ potID: UUID, at month: YearMonth) -> Double {
        guard let pot = self.pot(potID) else { return 0 }
        let limit = month.endExclusive
        var total = potEntries.reduce(0.0) { sum, e in
            e.potID == potID && e.date < limit ? sum + e.amount : sum
        }
        var m = pot.startMonth
        while m <= month {
            total += allocation(potID, in: m)
            m = m.adding(1)
        }
        return total.cents
    }

    func potBalanceNow(_ potID: UUID, current: YearMonth) -> Double {
        potBalance(potID, at: current)
    }

    func totalSaved(current: YearMonth) -> Double {
        pots.reduce(0) { $0 + potBalance($1.id, at: current) }.cents
    }

    /// Som van alle doelbedragen van spaarpotten die een doel hebben.
    func totalGoal() -> Double {
        pots.compactMap { $0.goalAmount }.filter { $0 > 0 }.reduce(0, +).cents
    }

    /// Wat er nu gespaard is in de potten die een doel hebben (om te vergelijken met `totalGoal`).
    func savedTowardGoals(current: YearMonth) -> Double {
        pots.filter { ($0.goalAmount ?? 0) > 0 }
            .reduce(0) { $0 + potBalance($1.id, at: current) }.cents
    }

    /// 0...1 (kan boven 1 uitkomen als je het doel hebt gehaald); nil zonder doel.
    func potProgress(_ potID: UUID, current: YearMonth) -> Double? {
        guard let pot = self.pot(potID), let goal = pot.goalAmount, goal > 0 else { return nil }
        return max(0, potBalance(potID, at: current) / goal)
    }

    /// Maand waarin het doel gehaald wordt bij de huidige inleg. nil = geen doel of wordt niet gehaald.
    func potGoalMonth(_ potID: UUID, current: YearMonth) -> YearMonth? {
        guard let pot = self.pot(potID), let goal = pot.goalAmount, goal > 0 else { return nil }
        let balance = potBalance(potID, at: current)
        if balance >= goal { return current }
        // Kijk vooruit met de geplande verdeling per maand (maximaal 50 jaar).
        var running = balance
        var m = current
        for _ in 0..<600 {
            m = m.adding(1)
            running += allocation(potID, in: m)
            if running >= goal { return m }
        }
        return nil
    }

    // MARK: Geschiedenis

    func potTimeline(_ potID: UUID, current: YearMonth) -> [PotTimelineItem] {
        guard let pot = self.pot(potID) else { return [] }
        var items: [PotTimelineItem] = potEntries.filter { $0.potID == potID }.map { e in
            PotTimelineItem(id: e.id.uuidString, date: e.date, title: e.kind.title, note: e.note,
                            amount: e.amount, isMonthlyAllocation: false)
        }
        var m = pot.startMonth
        while m <= current {
            let a = allocation(potID, in: m)
            if a != 0 {
                items.append(PotTimelineItem(id: "alloc-\(m.key)", date: m.firstDay,
                                             title: "Maandverdeling \(Fmt.month(m))", note: "",
                                             amount: a, isMonthlyAllocation: true))
            }
            m = m.adding(1)
        }
        return items.sorted { $0.date > $1.date }
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

    mutating func deletePot(_ id: UUID) {
        pots.removeAll { $0.id == id }
        potEntries.removeAll { $0.potID == id }
        for key in Array(months.keys) {
            months[key]?.allocations.removeValue(forKey: id.uuidString)
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

    mutating func deletePotEntry(_ id: UUID) {
        potEntries.removeAll { $0.id == id }
    }

    /// Zet het saldo op een nieuw bedrag via een correctieboeking.
    mutating func setPotBalance(_ potID: UUID, to newBalance: Double, current: YearMonth, note: String = "", date: Date = Date()) {
        let diff = (newBalance - potBalance(potID, at: current)).cents
        guard diff != 0 else { return }
        addPotEntry(potID: potID, amount: diff, kind: .adjustment, note: note, date: date)
    }

    mutating func transfer(from: UUID, to: UUID, amount: Double, note: String = "", date: Date = Date()) {
        guard from != to, amount > 0, let source = pot(from), let target = pot(to) else { return }
        potEntries.append(PotEntry(potID: from, date: date, amount: -amount.cents, kind: .transferOut,
                                   note: note.isEmpty ? "Naar \(target.name)" : note))
        potEntries.append(PotEntry(potID: to, date: date, amount: amount.cents, kind: .transferIn,
                                   note: note.isEmpty ? "Van \(source.name)" : note))
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
