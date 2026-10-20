import Foundation

struct HoldingState: Equatable {
    var value: Double
    var invested: Double
    var isProjected: Bool
    /// Geschat uit "Totaal ingelegd", "Belegd sinds" en de inleg: er is (nog) geen echt meetpunt. De waarde is dan gelijk aan wat
    /// je hebt ingelegd, zonder rendement; toon "Geschat" en verberg Winst en Rendement (die zijn dan 0 en zeggen niets).
    var isEstimated: Bool = false

    var gain: Double { (value - invested).cents }
    /// Rendement als breuk; nil zolang er niets ingelegd is.
    var gainFraction: Double? { invested > 0 ? (value - invested) / invested : nil }
}

struct PortfolioPoint: Identifiable, Equatable {
    var month: YearMonth
    var value: Double
    var invested: Double
    var isProjected: Bool
    /// Waar elke meegetelde belegging in dit punt geschat is uit de inleg (zie `HoldingState.isEstimated`).
    var isEstimated: Bool = false
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

    /// De meetpunten waarmee een belegging rekent: de echte, of (zonder enig meetpunt) één afgeleid beginpunt.
    private struct HoldingBasis {
        var snapshots: [ValueSnapshot]
        var isEstimated: Bool
    }

    /// Eén belegging klaargezet voor een lus over maanden: de basis voor de waarde van de maanden t/m `current` (`now`, met `today`)
    /// en die voor het EINDE van `current` waar de prognose van verder rekent (`end`, zonder `today`). Zo wordt het afgeleide
    /// beginpunt één keer per belegging uitgerekend en niet bij elke maand opnieuw.
    private struct HoldingTrack {
        var holding: Holding
        var now: HoldingBasis
        var end: HoldingBasis
    }

    /// Een belegging zonder meetpunt krijgt een AFGELEID beginpunt uit "Totaal ingelegd" en de inleg: op de eerste dag van
    /// `startMonth` (Belegd sinds) is de waarde gelijk aan het ingelegde bedrag, en dat is wat je bij "Totaal ingelegd" intikte
    /// min de inleg die er sindsdien bij kwam. Zo is de waarde van nu gelijk aan "Totaal ingelegd" en loopt de grafiek vanaf
    /// "Belegd sinds", zonder rendement. Voor de lopende maand telt een inleg pas als zijn overschrijfdag geweest is (dezelfde
    /// kalenderdagregel als `historicState`). Er wordt NIETS in `snapshots` geschreven: geen verzonnen punt in de Waarde-updates
    /// of de back-up; een echt meetpunt neemt het over. Zonder bedrag en zonder inleg is er niets te schatten: nil.
    private func derivedOpening(_ h: Holding, current: YearMonth, cache: IncomeBasesCache, today: Date?) -> ValueSnapshot? {
        var later = 0.0
        var m = h.startMonth.adding(1)
        let todayMonth = today.map { YearMonth(date: $0) }
        while m <= current {
            if let today, let todayMonth, m >= todayMonth,
               DayMath.isPlanned(m.date(day: transferDay(for: h.id, in: m)), asOf: today) {
                m = m.adding(1)
                continue
            }
            later += allocation(h.id, in: m, cache: cache)
            m = m.adding(1)
        }
        let hasPlan = h.monthlyContribution != 0 || (h.contributionMode == .percentage && h.contributionPercent > 0)
        guard h.investedTotal > 0 || hasPlan || later != 0 else { return nil }
        let opening = max(0, h.investedTotal - later).cents
        return ValueSnapshot(date: h.startMonth.firstDay, value: opening, invested: opening)
    }

    private func holdingBasis(_ h: Holding, current: YearMonth, cache: IncomeBasesCache, today: Date?) -> HoldingBasis {
        let real = h.snapshots.sorted { $0.date < $1.date }
        if !real.isEmpty { return HoldingBasis(snapshots: real, isEstimated: false) }
        if let opening = derivedOpening(h, current: current, cache: cache, today: today) {
            return HoldingBasis(snapshots: [opening], isEstimated: true)
        }
        return HoldingBasis(snapshots: [], isEstimated: false)
    }

    private func holdingTrack(_ h: Holding, current: YearMonth, cache: IncomeBasesCache, today: Date?) -> HoldingTrack {
        let now = holdingBasis(h, current: current, cache: cache, today: today)
        let end = today == nil ? now : holdingBasis(h, current: current, cache: cache, today: nil)
        return HoldingTrack(holding: h, now: now, end: end)
    }

