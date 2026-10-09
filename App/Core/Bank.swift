import Foundation

/// Verwacht bankverloop per maand.
struct BankPoint: Identifiable, Equatable {
    var month: YearMonth
    var balance: Double
    var isProjected: Bool
    var id: String { month.key }
}

/// De andere helft(en) van een overboeking die samen met een boeking verdwijnen als je die verwijdert.
/// Zie `FinanceData.pairedEntries(ofBank:)` en `pairedEntries(ofPot:)`.
struct PairedRemoval: Equatable {
    /// De bijbehorende bankboekingen (nooit de gekozen boeking zelf).
    var bankEntries: [BankEntry] = []
    /// De bijbehorende potboekingen (nooit de gekozen boeking zelf).
    var potEntries: [PotEntry] = []

    /// Aantal boekingen dat er extra verdwijnt.
    var count: Int { bankEntries.count + potEntries.count }
    var isEmpty: Bool { count == 0 }

    /// Totaal van de bedragen (zonder teken) van wat er extra verdwijnt, op centen.
    var amount: Double {
        let cents = bankEntries.map { abs(CentsMath.int($0.amount)) } + potEntries.map { abs(CentsMath.int($0.amount)) }
        return CentsMath.value(CentsMath.sum(cents))
    }

    /// Waarschuwing voor in de app. nil als er niets extra verdwijnt.
    var warning: String? {
        switch count {
        case 0: return nil
        case 1: return "Hiermee verdwijnt ook de bijbehorende boeking van \(Fmt.euro(amount))."
        default: return "Hiermee verdwijnen ook \(count) bijbehorende boekingen van samen \(Fmt.euro(amount))."
        }
    }
}

/// Het verloop van de bankrekening op dagniveau: het laatste ingevulde saldo (of een virtuele 0 bij alleen
/// stortingen) plus alle gebeurtenissen daarna. Eén keer opgebouwd, daarna snel te bevragen voor veel dagen.
///
/// Saldo aan het eind van een dag = basis + de gebeurtenissen na de basis en op of voor die dag. Wat "na de basis" is,
/// hangt af van het soort gebeurtenis:
/// - handmatige bankboekingen houden hun eigen tijdstip: alleen wat ná het meetmoment valt telt mee;
/// - planboekingen (salaris, inkomsten, uitgaven, inleg: alles uit het plan, ze staan op 12:00 van hun dag) op
///   dezelfde kalenderdag als het meetmoment gelden als al verwerkt. De basis is voor hen het EINDE van de dag van
///   het meetmoment. Anders telt een saldo dat je om 08:30 op salarisdag invult het salaris om 12:00 nog eens mee.
struct BankTimeline {
    private let snapshots: [BankSnapshot]
    private let hasSnapshots: Bool
    private let firstEntryDate: Date?
    /// Boekingen uit het plan, met hun datum (12:00).
    private let planFlow: CentsLedger
    /// Handmatige bankboekingen, met hun eigen tijdstip.
    private let entryFlow: CentsLedger

    /// Het punt waar een saldo van uitgaat: het moment van de meting en het moment waarna planboekingen meetellen.
    private struct Base {
        var date: Date
        var cents: Int
        var planDate: Date
    }

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

