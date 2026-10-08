import Foundation

/// Totaal vermogen op één moment, opgesplitst.
struct NetWorthPoint: Identifiable, Equatable {
    var month: YearMonth
    var bank: Double
    var pots: Double
    var investments: Double
    var isProjected: Bool

    var id: String { month.key }
    var total: Double { (bank + pots + investments).cents }
}

extension FinanceData {
    func netWorth(at month: YearMonth, current: YearMonth) -> NetWorthPoint {
        let potsTotal = pots.reduce(0) { $0 + potBalance($1.id, at: month) }
        let invested = holdings.reduce(0) { $0 + (holdingState($1, at: month, current: current)?.value ?? 0) }
        return NetWorthPoint(month: month,
                             bank: bankBalance(at: month) ?? 0,
                             pots: potsTotal.cents,
                             investments: invested.cents,
                             isProjected: month > current)
    }

    func netWorthSeries(from start: YearMonth, count: Int, current: YearMonth) -> [NetWorthPoint] {
        start.range(count: count).map { netWorth(at: $0, current: current) }
    }

    /// Is er al iets ingevuld? Wordt gebruikt om een welkomstkaart te tonen.
    var isEmptyStart: Bool {
        pots.isEmpty && holdings.isEmpty && bankSnapshots.isEmpty && salary.monthlyAmount() == 0 && goals.isEmpty
    }
}