    /// Waarde op een moment in het verleden of nu: laatste meetpunt + inleg daarna (zonder meetpunt: het afgeleide beginpunt,
    /// zie `derivedOpening`).
    ///
    /// Zonder `today` is dit de waarde aan het EIND van `month`: de hele inleg van de maand telt mee, ook die van de 25e als
    /// het nog de 9e is. Dat is de goede basis voor grafieken en prognoses (die rekenen per maand verder). Met `today` rekent
    /// de waarde per KALENDERDAG, zoals de bank en de spaarpotten: een inleg telt pas mee vanaf de dag waarop hij wordt
    /// overgeschreven (`transferDay(for:in:)`, dezelfde dag als in de dagboekhouding), en dan de hele dag.
    private func historicState(_ h: Holding, basis: HoldingBasis, at month: YearMonth, cache: IncomeBasesCache,
                               today: Date? = nil) -> HoldingState? {
        let limit = month.endExclusive
        guard let snap = basis.snapshots.last(where: { $0.date < limit }) else { return nil }
        var value = snap.value
        var invested = snap.invested
        let todayMonth = today.map { YearMonth(date: $0) }
        var m = YearMonth(date: snap.date).adding(1)
        while m <= month {
            // Alleen de maand van `today` (en later) kan een overschrijving hebben die nog moet komen.
            if let today, let todayMonth, m >= todayMonth,
               DayMath.isPlanned(m.date(day: transferDay(for: h.id, in: m)), asOf: today) {
                m = m.adding(1)
                continue
            }
            let a = allocation(h.id, in: m, cache: cache)
            value += a
            invested += a
            m = m.adding(1)
        }
        return HoldingState(value: value.cents, invested: invested.cents, isProjected: false, isEstimated: basis.isEstimated)
    }

    /// Waarde aan het eind van `month`. Na de huidige maand: verwachte groei plus geplande inleg.
    func holdingState(_ h: Holding, at month: YearMonth, current: YearMonth) -> HoldingState? {
        holdingState(h, at: month, current: current, cache: incomeBasesCache())
    }

    /// Zoals hierboven, met het inkomen per maand uit `cache`. Een inleg als percentage van het inkomen rekent per maand
    /// over dat inkomen; zonder cache zou elke tussenstap het maandplan opnieuw bouwen (kwadratisch in het aantal maanden).
    /// `today` (alleen voor de maanden t/m `current`) rekent per kalenderdag, zie `historicState`; een maand na `current` gaat
    /// altijd uit van het EINDE van `current` (de prognose rekent per maand verder).
    private func holdingState(_ h: Holding, at month: YearMonth, current: YearMonth, cache: IncomeBasesCache,
                              today: Date? = nil) -> HoldingState? {
        let track = holdingTrack(h, current: current, cache: cache, today: today)
        return holdingState(track: track, at: month, current: current, cache: cache, today: today)
    }

    /// Zoals hierboven voor een belegging die al klaarstaat voor een lus (`holdingTrack`).
    private func holdingState(track: HoldingTrack, at month: YearMonth, current: YearMonth, cache: IncomeBasesCache,
                              today: Date?) -> HoldingState? {
        let h = track.holding
        if month <= current { return historicState(h, basis: track.now, at: month, cache: cache, today: today) }
        guard let base = historicState(h, basis: track.end, at: current, cache: cache) else { return nil }
        var value = base.value
        var invested = base.invested
        let rm = Growth.monthlyRate(annual: h.netReturn)
        var m = current.adding(1)
        while m <= month {
            let a = allocation(h.id, in: m, cache: cache)
            // Een verwachte waarde onder 0 bestaat niet: een grote negatieve inleg haalt je waarde naar 0, niet eronder.
            value = max(0, value * (1 + rm) + a)
            invested += a
            m = m.adding(1)
        }
        return HoldingState(value: value.cents, invested: invested.cents, isProjected: true, isEstimated: base.isEstimated)
    }

    /// De waarde aan het EIND van `current` (met de hele inleg van die maand). Wil je tonen wat je nu hebt, gebruik dan
    /// `holdingStateNow(_:current:today:)`; dit getal is bedoeld voor prognoses en grafieken.
    func holdingStateNow(_ h: Holding, current: YearMonth) -> HoldingState? {
        holdingState(h, at: current, current: current)
    }

    /// De waarde van NU, per kalenderdag zoals `potBalanceNow` en het banksaldo van nu: valt `today` in `current`, dan telt
    /// een inleg die nog moet worden overgeschreven (die van de 25e als het de 9e is) niet mee, en een inleg die vandaag valt
    /// de hele dag wel. Valt `today` niet in `current`, dan is dit de waarde aan het eind van `current`.
    func holdingStateNow(_ h: Holding, current: YearMonth, today: Date) -> HoldingState? {
        holdingState(h, at: current, current: current, cache: incomeBasesCache(), today: dayAware(today, current))
    }

    func holdingValueNow(_ h: Holding, current: YearMonth) -> Double {
        holdingStateNow(h, current: current)?.value ?? 0
    }

    func holdingValueNow(_ h: Holding, current: YearMonth, today: Date) -> Double {
        holdingStateNow(h, current: current, today: today)?.value ?? 0
    }

