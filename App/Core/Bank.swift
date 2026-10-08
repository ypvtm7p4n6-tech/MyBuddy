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

    var hasBankBalance: Bool { !bankSnapshots.isEmpty }

    /// Saldo aan het eind van `month`: laatste ingevulde saldo plus het overschot van latere maanden.
    /// nil als er voor die maand nog geen saldo bekend is.
    func bankBalance(at month: YearMonth) -> Double? {
        let snaps = sortedBankSnapshots
        guard let snap = snaps.last(where: { $0.date < month.endExclusive }) else { return nil }
        let snapMonth = YearMonth(date: snap.date)
        var balance = snap.balance
        var m = snapMonth.adding(1)
        while m <= month {
            balance += remaining(in: m)
            m = m.adding(1)
        }
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