        var planItems: [(date: Date, cents: Int)] = []
        var entryItems: [(date: Date, cents: Int)] = []
        if let first = BankTimeline.startMonth(for: data, firstLimit: firstLimit, lastLimit: lastLimit) {
            let last = YearMonth(date: DayMath.lastMoment(before: lastLimit))
            var m = first
            var count = 0
            while m <= last && count < 2_400 {
                for event in source(m) where event.bankAmount != 0 {
                    let item = (date: event.date, cents: CentsMath.int(event.bankAmount))
                    if event.kind == .bankEntry { entryItems.append(item) } else { planItems.append(item) }
                }
                m = m.adding(1)
                count += 1
            }
        }
        planFlow = CentsLedger(items: planItems)
        entryFlow = CentsLedger(items: entryItems)
    }

    /// Het meetpunt waar het saldo van uitgaat voor een vraag met bovengrens `limit`.
    private func base(before limit: Date) -> Base? {
        if let snap = snapshots.last(where: { $0.date < limit }) {
            // Planboekingen van de dag van het meetmoment zitten al in het ingevulde saldo.
            let endOfDay = DayMath.lastMoment(before: DayMath.nextDayStart(after: snap.date))
            return Base(date: snap.date, cents: CentsMath.int(snap.balance), planDate: endOfDay)
        }
        if !hasSnapshots, let first = firstEntryDate, first < limit {
            // Geen meting, alleen een virtuele 0 vlak voor de eerste boeking: niets is "al verwerkt".
            let start = first.addingTimeInterval(-1)
            return Base(date: start, cents: 0, planDate: start)
        }
        return nil
    }

    /// Saldo vóór het moment `limit` (begin van de dag na de gevraagde dag). nil zolang er geen saldo bekend is.
    func balance(before limit: Date) -> Double? {
        guard let base = base(before: limit) else { return nil }
        let entries = entryFlow.sum(after: base.date, before: limit)
        let plan = planFlow.sum(after: base.planDate, before: limit)
        return CentsMath.value(CentsMath.add(base.cents, CentsMath.add(entries, plan)))
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

    /// Saldo op precies dit moment: het laatste meetpunt tot en met `moment` plus de gebeurtenissen daarna die op of
    /// vóór `moment` vallen. Handmatige boekingen houden hun eigen tijdstip. Planboekingen (salaris, inkomsten,
    /// uitgaven, inleg) op dezelfde kalenderdag als het meetpunt zitten al in het ingevulde saldo en tellen dus
    /// niet nog eens mee, ook niet als ze (12:00) later op die dag vallen. nil zolang er geen saldo bekend is.
    func bankBalance(atMoment moment: Date) -> Double? {
        let limit = DayMath.limit(including: moment)
        let timeline = BankTimeline(self, firstLimit: limit, lastLimit: limit, events: { self.bankFlowEvents(in: $0) })
        return timeline.balance(before: limit)
    }

    /// Saldo van nu: op het moment `today` als dat in `current` valt, anders het saldo aan het eind van `current`.
    /// 0 als er nog geen saldo bekend is. Een saldo dat je net invulde blijft dus staan tot de eerstvolgende
    /// geplande gebeurtenis van een latere dag aan de beurt is.
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

    /// Verwijdert een boeking. Hoort ze bij een overboeking (`pairID`), dan verdwijnt de andere helft ook: bank en
    /// spaarpot samen veranderen dan niet door één kant te wissen. Boekingen zonder `pairID` (van vóór deze regel)
    /// blijven los verwijderbaar.
    mutating func deleteBankEntry(_ id: UUID) {
        let pair = bankEntries.first { $0.id == id }?.pairID
        bankEntries.removeAll { $0.id == id || (pair != nil && $0.pairID == pair) }
        if let pair { potEntries.removeAll { $0.pairID == pair } }
    }

    /// Wat er samen met deze bankboeking verdwijnt als je ze verwijdert (de andere helft van de overboeking).
    /// Leeg bij een losse boeking of een onbekend id. Bedoeld voor een waarschuwing in de app.
    func pairedEntries(ofBank id: UUID) -> PairedRemoval {
        guard let pair = bankEntries.first(where: { $0.id == id })?.pairID else { return PairedRemoval() }
        return pairedRemoval(pairID: pair, exceptBank: id, exceptPot: nil)
    }

    /// Wat er samen met deze potboeking verdwijnt als je ze verwijdert (de andere helft van de overboeking).
    /// Leeg bij een losse boeking of een onbekend id. Bedoeld voor een waarschuwing in de app.
    func pairedEntries(ofPot id: UUID) -> PairedRemoval {
        guard let pair = potEntries.first(where: { $0.id == id })?.pairID else { return PairedRemoval() }
        return pairedRemoval(pairID: pair, exceptBank: nil, exceptPot: id)
    }

    private func pairedRemoval(pairID: UUID, exceptBank: UUID?, exceptPot: UUID?) -> PairedRemoval {
        PairedRemoval(bankEntries: bankEntries.filter { $0.pairID == pairID && $0.id != exceptBank },
                      potEntries: potEntries.filter { $0.pairID == pairID && $0.id != exceptPot })
    }

    /// Boekt geld van de bankrekening naar een spaarpot. Beide helften delen een `pairID`.
    mutating func transferBankToPot(potID: UUID, amount: Double, note: String = "", date: Date = Date()) {
        let value = amount.cents
        guard value > 0, let target = pot(potID) else { return }
        let pair = UUID()
        bankEntries.append(BankEntry(date: date, amount: -value, kind: .toPot,
                                     note: note.isEmpty ? "Naar \(target.name)" : note, potID: potID, pairID: pair))
        potEntries.append(PotEntry(potID: potID, date: date, amount: value, kind: .deposit,
                                   note: note.isEmpty ? "Van bankrekening" : note, pairID: pair))
    }

    /// Boekt geld van een spaarpot terug naar de bankrekening. Beide helften delen een `pairID`.
    mutating func transferPotToBank(potID: UUID, amount: Double, note: String = "", date: Date = Date()) {
        let value = amount.cents
        guard value > 0, let source = pot(potID) else { return }
        let pair = UUID()
        bankEntries.append(BankEntry(date: date, amount: value, kind: .fromPot,
                                     note: note.isEmpty ? "Van \(source.name)" : note, potID: potID, pairID: pair))
        potEntries.append(PotEntry(potID: potID, date: date, amount: -value, kind: .withdrawal,
                                   note: note.isEmpty ? "Naar bankrekening" : note, pairID: pair))
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