    /// `today` als de dag van nu in `current` valt, anders nil (dan is er geen "nu" binnen de maand en geldt het maandeinde).
    private func dayAware(_ today: Date?, _ current: YearMonth) -> Date? {
        guard let today, YearMonth(date: today) == current else { return nil }
        return today
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

    /// De portefeuille van NU, per kalenderdag (zie `holdingStateNow(_:current:today:)`). De bedragen zonder `today` zijn die
    /// van het eind van de maand: de goede start voor prognoses en doelen, maar niet wat je vandaag hebt.
    func portfolioValue(current: YearMonth, today: Date) -> Double {
        let cache = incomeBasesCache()
        let day = dayAware(today, current)
        return holdings.reduce(0) { $0 + (holdingState($1, at: current, current: current, cache: cache, today: day)?.value ?? 0) }.cents
    }

    func portfolioInvested(current: YearMonth, today: Date) -> Double {
        let cache = incomeBasesCache()
        let day = dayAware(today, current)
        return holdings.reduce(0) { $0 + (holdingState($1, at: current, current: current, cache: cache, today: day)?.invested ?? 0) }.cents
    }

    func portfolioGain(current: YearMonth, today: Date) -> Double {
        (portfolioValue(current: current, today: today) - portfolioInvested(current: current, today: today)).cents
    }

    /// Waarde van (een deel van) de portefeuille per maand. Maanden zonder enig meetpunt worden overgeslagen. Elk punt is de
    /// waarde aan het EIND van die maand. Met `today` is het punt van de lopende maand de waarde
    /// van NU (per kalenderdag, zoals `portfolioValue(current:today:)`), zodat het laatste echte punt van een grafiek gelijk is
    /// aan het getal erboven; de verwachte punten erna rekenen vanaf het eind van de lopende maand.
    func portfolioSeries(from start: YearMonth, count: Int, current: YearMonth, only ids: Set<UUID>? = nil,
                         today: Date? = nil) -> [PortfolioPoint] {
        let selected = holdings.filter { ids == nil || ids!.contains($0.id) }
        let cache = incomeBasesCache()
        let day = dayAware(today, current)
        // Het afgeleide beginpunt van elke belegging één keer, niet bij elke maand.
        let tracks = selected.map { holdingTrack($0, current: current, cache: cache, today: day) }
        return start.range(count: count).compactMap { m in
            var value = 0.0
            var invested = 0.0
            var any = false
            var allEstimated = true
            for track in tracks {
                if let s = holdingState(track: track, at: m, current: current, cache: cache, today: day) {
                    value += s.value
                    invested += s.invested
                    any = true
                    if !s.isEstimated { allEstimated = false }
                }
            }
            guard any else { return nil }
            return PortfolioPoint(month: m, value: value.cents, invested: invested.cents, isProjected: m > current,
                                  isEstimated: allEstimated)
        }
    }

    /// De eerste maand waarin (een deel van) de portefeuille iets te tekenen heeft: de maand van het eerste meetpunt of, bij een
    /// belegging zonder meetpunt, "Belegd sinds" (het afgeleide beginpunt). nil zonder enig gegeven. Een belegging die pas na
    /// `current` begint telt niet mee: die heeft nu nog geen waarde. Het venster van de grafiek begint hier (`PortfolioWindow`).
    func portfolioDataStart(current: YearMonth, today: Date? = nil, only ids: Set<UUID>? = nil) -> YearMonth? {
        let cache = incomeBasesCache()
        let day = dayAware(today, current)
        var first: YearMonth?
        for h in holdings where ids == nil || ids!.contains(h.id) {
            var start: YearMonth?
            if let earliest = h.snapshots.map(\.date).min() {
                start = YearMonth(date: earliest)
            } else if derivedOpening(h, current: current, cache: cache, today: day) != nil {
                start = h.startMonth
            }
            guard let s = start, s <= current else { continue }
            if let f = first { first = min(f, s) } else { first = s }
        }
        return first
    }

    func valueByKind(current: YearMonth) -> [KindSlice] {
        var totals: [HoldingKind: Double] = [:]
        for h in holdings { totals[h.kind, default: 0] += holdingValueNow(h, current: current) }
        return totals.filter { $0.value > 0 }
            .map { KindSlice(kind: $0.key, value: $0.value.cents) }
            .sorted { $0.value > $1.value }
    }

    /// De verdeling over soorten van NU, per kalenderdag (zoals `portfolioValue(current:today:)`).
    func valueByKind(current: YearMonth, today: Date) -> [KindSlice] {
        var totals: [HoldingKind: Double] = [:]
        for h in holdings { totals[h.kind, default: 0] += holdingValueNow(h, current: current, today: today) }
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
        } else if old.investedTotal != updated.investedTotal, !updated.isTracked, !updated.snapshots.isEmpty,
                  let state = holdingStateNow(updated, current: current, today: now) {
            // Niet gevolgd, met minstens een meetpunt: het nieuwe "Totaal ingelegd" komt in een meetpunt van vandaag, met de
            // waarde van nu. Anders blijft de reeks bij het oude bedrag (het scherm toonde 5.000, opgeslagen was 6.000).
            addSnapshot(holdingID: updated.id, value: state.value, invested: updated.investedTotal, date: now)
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
