import Foundation

/// Totaal vermogen op één moment, opgesplitst.
struct NetWorthPoint: Identifiable, Equatable {
    var month: YearMonth
    var bank: Double
    var pots: Double
    var investments: Double
    var isProjected: Bool

    var id: String { month.key }
    var total: Double { CentsMath.value(CentsMath.int(bank) + CentsMath.int(pots) + CentsMath.int(investments)) }
}

extension FinanceData {
    /// Vermogen aan het eind van `month`: bank, spaarpotten (met geplande inleg en verwachte rente) en beleggingen.
    func netWorth(at month: YearMonth, current: YearMonth) -> NetWorthPoint {
        let potCents = CentsMath.sum(pots.map { CentsMath.int(potBalance($0.id, at: month)) })
        return netWorthPoint(month: month, bank: bankBalance(at: month), potCents: potCents, current: current)
    }

    /// Vermogen van nu: bank en spaarpotten op het moment `today` (wat nog komt, zoals het salaris van de 25e of de
    /// geplande inleg, telt niet mee) plus beleggingen. Valt `today` buiten `current`, dan is het het vermogen aan
    /// het eind van `current`. Gebruik dit voor een kop als "Totaal vermogen"; `netWorth(at:current:)` is voor
    /// grafieken en het eind van een maand.
    func netWorthNow(current: YearMonth, today: Date = Date()) -> NetWorthPoint {
        let potCents = CentsMath.sum(pots.map { CentsMath.int(potBalanceNow($0.id, current: current, today: today)) })
        return netWorthPoint(month: current, bank: bankBalanceNow(current: current, today: today),
                             potCents: potCents, current: current)
    }

    func netWorthSeries(from start: YearMonth, count: Int, current: YearMonth) -> [NetWorthPoint] {
        let months = start.range(count: count)
        guard let last = months.last else { return [] }
        // Het bankverloop en het verloop van elke pot één keer opbouwen voor alle maanden.
        let banks = bankBalances(atEndOf: months)
        var potCents = [Int](repeating: 0, count: months.count)
        for pot in pots {
            let flows = potFlows(pot, throughMonth: last)
            for i in months.indices { potCents[i] = CentsMath.add(potCents[i], flows.cents(before: months[i].endExclusive)) }
        }
        return months.indices.map { i in
            netWorthPoint(month: months[i], bank: banks[i], potCents: potCents[i], current: current)
        }
    }

    private func netWorthPoint(month: YearMonth, bank: Double?, potCents: Int, current: YearMonth) -> NetWorthPoint {
        let invested = holdings.reduce(0) { $0 + (holdingState($1, at: month, current: current)?.value ?? 0) }
        return NetWorthPoint(month: month,
                             bank: bank ?? 0,
                             pots: CentsMath.value(potCents),
                             investments: invested.cents,
                             isProjected: month > current)
    }

    /// Is er al iets ingevuld? Wordt gebruikt om een welkomstkaart te tonen.
    var isEmptyStart: Bool {
        pots.isEmpty && holdings.isEmpty && bankSnapshots.isEmpty && salary.monthlyAmount() == 0 && goals.isEmpty
    }
}
