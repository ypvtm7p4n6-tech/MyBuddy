import Foundation

struct HoldingState: Equatable {
    var value: Double
    var invested: Double
    var isProjected: Bool

    var gain: Double { (value - invested).cents }
    /// Rendement als breuk; nil zolang er niets ingelegd is.
    var gainFraction: Double? { invested > 0 ? (value - invested) / invested : nil }
}

struct PortfolioPoint: Identifiable, Equatable {
    var month: YearMonth
    var value: Double
    var invested: Double
    var isProjected: Bool
    var id: String { month.key }
}

struct KindSlice: Identifiable, Equatable {
    var kind: HoldingKind
    var value: Double
    var id: String { kind.rawValue }
}

extension FinanceData {
    func holding(_ id: UUID) -> Holding? { holdings.first { $0.id == id } }

    // MARK: Waarde per maand

    /// Waarde op een moment in het verleden of nu: laatste meetpunt + inleg daarna.
    private func historicState(_ h: Holding, at month: YearMonth, cache: IncomeBasesCache) -> HoldingState? {
        let snaps = h.snapshots.sorted { $0.date < $1.date }
        guard let snap = snaps.last(where: { $0.date < month.endExclusive }) else { return nil }
        var value = snap.value
        var invested = snap.invested
        var m = YearMonth(date: snap.date).adding(1)
        while m <= month {
            let a = allocation(h.id, in: m, cache: cache)
            value += a
            invested += a
            m = m.adding(1)
        }
        return HoldingState(value: value.cents, invested: invested.cents, isProjected: false)
    }

    /// Waarde aan het eind van `month`. Na de huidige maand: verwachte groei plus geplande inleg.
    func holdingState(_ h: Holding, at month: YearMonth, current: YearMonth) -> HoldingState? {
        holdingState(h, at: month, current: current, cache: incomeBasesCache())
    }

    /// Zoals hierboven, met het inkomen per maand uit `cache`. Een inleg als percentage van het inkomen rekent per maand
    /// over dat inkomen; zonder cache zou elke tussenstap het maandplan opnieuw bouwen (kwadratisch in het aantal maanden).
    private func holdingState(_ h: Holding, at month: YearMonth, current: YearMonth, cache: IncomeBasesCache) -> HoldingState? {
        if month <= current { return historicState(h, at: month, cache: cache) }
        guard let base = historicState(h, at: current, cache: cache) else { return nil }
        var value = base.value
        var invested = base.invested
        let rm = Growth.monthlyRate(annual: h.netReturn)
        var m = current.adding(1)
        while m <= month {
            let a = allocation(h.id, in: m, cache: cache)
            value = value * (1 + rm) + a
            invested += a
            m = m.adding(1)
        }
        return HoldingState(value: value.cents, invested: invested.cents, isProjected: true)
    }

    func holdingStateNow(_ h: Holding, current: YearMonth) -> HoldingState? {
        holdingState(h, at: current, current: current)
    }

    func holdingValueNow(_ h: Holding, current: YearMonth) -> Double {
        holdingStateNow(h, current: current)?.value ?? 0
    }

    // MARK: Portefeuille

    func portfolioValue(current: YearMonth) -> Double {
        let cache = incomeBasesCache()
        return holdings.reduce(0) { $0 + (holdingState($1, at: current, current: current, cache: cache)?.value ?? 0) }.cents
    }

    func portfolioInvested(current: YearMonth) -> Double {
        let cache = incomeBasesCache()
        return holdings.reduce(0) { $0 + (holdingState($1, at: current, current: current, cache: cache)?.invested ?? 0) }.cents
    }

    func portfolioGain(current: YearMonth) -> Double {
        (portfolioValue(current: current) - portfolioInvested(current: current)).cents
    }

    /// Waarde van (een deel van) de portefeuille per maand. Maanden zonder enig meetpunt worden overgeslagen.
    func portfolioSeries(from start: YearMonth, count: Int, current: YearMonth, only ids: Set<UUID>? = nil) -> [PortfolioPoint] {
        let selected = holdings.filter { ids == nil || ids!.contains($0.id) }
        let cache = incomeBasesCache()
        return start.range(count: count).compactMap { m in
            var value = 0.0
            var invested = 0.0
            var any = false
            for h in selected {
                if let s = holdingState(h, at: m, current: current, cache: cache) {
                    value += s.value
                    invested += s.invested
                    any = true
                }
            }
            guard any else { return nil }
            return PortfolioPoint(month: m, value: value.cents, invested: invested.cents, isProjected: m > current)
        }
    }

    func valueByKind(current: YearMonth) -> [KindSlice] {
        var totals: [HoldingKind: Double] = [:]
        for h in holdings { totals[h.kind, default: 0] += holdingValueNow(h, current: current) }
        return totals.filter { $0.value > 0 }
            .map { KindSlice(kind: $0.key, value: $0.value.cents) }
            .sorted { $0.value > $1.value }
    }

    /// Gewogen verwacht rendement na kosten van de portefeuille.
    func weightedNetReturn(current: YearMonth) -> Double {
        guard !holdings.isEmpty else { return Growth.fallbackReturn }
        let total = portfolioValue(current: current)
        if total > 0 {
            let weighted = holdings.reduce(0.0) { $0 + holdingValueNow($1, current: current) * $1.netReturn }
            return weighted / total
        }
        return holdings.reduce(0.0) { $0 + $1.netReturn } / Double(holdings.count)
    }

