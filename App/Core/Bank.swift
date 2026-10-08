import Foundation

/// Verwacht bankverloop per maand.
struct BankPoint: Identifiable, Equatable {
    var month: YearMonth
    var balance: Double
    var isProjected: Bool
    var id: String { month.key }
}

extension FinanceData {
    var sortedBankSnapshots: [BankSnapshot] {
        bankSnapshots.sorted { $0.date < $1.date }
    }

    var hasBankBalance: Bool { !bankSnapshots.isEmpty || !bankEntries.isEmpty }

    /// Het meetpunt waar het saldo van uitgaat. Zonder ingevuld saldo maar met een eerste storting
    /// begint de rekening op nul vlak vóór die storting.
    private func bankBase(before limit: Date) -> BankSnapshot? {
        if let snap = sortedBankSnapshots.last(where: { $0.date < limit }) { return snap }
        if bankSnapshots.isEmpty, let first = bankEntries.map(\.date).min(), first < limit {
            return BankSnapshot(date: first.addingTimeInterval(-1), balance: 0, note: "")
        }
        return nil
    }

    /// Saldo aan het eind van `month`: laatste ingevulde saldo, plus stortingen en opnames daarna,
    /// plus het overschot van latere maanden. nil als er voor die maand nog geen saldo bekend is.
    func bankBalance(at month: YearMonth) -> Double? {
        let limit = month.endExclusive
        guard let snap = bankBase(before: limit) else { return nil }
        let snapMonth = YearMonth(date: snap.date)
        var balance = snap.balance
        var m = snapMonth.adding(1)
        while m <= month {
            balance += remaining(in: m)
            m = m.adding(1)
        }
        balance += bankEntries.filter { $0.date > snap.date && $0.date < limit }.reduce(0) { $0 + $1.amount }
        return balance.cents
    }

    func bankBalanceNow(current: YearMonth) -> Double {
        bankBalance(at: current) ?? 0
    }

    func bankSeries(from start: YearMonth, count: Int, current: YearMonth) -> [BankPoint] {
        start.range(count: count).compactMap { m in
            guard let b = bankBalance(at: m) else { return nil }
            return BankPoint(month: m, balance: b, isProjected: m > current)
        }
    }

    mutating func addBankSnapshot(balance: Double, note: String = "", date: Date = Date()) {
        bankSnapshots.append(BankSnapshot(date: date, balance: balance.cents, note: note))
    }

    mutating func deleteBankSnapshot(_ id: UUID) {
        bankSnapshots.removeAll { $0.id == id }
    }

    // MARK: Stortingen, opnames en overboekingen

    /// Zet geld op de bankrekening (positief) of haalt het eraf (negatief). Alleen in de app.
    mutating func addBankEntry(amount: Double, note: String = "", date: Date = Date()) {
        let value = amount.cents
        guard value != 0 else { return }
        bankEntries.append(BankEntry(date: date, amount: value, kind: value > 0 ? .deposit : .withdrawal, note: note))
    }

    mutating func deleteBankEntry(_ id: UUID) {
        bankEntries.removeAll { $0.id == id }
    }

    /// Boekt geld van de bankrekening naar een spaarpot.
    mutating func transferBankToPot(potID: UUID, amount: Double, note: String = "", date: Date = Date()) {
        let value = amount.cents
        guard value > 0, let target = pot(potID) else { return }
        bankEntries.append(BankEntry(date: date, amount: -value, kind: .toPot,
                                     note: note.isEmpty ? "Naar \(target.name)" : note, potID: potID))
        potEntries.append(PotEntry(potID: potID, date: date, amount: value, kind: .deposit,
                                   note: note.isEmpty ? "Van bankrekening" : note))
    }

    /// Boekt geld van een spaarpot terug naar de bankrekening.
    mutating func transferPotToBank(potID: UUID, amount: Double, note: String = "", date: Date = Date()) {
        let value = amount.cents
        guard value > 0, let source = pot(potID) else { return }
        bankEntries.append(BankEntry(date: date, amount: value, kind: .fromPot,
                                     note: note.isEmpty ? "Van \(source.name)" : note, potID: potID))
        potEntries.append(PotEntry(potID: potID, date: date, amount: -value, kind: .withdrawal,
                                   note: note.isEmpty ? "Naar bankrekening" : note))
    }

    // MARK: Buffer

    /// Gemiddelde uitgaven per maand (de laatste drie maanden t/m nu, anders de huidige plannen).
    func averageMonthlyExpenses(current: YearMonth) -> Double {
        let recent = current.adding(-2).range(count: 3).filter { $0 >= startMonth }
        let list = recent.isEmpty ? [current] : recent
        let total = list.reduce(0) { $0 + expensesTotal(in: $1) }
        return (total / Double(list.count)).cents
    }

    /// Gewenste buffer op de bankrekening.
    func bankBuffer(current: YearMonth) -> Double {
        (averageMonthlyExpenses(current: current) * settings.bankBufferMonths).cents
    }

    /// Wat er boven de buffer op de rekening staat (nooit negatief).
    func bankSurplusAboveBuffer(current: YearMonth) -> Double {
        guard hasBankBalance else { return 0 }
        return max(0, (bankBalanceNow(current: current) - bankBuffer(current: current)).cents)
    }
}
