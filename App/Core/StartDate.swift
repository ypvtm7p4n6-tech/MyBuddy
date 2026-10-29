import Foundation

// MARK: - De startdatum
//
// De tijdlijn begint op `firstDay`: de startdatum als die is ingesteld (`startDay`), anders de eerste dag van `startMonth`. Alles
// wat daarvoor valt bestaat niet in de cijfers. Zonder startdatum rekent alles precies zoals altijd (ook met boekingen van vóór
// de startmaand): elke plek hieronder is dan een controle die niets verandert.
//
// Wat telt, in één regel per soort (docs/work/plan.md par. 2.1):
//
//  - Een GEPLANDE gebeurtenis (salaris, extra inkomsten, uitgaven, inleg, rente) telt alleen als haar dag op of na de startdag valt
//    (`counts(day:in:)`, `transferCounts(_:in:)`). Vóór de startmaand telt niets (`month >= startMonth`, zoals altijd).
//  - HANDMATIGE boekingen op de bank en in de spaarpotten en ingevulde banksaldi van vóór het begin van de startdag tellen niet mee
//    (`countedBankEntries`, `countedPotEntries`, `countedBankSnapshots`). Ze blijven bewaard: een eerdere startdatum brengt ze terug.
//  - De sommen van een maand (`monthFigures`, `expenseOverview`, `salaryAmount`, ...) en de gebeurtenissen van de dagen komen uit
//    dezelfde regels, dus de dagboekhouding blijft sluiten.
//  - De standaard-salarisdag (`salaryDay(in:)`) en de overschrijfdagen volgen het SCHEMA, niet de startdag. Valt zo'n dag vóór de
//    start, dan telt die inkomst of inleg niet mee: wat toen gebeurde zit in je beginsaldo.
//  - SCHATTINGEN (buffer, aankoopcheck, versnellers, doelen, toekomstschatting) rekenen met een HELE startmaand (`forEstimates`).

extension FinanceData {
    /// De startdatum zoals hij geldt: alleen als hij in `startMonth` valt (wie `startMonth` rechtstreeks zet, laat de startdatum los).
    var effectiveStartDay: CalendarDay? {
        guard let day = startDay, day.yearMonth == startMonth else { return nil }
        return day
    }

    /// De eerste dag van de tijdlijn: de startdatum, anders de eerste dag van de startmaand.
    var firstDay: CalendarDay {
        effectiveStartDay ?? CalendarDay(month: startMonth, day: 1)
    }

    /// De startdatum voor een datumkiezer (12:00 van die dag); nil zonder ingestelde startdatum.
    var startDate: Date? {
        effectiveStartDay?.date()
    }

    /// De eerste dag (1...31) van `month` die meetelt: 1 voor elke maand na de startmaand, de dag van de startdatum in de startmaand
    /// en `Int.max` (niets telt) voor een maand ervoor. Zonder startdatum is het altijd 1: de bestaande controles op `startMonth`
    /// houden de maanden daarvoor buiten beeld, precies zoals altijd.
    func firstCountedDay(in month: YearMonth) -> Int {
        guard let start = effectiveStartDay else { return 1 }
        if month < start.yearMonth { return Int.max }
        if month == start.yearMonth { return start.day }
        return 1
    }

    /// Telt een gebeurtenis op dag `day` van `month` mee?
    func counts(day: Int, in month: YearMonth) -> Bool {
        day >= firstCountedDay(in: month)
    }

    /// Telt de overschrijving van een spaarpot of belegging in `month` mee (de overschrijfdag valt op of na de startdag)? De
    /// overschrijfdag volgt het schema (`transferDay(for:in:)`), niet de startdag.
    func transferCounts(_ id: UUID, in month: YearMonth) -> Bool {
        let first = firstCountedDay(in: month)
        if first <= 1 { return true }
        return transferDay(for: id, in: month) >= first
    }

    /// Telt een inkomstenregel (extra inkomsten) in `month` mee? Haar dag (de eigen dag, anders de salarisdag van die maand) valt
    /// op of na de startdag. In een gewone maand is dat altijd zo, zonder de dag uit te rekenen.
    func incomeCounts(_ line: MoneyLine, in month: YearMonth) -> Bool {
        let first = firstCountedDay(in: month)
        return first <= 1 || incomeDay(of: line, in: month) >= first
    }