    /// Wat er in totaal per maand wordt ingelegd, voor schattingen (toekomstschatting, doelen): wat er deze maand in totaal
    /// wordt ingelegd. Bij een salaris om de zoveel weken of dagen en een inleg als percentage van het inkomen is het die van
    /// een GEMIDDELDE maand (`estimatedFigures`). Bij het maandelijkse schema precies `investedTotal(in:)`.
    func monthlyInvestment(current: YearMonth) -> Double {
        CentsMath.value(estimatedFigures(current).invested)
    }

    // MARK: Wijzigen

    mutating func addHolding(_ holding: Holding, initialValue: Double? = nil, now: Date = Date()) {
        holdings.append(holding)
        if let v = initialValue {
            addSnapshot(holdingID: holding.id, value: v, invested: holding.investedTotal > 0 ? holding.investedTotal : v, date: now)
        }
    }

    mutating func updateHolding(_ updated: Holding, current: YearMonth, now: Date = Date()) {
        guard let i = holdings.firstIndex(where: { $0.id == updated.id }) else { return }
        let old = holdings[i]
        holdings[i] = updated
        // Een nieuwe standaardinleg geldt ook meteen voor de lopende maand (zoals bij `updatePot`): een ander vast bedrag,
        // maar ook een andere inlegwijze (vast bedrag of percentage), een ander percentage of een andere grondslag. Een
        // wijziging die de inleg niet raakt laat de lopende maand met rust.
        syncCurrentMonth(updated.id, with: old.contributionRule, current: current)
        // Aantal of ingelegd bedrag gewijzigd bij een gevolgde belegging: nieuw meetpunt met de laatste koers.
        let changed = old.units != updated.units || old.investedTotal != updated.investedTotal
        if changed, updated.isTracked, let price = updated.lastPrice, let units = updated.units {
            addSnapshot(holdingID: updated.id, value: units * price, invested: updated.investedTotal, date: now)
        }
    }

    mutating func deleteHolding(_ id: UUID) {
        holdings.removeAll { $0.id == id }
        for key in Array(months.keys) {
            months[key]?.allocations.removeValue(forKey: id.uuidString)
            // Ook een eigen percentage van een maand (variabel percentage) hoort bij de belegging en verdwijnt met haar.
            months[key]?.percentAllocations.removeValue(forKey: id.uuidString)
        }
        homeHoldingIDs = homeHoldingIDs?.filter { $0 != id }
    }

    /// Voegt een meetpunt toe. Een tweede meetpunt op dezelfde dag vervangt het eerste.
    mutating func addSnapshot(holdingID: UUID, value: Double, invested: Double? = nil, date: Date = Date()) {
        guard let i = holdings.firstIndex(where: { $0.id == holdingID }) else { return }
        let cal = YearMonth.calendar
        var fallbackInvested = value
        if holdings[i].investedTotal > 0 {
            fallbackInvested = holdings[i].investedTotal
        } else if let last = holdings[i].snapshots.sorted(by: { $0.date < $1.date }).last {
            fallbackInvested = last.invested
        }
        let snap = ValueSnapshot(date: date, value: value.cents, invested: (invested ?? fallbackInvested).cents)
        holdings[i].snapshots.removeAll { cal.isDate($0.date, inSameDayAs: date) }
        holdings[i].snapshots.append(snap)
        holdings[i].snapshots.sort { $0.date < $1.date }
        if let inv = invested { holdings[i].investedTotal = inv.cents }
    }

    mutating func deleteSnapshot(holdingID: UUID, snapshotID: UUID) {
        guard let i = holdings.firstIndex(where: { $0.id == holdingID }) else { return }
        holdings[i].snapshots.removeAll { $0.id == snapshotID }
    }

    /// Slaat een nieuwe koers (in euro) op en maakt daarmee een meetpunt.
    mutating func recordPrice(holdingID: UUID, price: Double, currency: String, date: Date = Date()) {
        guard let i = holdings.firstIndex(where: { $0.id == holdingID }) else { return }
        holdings[i].lastPrice = price
        holdings[i].lastPriceDate = date
        holdings[i].priceCurrency = currency
        if let units = holdings[i].units, units > 0 {
            addSnapshot(holdingID: holdingID, value: units * price, invested: holdings[i].investedTotal, date: date)
        }
    }

    /// Vult de historie aan met koersen van vóór het eerste meetpunt (neemt aan dat je altijd evenveel stuks had).
    mutating func importHistory(holdingID: UUID, prices: [(date: Date, price: Double)]) {
        guard let i = holdings.firstIndex(where: { $0.id == holdingID }),
              let units = holdings[i].units, units > 0 else { return }
        let earliest = holdings[i].snapshots.map(\.date).min() ?? Date()
        let invested = holdings[i].investedTotal
        for p in prices where p.date < earliest {
            holdings[i].snapshots.append(ValueSnapshot(date: p.date, value: (units * p.price).cents, invested: invested))
        }
        holdings[i].snapshots.sort { $0.date < $1.date }
    }

    // MARK: Home-keuze

    /// De beleggingen die op Home staan (maximaal 4).
    func homeHoldings() -> [Holding] {
        if let ids = homeHoldingIDs {
            return ids.compactMap { id in holdings.first { $0.id == id } }.prefix(4).map { $0 }
        }
        return Array(holdings.prefix(4))
    }
}
