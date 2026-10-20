import Foundation

/// Totaal vermogen op één moment, opgesplitst.
struct NetWorthPoint: Identifiable, Equatable {
    var month: YearMonth
    var bank: Double
    var pots: Double
    var investments: Double
    var isProjected: Bool
    /// Is het banksaldo van deze maand bekend? Zo niet, dan telt de bank als 0 mee in `total` en hoort er een noot bij
    /// ("Zonder banksaldo"), anders lijkt het vermogen te laag zonder aanwijzing waarom.
    var bankKnown: Bool = true

    var id: String { month.key }
    var total: Double { CentsMath.value(CentsMath.int(bank) + CentsMath.int(pots) + CentsMath.int(investments)) }
}

extension FinanceData {
    /// Vermogen aan het eind van `month`: bank, spaarpotten (met geplande inleg en verwachte rente) en beleggingen.
    func netWorth(at month: YearMonth, current: YearMonth) -> NetWorthPoint {
        let potCents = CentsMath.sum(pots.map { CentsMath.int(potBalance($0.id, at: month)) })
        return netWorthPoint(month: month, bank: bankBalance(at: month), potCents: potCents,
                             invested: investmentValue(at: month, current: current), current: current)
    }

    /// Vermogen van nu: bank en spaarpotten op het moment `today` (wat nog komt, zoals het salaris van de 25e of de
    /// geplande inleg, telt niet mee) plus beleggingen. Valt `today` buiten `current`, dan is het het vermogen aan
    /// het eind van `current`. Gebruik dit voor een kop als "Totaal vermogen"; `netWorth(at:current:)` is voor
    /// grafieken en het eind van een maand.
    func netWorthNow(current: YearMonth, today: Date = Date()) -> NetWorthPoint {
        let potCents = CentsMath.sum(pots.map { CentsMath.int(potBalanceNow($0.id, current: current, today: today)) })
        return netWorthPoint(month: current, bank: bankBalanceNowIfKnown(current: current, today: today),
                             potCents: potCents, invested: investmentValue(at: current, current: current), current: current)
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
        // De beleggingen één keer voor alle maanden (met het afgeleide beginpunt van een belegging zonder meetpunt).
        var invested: [String: Double] = [:]
        for point in portfolioSeries(from: months[0], count: months.count, current: current) { invested[point.month.key] = point.value }
        return months.indices.map { i in
            netWorthPoint(month: months[i], bank: banks[i], potCents: potCents[i],
                          invested: invested[months[i].key] ?? 0, current: current)
        }
    }

    /// De waarde van alle beleggingen aan het eind van `month` (een belegging zonder gegevens telt als 0).
    private func investmentValue(at month: YearMonth, current: YearMonth) -> Double {
        holdings.reduce(0) { $0 + (holdingState($1, at: month, current: current)?.value ?? 0) }.cents
    }

    private func netWorthPoint(month: YearMonth, bank: Double?, potCents: Int, invested: Double,
                               current: YearMonth) -> NetWorthPoint {
        NetWorthPoint(month: month,
                      bank: bank ?? 0,
                      pots: CentsMath.value(potCents),
                      investments: invested.cents,
                      isProjected: month > current,
                      bankKnown: bank != nil)
    }

    /// Is er nog niets ingevuld? Wordt gebruikt om een welkomstkaart te tonen (met de knop "Voorbeelddata", die alles
    /// overschrijft). Alles wat de gebruiker zelf invulde telt als "ingevuld": potten en potboekingen, beleggingen,
    /// banksaldi en bankboekingen, doelen, salaris (elke afwijking van de beginwaarden), toegepaste versnellers en
    /// maanden met inkomsten, uitgaven, een verdeling of een eigen salaris, uren of overschrijfdag. Een maand die de app
    /// zelf vastlegde zonder inhoud (`materialize(upTo:)`) en de instellingen (die worden vanzelf bijgewerkt) tellen niet.
    var isEmptyStart: Bool {
        if !pots.isEmpty || !potEntries.isEmpty || !holdings.isEmpty { return false }
        if !bankSnapshots.isEmpty || !bankEntries.isEmpty || !goals.isEmpty { return false }
        if !appliedAccelerators.isEmpty { return false }
        if salary != SalarySettings() { return false }
        for plan in months.values {
            if !plan.expenses.isEmpty || !plan.extraIncome.isEmpty || !plan.allocations.isEmpty { return false }
            if plan.salaryOverride != nil || plan.hoursOverride != nil || plan.transferDay != nil { return false }
        }
        return true
    }
}