    /// Telt een uitgave in `month` mee? Haar dag (de eigen dag, anders de 1e) valt op of na de startdag.
    func expenseCounts(_ line: MoneyLine, in month: YearMonth) -> Bool {
        let first = firstCountedDay(in: month)
        return first <= 1 || expenseDay(of: line) >= first
    }

    // MARK: Handmatige gegevens

    /// Het moment waarvóór handmatige boekingen en ingevulde saldi niet meetellen: het begin van de startdag. nil zonder
    /// startdatum (dan telt alles, zoals altijd).
    var startCutoff: Date? {
        guard let start = effectiveStartDay else { return nil }
        return YearMonth.calendar.startOfDay(for: start.date())
    }

    /// De handmatige bankboekingen die meetellen. Zonder startdatum zijn het gewoon alle boekingen (geen kopie).
    var countedBankEntries: [BankEntry] {
        guard let cutoff = startCutoff else { return bankEntries }
        return bankEntries.filter { $0.date >= cutoff }
    }

    /// De handmatige potboekingen die meetellen (zie `countedBankEntries`).
    var countedPotEntries: [PotEntry] {
        guard let cutoff = startCutoff else { return potEntries }
        return potEntries.filter { $0.date >= cutoff }
    }

    /// De ingevulde banksaldi die meetellen (zie `countedBankEntries`), in de volgorde waarin ze zijn bewaard.
    var countedBankSnapshots: [BankSnapshot] {
        guard let cutoff = startCutoff else { return bankSnapshots }
        return bankSnapshots.filter { $0.date >= cutoff }
    }

    /// Hoeveel handmatige gegevens vóór het begin van `day` liggen: bankboekingen, potboekingen en ingevulde saldi. Voor de
    /// pagina Startdatum ("Wat verandert er?") en de waarschuwing vóór het instellen van een startdatum.
    func entriesBefore(_ day: CalendarDay) -> (bank: Int, pots: Int, balances: Int) {
        let cutoff = YearMonth.calendar.startOfDay(for: day.date())
        let bank = bankEntries.filter { $0.date < cutoff }.count
        let potsCount = potEntries.filter { $0.date < cutoff }.count
        let balances = bankSnapshots.filter { $0.date < cutoff }.count
        return (bank, potsCount, balances)
    }

    /// Hoeveel boekingen en ingevulde saldi op de bankrekening er vóór de startdag liggen (bewaard, maar ze tellen niet mee). 0
    /// zonder startdatum.
    var hiddenBankCount: Int {
        guard let cutoff = startCutoff else { return 0 }
        let entries = bankEntries.filter { $0.date < cutoff }.count
        let balances = bankSnapshots.filter { $0.date < cutoff }.count
        return entries + balances
    }

    /// Hoeveel potboekingen er vóór de startdag liggen (bewaard, maar ze tellen niet mee), van één pot of van alle potten. 0 zonder
    /// startdatum.
    func hiddenPotCount(for potID: UUID? = nil) -> Int {
        guard let cutoff = startCutoff else { return 0 }
        return potEntries.filter { $0.date < cutoff && (potID == nil || $0.potID == potID) }.count
    }

    /// Het aantal maanden dat door een startdatum op `day` uit beeld raakt (de maanden van de huidige startmaand tot de maand van
    /// `day`), voor "Wat verandert er?". 0 als `day` niet later is dan de huidige eerste dag.
    func monthsDropped(by day: CalendarDay) -> Int {
        max(0, startMonth.months(to: day.yearMonth))
    }

    // MARK: Instellen

    /// Zet de startdatum (en daarmee de startmaand). Bij een salaris om de zoveel weken of dagen zonder eigen ankerdatum volgde het
    /// anker de startmaand; dat wordt eerst vastgezet, zodat de uitbetalingen niet verschuiven.
    mutating func setStart(_ day: CalendarDay) {
        if !salary.isMonthly, salary.anchor == nil {
            salary.anchor = salaryAnchor()
        }
        startDay = day
        startMonth = day.yearMonth
    }

