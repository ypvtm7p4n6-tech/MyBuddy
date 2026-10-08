import Foundation

/// Verwacht bankverloop per maand.
struct BankPoint: Identifiable, Equatable {
    var month: YearMonth
    var balance: Double
    var isProjected: Bool
    var id: String { month.key }
}

/// Het verloop van de bankrekening op dagniveau: het laatste ingevulde saldo (of een virtuele 0 bij alleen
/// stortingen) plus alle gebeurtenissen daarna. Eén keer opgebouwd, daarna snel te bevragen voor veel dagen.
///
/// Saldo aan het eind van een dag = basis + alle gebeurtenissen met een datum na het meetmoment van de basis
/// en op of voor die dag. Gebeurtenissen van de maand van het meetmoment die ná dat moment vallen tellen dus mee.
struct BankTimeline {
    private let snapshots: [BankSnapshot]
    private let hasSnapshots: Bool
    private let firstEntryDate: Date?
    private let flow: CentsLedger

    /// De eerste maand waarvan gebeurtenissen nodig zijn voor vragen tussen `firstLimit` en `lastLimit`
    /// (beide exclusieve bovengrenzen: begin van de dag na de gevraagde dag). nil als er nooit een basis is.
    static func startMonth(for data: FinanceData, firstLimit: Date, lastLimit: Date) -> YearMonth? {
        let snaps = data.sortedBankSnapshots
        var earliest: Date?
        if !snaps.isEmpty {
            earliest = (snaps.last(where: { $0.date < firstLimit }) ?? snaps.first)?.date
        } else if let first = data.bankEntries.map({ $0.date }).min() {
            earliest = first.addingTimeInterval(-1)
        }
        guard let start = earliest, start < lastLimit else { return nil }
        return YearMonth(date: start)
    }

    init(_ data: FinanceData, firstLimit: Date, lastLimit: Date, events source: (YearMonth) -> [DayEvent]) {
        let snaps = data.sortedBankSnapshots
        snapshots = snaps
        hasSnapshots = !snaps.isEmpty
        firstEntryDate = data.bankEntries.map { $0.date }.min()

        var items: [(date: Date, cents: Int)] = []
        if let first = BankTimeline.startMonth(for: data, firstLimit: firstLimit, lastLimit: lastLimit) {
            let last = YearMonth(date: DayMath.lastMoment(before: lastLimit))
            var m = first
            var count = 0
            while m <= last && count < 2_400 {
                for event in source(m) where event.bankAmount != 0 {
                    items.append((event.date, CentsMath.int(event.bankAmount)))
                }
                m = m.adding(1)
                count += 1
            }
        }
        flow = CentsLedger(items: items)
    }

    /// Het meetpunt waar het saldo van uitgaat voor een vraag met bovengrens `limit`.
    private func base(before limit: Date) -> (date: Date, cents: Int)? {
        if let snap = snapshots.last(where: { $0.date < limit }) {
            return (snap.date, CentsMath.int(snap.balance))
        }
        if !hasSnapshots, let first = firstEntryDate, first < limit {
            return (first.addingTimeInterval(-1), 0)
        }
        return nil
    }

    /// Saldo vóór het moment `limit` (begin van de dag na de gevraagde dag). nil zolang er geen saldo bekend is.
    func balance(before limit: Date) -> Double? {
        guard let base = base(before: limit) else { return nil }
        return CentsMath.value(CentsMath.add(base.cents, flow.sum(after: base.date, before: limit)))
    }
}

extension FinanceData {
    var sortedBankSnapshots: [BankSnapshot] {
        bankSnapshots.sorted { $0.date < $1.date }
    }

    var hasBankBalance: Bool { !bankSnapshots.isEmpty || !bankEntries.isEmpty }

    /// Saldo aan het eind van `month`: het saldo aan het eind van de laatste dag van die maand.
    /// nil als er voor die maand nog geen saldo bekend is.
    func bankBalance(at month: YearMonth) -> Double? {
        bankBalance(on: month.date(day: month.dayCount))
    }

    /// Saldo op precies dit moment: het laatste meetpunt tot en met `moment` plus alle gebeurtenissen daarna
    /// die op of vóór `moment` vallen. Gebeurtenissen later op dezelfde dag (12:00 voor plangebeurtenissen) tellen
    /// nog niet mee, net zoals `DayEvent.isPlanned` ze "gepland" noemt. nil zolang er geen saldo bekend is.
    func bankBalance(atMoment moment: Date) -> Double? {
        let limit = DayMath.limit(including: moment)
        let timeline = BankTimeline(self, firstLimit: limit, lastLimit: limit, events: { self.bankFlowEvents(in: $0) })
        return timeline.balance(before: limit)
    }

    /// Saldo van nu: op het moment `today` als dat in `current` valt, anders het saldo aan het eind van `current`.
    /// 0 als er nog geen saldo bekend is. Een saldo dat je net invulde blijft dus staan tot de eerstvolgende
    /// geplande gebeurtenis echt aan de beurt is.
    func bankBalanceNow(current: YearMonth, today: Date = Date()) -> Double {
        if YearMonth(date: today) == current { return bankBalance(atMoment: today) ?? 0 }
        return bankBalance(at: current) ?? 0
    }

    func bankSeries(from start: YearMonth, count: Int, current: YearMonth) -> [BankPoint] {
        let months = start.range(count: count)
        guard let first = months.first, let last = months.last else { return [] }
        let timeline = BankTimeline(self, firstLimit: first.endExclusive, lastLimit: last.endExclusive,
                                    events: { self.bankFlowEvents(in: $0) })
        return months.compactMap { m in
            guard let b = timeline.balance(before: m.endExclusive) else { return nil }
            return BankPoint(month: m, balance: b, isProjected: m > current)
        }
    }

    /// Eén keer per aanroep alle saldi aan het eind van de maanden (nil = nog niet bekend).
    func bankBalances(atEndOf months: [YearMonth]) -> [Double?] {
        guard let first = months.min(), let last = months.max() else { return [] }
        let timeline = BankTimeline(self, firstLimit: first.endExclusive, lastLimit: last.endExclusive,
                                    events: { self.bankFlowEvents(in: $0) })
        return months.map { timeline.balance(before: $0.endExclusive) }
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
    /// Telt alle uitgaven mee, ook wat uit spaarpotten betaald wordt: een buffer moet ze allemaal dekken.
    func averageMonthlyExpenses(current: YearMonth) -> Double {
        let recent = current.adding(-2).range(count: 3).filter { $0 >= startMonth }
        let list = recent.isEmpty ? [current] : recent
        let total = CentsMath.sum(list.map { CentsMath.int(expensesTotal(in: $0)) })
        return (CentsMath.value(total) / Double(list.count)).cents
    }

    /// Gewenste buffer op de bankrekening.
    func bankBuffer(current: YearMonth) -> Double {
        (averageMonthlyExpenses(current: current) * settings.bankBufferMonths).cents
    }

    /// Wat er boven de buffer op de rekening staat (nooit negatief).
    func bankSurplusAboveBuffer(current: YearMonth, today: Date = Date()) -> Double {
        guard hasBankBalance else { return 0 }
        return max(0, (bankBalanceNow(current: current, today: today) - bankBuffer(current: current)).cents)
    }
}