    /// De gegevens zoals een gewone maand ze ziet, voor SCHATTINGEN: een gedeeltelijke startmaand telt helemaal mee. Alleen de
    /// startdatum verandert (naar de eerste dag van de maand); de maandplannen (en dus de tussenopslag) blijven gedeeld.
    var forEstimates: FinanceData {
        guard let start = effectiveStartDay, start.day > 1 else { return self }
        var copy = self
        copy.startDay = CalendarDay(month: start.yearMonth, day: 1)
        return copy
    }

    // MARK: Beginsaldo

    /// Het moment van een beginsaldo op `day`: in de dag zelf en zo dicht mogelijk bij `now`. Een dag in het verleden krijgt het
    /// laatste moment van die dag (het saldo is dan het saldo aan het eind van de dag, zoals de rest van de app dat toont), vandaag
    /// krijgt `now` (het saldo is meteen bekend) en een dag in de toekomst het begin van die dag (zodra de dag begint is het saldo er).
    static func openingMoment(on day: CalendarDay, now: Date) -> Date {
        let calendar = YearMonth.calendar
        let dayStart = calendar.startOfDay(for: day.date(calendar: calendar))
        let dayEnd = DayMath.lastMoment(before: DayMath.nextDayStart(after: dayStart, calendar: calendar))
        return min(max(dayStart, now), dayEnd)
    }

    /// Zet het beginsaldo op `day`: `bank` is het banksaldo en `pots` het saldo per spaarpot, beide zoals ze AAN HET EIND van die
    /// dag staan, met alles wat die dag al gebeurd is (de geplande boekingen van die dag zitten er dus in). nil laat de bank
    /// ongemoeid; een pot die niet in `pots` staat ook.
    ///
    /// De bank krijgt een ingevuld saldo met de notitie "Beginsaldo". Een spaarpot krijgt een boeking van het soort `.opening` van
    /// het verschil tussen het ingevulde saldo en wat de pot die dag al had zonder beginboeking; is er geen verschil, dan komt er
    /// niets bij. Aanroepen met dezelfde waarden verandert daarna niets meer: het saldo en de boekingen "Beginsaldo" van die dag
    /// worden vervangen, nooit opgeteld.
    mutating func setOpeningBalances(on day: CalendarDay, bank: Double?, pots balances: [UUID: Double], now: Date = Date()) {
        let calendar = YearMonth.calendar
        let moment = FinanceData.openingMoment(on: day, now: now)
        func isOnDay(_ date: Date) -> Bool {
            CalendarDay(date: date, calendar: calendar) == day
        }
        if let bank {
            bankSnapshots.removeAll { $0.note == FinanceData.openingNote && isOnDay($0.date) }
            bankSnapshots.append(BankSnapshot(date: moment, balance: bank.cents, note: FinanceData.openingNote))
        }
        let ids = pots.map { $0.id }.filter { balances[$0] != nil }
        for id in ids {
            guard let typed = balances[id] else { continue }
            potEntries.removeAll { $0.potID == id && $0.kind == .opening && isOnDay($0.date) }
            // Wat de pot aan het eind van die dag al heeft zonder beginboeking van die dag.
            let reference = CentsMath.int(potBalance(id, asOf: day.date(calendar: calendar)))
            let difference = CentsMath.int(typed) - reference
            if difference != 0 {
                potEntries.append(PotEntry(potID: id, date: moment, amount: CentsMath.value(difference), kind: .opening, note: ""))
            }
        }
    }

    /// De notitie bij het ingevulde banksaldo van een beginsaldo.
    static let openingNote = "Beginsaldo"

    /// De datum van de beginboeking van een nieuwe spaarpot: `now`, maar niet vóór het begin van de startdag (anders telde zij niet
    /// mee en bleef de pot leeg). Zonder startdatum precies `now`.
    func openingEntryDate(now: Date) -> Date {
        guard let cutoff = startCutoff else { return now }
        return max(now, cutoff)
    }
}
