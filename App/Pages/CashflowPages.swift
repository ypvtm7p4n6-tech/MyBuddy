import SwiftUI
import Charts

// MARK: - Logica van de dagschermen (zonder SwiftUI)
//
// Alles tussen "BEGIN LOGICA" en "EINDE LOGICA" is Foundation-only en leest alleen uit de dagboekhouding van de
// rekenmotor (`MonthLedger` en `DayTotals`, zie Ledger.swift). Er wordt hier geen bedrag zelf uitgerekend: de
// schermen tonen wat de motor levert, zodat Overzicht, "Nog te verdelen", spaarpotten, bankrekening en dagen
// precies dezelfde cijfers hebben. Alleen waar een bedrag uit twee motorwaarden samengesteld wordt (bijvoorbeeld
// "overgeschreven" = spaarpotten + beleggingen) of waar een verschil getoond moet worden (de controle), gebeurt dat
// in hele centen (`CentsMath`) en staat het hieronder uitgelegd.

// BEGIN LOGICA

// MARK: - Dagen in woorden

/// Korte Nederlandse teksten voor dagen en datums ("de 25e", "ma 25 okt").
enum DayText {
    static let weekdays = ["zo", "ma", "di", "wo", "do", "vr", "za"]

    /// "de 25e"
    static func ordinal(_ day: Int) -> String {
        "de \(day)e"
    }

    /// "25 okt"
    static func short(_ date: Date) -> String {
        let cal = YearMonth.calendar
        let number = cal.component(.day, from: date)
        return "\(number) \(Fmt.shortMonth(YearMonth(date: date, calendar: cal)))"
    }

    /// "ma 25 okt"
    static func weekdayShort(_ date: Date) -> String {
        let cal = YearMonth.calendar
        let weekday = cal.component(.weekday, from: date) // 1 = zondag
        let name = weekdays[min(max(weekday - 1, 0), 6)]
        return "\(name) \(short(date))"
    }

    /// "Vakantie", "Vakantie en Fun", "Vakantie, Fun en Auto"
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " en " + names[names.count - 1]
        }
    }

    /// Valt `date` op dezelfde kalenderdag als `other`?
    static func isSameDay(_ date: Date, _ other: Date) -> Bool {
        YearMonth.calendar.isDate(date, inSameDayAs: other)
    }
}

/// Bedragen met teken, voor regels en tegels, en telwoorden.
enum CashflowText {
    /// "+ € 3.000", "− € 1.000" of "€ 0" (zonder teken bij nul).
    static func signed(_ amount: Double) -> String {
        let sign = amount > 0 ? "+ " : (amount < 0 ? "− " : "")
        return sign + Fmt.euro(abs(amount))
    }

    /// "1 dag", "12 dagen".
    static func days(_ count: Int) -> String {
        count == 1 ? "1 dag" : "\(count) dagen"
    }
}

/// Houdt de dagboekhouding van de maanden bij die één scherm nodig heeft, zodat elke maand per berekening maar één keer
/// wordt uitgerekend (`monthLedger` kost enkele milliseconden; per dag aanroepen is veel duurder). Maak er één per `body`.
final class LedgerBook {
    let data: FinanceData
    let today: Date
    private var cache: [YearMonth: MonthLedger] = [:]

    init(_ data: FinanceData, today: Date) {
        self.data = data
        self.today = today
    }

    /// De dagboekhouding van een maand.
    func ledger(_ month: YearMonth) -> MonthLedger {
        if let known = cache[month] { return known }
        let made = data.monthLedger(month, asOf: today)
        cache[month] = made
        return made
    }

    /// De cijfers van de kalenderdag waar `date` in valt.
    func day(_ date: Date) -> DayTotals {
        let cal = YearMonth.calendar
        let list = ledger(YearMonth(date: date, calendar: cal))
        let number = DayMath.dayNumber(of: date, calendar: cal)
        return list.days[min(max(number, 1), list.days.count) - 1]
    }

    /// De dagen van `from` t/m `to` (maximaal 800), ook over maandgrenzen heen. Elke dag heeft zijn cijfers uit de
    /// dagboekhouding van zijn eigen maand.
    func days(from: Date, to: Date, limit: Int = 800) -> [DayTotals] {
        let cal = YearMonth.calendar
        let first = cal.startOfDay(for: from)
        let last = cal.startOfDay(for: to)
        guard last >= first else { return [] }
        var result: [DayTotals] = []
        var month = YearMonth(date: first, calendar: cal)
        let lastMonth = YearMonth(date: last, calendar: cal)
        while month <= lastMonth && result.count < limit {
            for day in ledger(month).days {
                let start = cal.startOfDay(for: day.date)
                guard start >= first && start <= last else { continue }
                result.append(day)
                if result.count >= limit { break }
            }
            month = month.adding(1)
        }
        return result
    }
}

extension DayTotals {
    /// Wat er die dag naar spaarpotten en beleggingen samen gaat, in hele centen opgeteld uit `toPots` en `toHoldings`.
    /// Negatief als er die dag meer van een spaarpot terug naar de bank gaat dan erheen.
    var totalTransferred: Double {
        CentsMath.value(CentsMath.add(CentsMath.int(toPots), CentsMath.int(toHoldings)))
    }
}

extension MonthLedger {
    /// Het aantal salarisuitbetalingen in de maand (meer dan één bij een schema om de zoveel weken of dagen).
    var salaryPayoutCount: Int {
        days.reduce(0) { total, day in total + day.events.filter { $0.kind == .salary }.count }
    }
}

/// Het laagste dagsaldo uit een rij dagen.
enum CashflowLowPoint {
    /// De dag met het laagste bekende saldo (bij gelijke saldi de eerste). nil als geen enkele dag een saldo heeft.
    static func lowest(in days: [DayTotals]) -> DayTotals? {
        var best: DayTotals?
        var bestBalance = 0.0
        for day in days {
            guard let balance = day.bankBalance else { continue }
            if best == nil || balance < bestBalance {
                best = day
                bestBalance = balance
            }
        }
        return best
    }
}

/// Welke dagen de lijst toont.
enum CashflowDayFilter: String, CaseIterable, Identifiable {
    case all, withEntries
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Alle dagen"
        case .withEntries: return "Alleen met boekingen"
        }
    }

    /// De dagen van de maand die erbij horen. Vandaag blijft er altijd bij: daar scrolt de lijst naartoe en het saldo
    /// van vandaag wil je kunnen zien.
    func days(of ledger: MonthLedger) -> [DayTotals] {
        switch self {
        case .all: return ledger.days
        case .withEntries: return ledger.days.filter { $0.hasActivity || $0.isToday }
        }
    }
}

/// Waar de lijst naartoe scrolt.
enum CashflowScroll {
    /// De dag van vandaag als die in deze maand valt, anders nil (dan scrolt de lijst nergens naartoe). Dit is ook het
    /// id van de kaart van die dag in de lijst.
    static func todayTarget(in ledger: MonthLedger) -> Int? {
        ledger.days.first(where: { $0.isToday })?.day
    }
}

// MARK: Sluitende regels

/// Eén regel in een sluitend overzicht van de maand (bankrekening of spaarpotten). `effectCents` is wat de regel met het
/// saldo doet, met teken (nul voor begin, eind en detailregels): begin + alle effecten = eind. Zo laat de test zien dat
/// het getoonde overzicht echt sluit, ook met handmatige boekingen en een ingevuld saldo.
struct CashflowRow: Identifiable, Equatable {
    enum Kind: String {
        case begin, inflow, inflowPlan, inflowManual, outflow, outflowPlan, outflowManual
        case toPots, toPotsPlan, toPotsManual, toHoldings, correction, end
        case potsPlan, potsManual, interest, paidFromPots
    }

    enum Style { case line, detail, total }
    enum Tone { case neutral, positive, negative, accent }

    var kind: Kind
    var title: String
    /// "+", "−", "±", "=" of leeg.
    var sign: String
    /// Het bedrag zoals het getoond wordt. nil = onbekend.
    var amount: Double?
    /// Toont het bedrag met een plus of min (voor regels die ook negatief kunnen zijn).
    var showsSign = false
    var note: String?
    var style: Style = .line
    var tone: Tone = .neutral
    var effectCents = 0

    var id: String { kind.rawValue }
}

/// De regels van het maandoverzicht, rechtstreeks uit `MonthLedger`.
enum CashflowSummary {
    /// Een regel die geld laat bewegen: het teken volgt het effect op het saldo (`zeroSign` bij nul).
    private static func movement(_ kind: CashflowRow.Kind, _ title: String, effect: Int, zeroSign: String,
                                 tone: CashflowRow.Tone, note: String? = nil) -> CashflowRow {
        let sign = effect > 0 ? "+" : (effect < 0 ? "−" : zeroSign)
        return CashflowRow(kind: kind, title: title, sign: sign, amount: CentsMath.value(abs(effect)), note: note,
                           tone: tone, effectCents: effect)
    }

    /// De bankrekening van de maand: begin, binnen, eruit, overgeschreven naar spaarpotten en beleggingen, het verschil met
    /// een ingevuld saldo, eind. Handmatige stortingen, opnames en overboekingen staan apart bij elke regel als ze er zijn.
    static func bankRows(_ l: MonthLedger) -> [CashflowRow] {
        var rows: [CashflowRow] = []
        rows.append(CashflowRow(kind: .begin, title: "Begin van de maand", sign: "", amount: l.openingBank, style: .total))

        let payouts = l.salaryPayoutCount
        rows.append(movement(.inflow, "Binnen", effect: CentsMath.int(l.inflow), zeroSign: "+", tone: .positive,
                             note: payouts > 1 ? "Met \(payouts) salarisuitbetalingen" : nil))
        if CentsMath.int(l.manualInflow) != 0 {
            rows.append(CashflowRow(kind: .inflowPlan, title: "Salaris en inkomsten", sign: "", amount: l.planInflow, style: .detail))
            rows.append(CashflowRow(kind: .inflowManual, title: "Handmatig gestort", sign: "", amount: l.manualInflow, style: .detail))
        }

        rows.append(movement(.outflow, "Eruit", effect: -CentsMath.int(l.outflow), zeroSign: "−", tone: .negative))
        if CentsMath.int(l.manualOutflow) != 0 {
            rows.append(CashflowRow(kind: .outflowPlan, title: "Uitgaven van je rekening", sign: "", amount: l.planOutflow, style: .detail))
            rows.append(CashflowRow(kind: .outflowManual, title: "Handmatig opgenomen", sign: "", amount: l.manualOutflow, style: .detail))
        }

        // Meer terug van de spaarpotten dan erheen: dan komt er netto geld bij op de bankrekening.
        let toPots = CentsMath.int(l.toPots)
        if toPots != 0 || CentsMath.int(l.planToPots) != 0 || CentsMath.int(l.manualToPots) != 0 {
            let back = toPots < 0
            rows.append(movement(.toPots, back ? "Teruggeboekt van spaarpotten" : "Overgeschreven naar spaarpotten",
                                 effect: -toPots, zeroSign: "−", tone: .accent))
            if CentsMath.int(l.manualToPots) != 0 {
                rows.append(CashflowRow(kind: .toPotsPlan, title: "Maandverdeling", sign: "", amount: l.planToPots, style: .detail))
                rows.append(CashflowRow(kind: .toPotsManual, title: "Handmatig overgeboekt", sign: "", amount: l.manualToPots,
                                        showsSign: true, style: .detail))
            }
        }

        let toHoldings = CentsMath.int(l.toHoldings)
        if toHoldings != 0 {
            rows.append(movement(.toHoldings, toHoldings < 0 ? "Teruggeboekt van beleggingen" : "Overgeschreven naar beleggingen",
                                 effect: -toHoldings, zeroSign: "−", tone: .accent))
        }

        let correction = CentsMath.int(l.bankCorrections)
        if correction != 0 {
            rows.append(CashflowRow(kind: .correction, title: "Verschil met je ingevulde saldo", sign: "±", amount: l.bankCorrections,
                                    showsSign: true, note: "Je vulde een saldo in dat afweek van wat de app verwachtte.",
                                    effectCents: correction))
        }

        rows.append(CashflowRow(kind: .end, title: "Eind van de maand", sign: "=", amount: l.closingBank, style: .total))
        return rows
    }

    /// De spaarpotten van de maand: begin, inleg, handmatige boekingen, rente, betaald uit potten, eind.
    static func potsRows(_ l: MonthLedger) -> [CashflowRow] {
        var rows: [CashflowRow] = []
        rows.append(CashflowRow(kind: .begin, title: "Begin van de maand", sign: "", amount: l.openingPots, style: .total))

        let plan = CentsMath.int(l.planToPots)
        if plan != 0 {
            rows.append(movement(.potsPlan, "Inleg volgens je verdeling", effect: plan, zeroSign: "+", tone: .accent))
        }
        let manual = CentsMath.int(l.potEntriesNet)
        if manual != 0 {
            rows.append(CashflowRow(kind: .potsManual, title: "Handmatige boekingen", sign: "±", amount: l.potEntriesNet,
                                    showsSign: true, note: "Stortingen, opnames en overboekingen die je zelf deed.",
                                    effectCents: manual))
        }
        let interest = CentsMath.int(l.interest)
        if interest != 0 {
            rows.append(movement(.interest, "Rente", effect: interest, zeroSign: "+", tone: .positive))
        }
        let paid = CentsMath.int(l.paidFromPots)
        if paid != 0 {
            rows.append(movement(.paidFromPots, "Betaald uit potten", effect: -paid, zeroSign: "−", tone: .negative))
        }

        rows.append(CashflowRow(kind: .end, title: "Eind van de maand", sign: "=", amount: l.closingPots, style: .total))
        return rows
    }
}

// MARK: Controle

/// De controle "klopt het met je overzicht?". Is alles in orde (`MonthLedger.allReconciles`), dan zijn er geen
/// meldingen. Anders staat er per afwijking een Nederlandse zin met het verschil, zodat de gebruiker ziet waar het zit.
struct LedgerCheck: Equatable {
    struct Issue: Identifiable, Equatable {
        let id: String
        let text: String
    }

    let issues: [Issue]
    var isOK: Bool { issues.isEmpty }

    init(_ ledger: MonthLedger) {
        var found: [Issue] = []
        if !ledger.bankReconciles { found.append(contentsOf: LedgerCheck.bankIssues(ledger)) }
        if !ledger.potsReconciles { found.append(contentsOf: LedgerCheck.potsIssues(ledger)) }
        if !ledger.overviewReconciles { found.append(contentsOf: LedgerCheck.overviewIssues(ledger)) }
        issues = found
    }

    /// Een verschil in centen als bedrag zonder teken.
    private static func text(_ cents: Int) -> String {
        Fmt.euroExact(CentsMath.value(abs(cents)))
    }

    private static func bankIssues(_ l: MonthLedger) -> [Issue] {
        var out: [Issue] = []
        if let opening = l.openingBank, let closing = l.closingBank {
            var expected = CentsMath.int(opening)
            expected = CentsMath.add(expected, CentsMath.int(l.inflow))
            expected = CentsMath.add(expected, -CentsMath.int(l.outflow))
            expected = CentsMath.add(expected, -CentsMath.int(l.toPots))
            expected = CentsMath.add(expected, -CentsMath.int(l.toHoldings))
            expected = CentsMath.add(expected, CentsMath.int(l.bankCorrections))
            let difference = CentsMath.int(closing) - expected
            if difference != 0 {
                out.append(Issue(id: "bank-month",
                                 text: "Bankrekening: het eindsaldo wijkt \(text(difference)) af van begin + binnen − eruit − overgeschreven."))
            }
        }
        if let day = l.days.first(where: { !$0.bankReconciles }),
           let before = day.openingBank, let after = day.bankBalance {
            let expected = CentsMath.add(CentsMath.int(before), CentsMath.int(day.bankChange))
            let difference = CentsMath.int(after) - expected
            out.append(Issue(id: "bank-day-\(day.day)",
                             text: "Bankrekening op \(DayText.weekdayShort(day.date)): het saldo wijkt \(text(difference)) af van het saldo van de dag ervoor plus wat er die dag binnenkwam en eruit ging."))
        }
        if out.isEmpty {
            out.append(Issue(id: "bank", text: "Het saldo van je bankrekening sluit niet met de cijfers van deze maand."))
        }
        return out
    }

    private static func potsIssues(_ l: MonthLedger) -> [Issue] {
        var out: [Issue] = []
        var expected = CentsMath.int(l.openingPots)
        expected = CentsMath.add(expected, CentsMath.int(l.planToPots))
        expected = CentsMath.add(expected, CentsMath.int(l.potEntriesNet))
        expected = CentsMath.add(expected, CentsMath.int(l.interest))
        expected = CentsMath.add(expected, -CentsMath.int(l.paidFromPots))
        let difference = CentsMath.int(l.closingPots) - expected
        if difference != 0 {
            out.append(Issue(id: "pots-month",
                             text: "Spaarpotten: het eindsaldo wijkt \(text(difference)) af van begin + inleg + rente − betaald uit potten."))
        }
        if let day = l.days.first(where: { !$0.potsReconciles }) {
            let dayExpected = CentsMath.add(CentsMath.int(day.openingPots), CentsMath.int(day.potsChange))
            let dayDifference = CentsMath.int(day.potsTotal) - dayExpected
            out.append(Issue(id: "pots-day-\(day.day)",
                             text: "Spaarpotten op \(DayText.weekdayShort(day.date)): het totaal wijkt \(text(dayDifference)) af van het totaal van de dag ervoor plus wat er die dag bijkwam en afging."))
        }
        if out.isEmpty {
            out.append(Issue(id: "pots", text: "Het totaal van je spaarpotten sluit niet met de cijfers van deze maand."))
        }
        return out
    }

    private static func overviewIssues(_ l: MonthLedger) -> [Issue] {
        var out: [Issue] = []
        func compare(_ title: String, overview: Double, days: Double) {
            let a = CentsMath.int(overview)
            let b = CentsMath.int(days)
            guard a != b else { return }
            out.append(Issue(id: "overview-\(title)",
                             text: "\(title): overzicht \(Fmt.euroExact(overview)), dagen \(Fmt.euroExact(days)) (verschil \(text(a - b)))."))
        }
        compare("Inkomen", overview: l.income, days: l.planInflow)
        compare("Uitgaven van je rekening", overview: l.expensesFromBank, days: l.planOutflow)
        compare("Uitgaven uit spaarpotten", overview: l.expensesFromPots, days: l.paidFromPots)
        compare("Gespaard", overview: l.saved, days: l.planToPots)
        compare("Belegd", overview: l.invested, days: l.toHoldings)
        var remaining = CentsMath.int(l.planInflow)
        remaining = CentsMath.add(remaining, -CentsMath.int(l.planOutflow))
        remaining = CentsMath.add(remaining, -CentsMath.int(l.planToPots))
        remaining = CentsMath.add(remaining, -CentsMath.int(l.toHoldings))
        compare("Nog te verdelen", overview: l.remaining, days: CentsMath.value(remaining))
        if let last = l.days.last {
            compare("Nog te verdelen op de laatste dag", overview: l.remaining, days: last.remainingSoFar)
        }
        if out.isEmpty {
            out.append(Issue(id: "overview", text: "De dagen sluiten niet met het overzicht van deze maand."))
        }
        return out
    }
}

/// De regels van een maand op id, om een tik op een gebeurtenis naar de juiste regel te brengen.
struct CashflowLineLookup {
    let income: [UUID: MoneyLine]
    let expenses: [UUID: MoneyLine]

    init(plan: MonthPlan) {
        income = Dictionary(plan.extraIncome.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        expenses = Dictionary(plan.expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: Grafiek en bereiken

/// Eén punt van de dagsaldo-grafiek.
struct DayChartItem: Identifiable, Equatable {
    let id: Date
    let value: Double
    let planned: Bool
    var date: Date { id }

    /// Punten voor de grafiek: de dagen met een bekend saldo, in de volgorde van `days`.
    static func items(from days: [DayTotals]) -> [DayChartItem] {
        days.compactMap { day -> DayChartItem? in
            guard let balance = day.bankBalance else { return nil }
            return DayChartItem(id: day.date, value: balance, planned: day.isPlanned)
        }
    }
}

/// Hoe ver de dagsaldo-grafiek kijkt: de komende 30 dagen of de gekozen maand.
enum DayChartRange: String, CaseIterable, Identifiable {
    case next30, month
    var id: String { rawValue }

    /// Van welke dag tot welke dag (beide meegerekend) de grafiek loopt.
    func window(focus: YearMonth, today: Date) -> (from: Date, to: Date) {
        let cal = YearMonth.calendar
        let todayStart = cal.startOfDay(for: today)
        switch self {
        case .next30:
            let end = cal.date(byAdding: .day, value: 29, to: todayStart) ?? todayStart
            return (todayStart, end)
        case .month:
            return (focus.firstDay, focus.date(day: focus.dayCount))
        }
    }
}

/// De dagen die je op de bankpagina kunt kiezen.
enum BankDayBounds {
    /// Vanaf de eerste dag van de startmaand van de gegevens tot twee jaar na vandaag. Zonder grens rekent elke body alle
    /// maanden vanaf het laatste saldo door (een datum in het jaar 3000 kost bijna een seconde), en zoiets ver vooruit
    /// zegt niets. Vandaag valt altijd binnen het bereik, ook als de startmaand (na een import) later ligt.
    static func range(startMonth: YearMonth, today: Date) -> ClosedRange<Date> {
        let cal = YearMonth.calendar
        let upper = cal.date(byAdding: .year, value: 2, to: today) ?? today
        let lower = min(startMonth.firstDay, cal.startOfDay(for: today))
        return lower...max(lower, upper)
    }

    static func clamp(_ value: Date, to range: ClosedRange<Date>) -> Date {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: Waarschuwing: onder nul of onder de buffer

/// Het bereik waarin de waarschuwing het laagste saldo zoekt. Voor de huidige maand vanaf vandaag (een dip in het verleden
/// verbergt dan geen dip die nog komt) en 30 dagen vooruit, dus ook over de maandwisseling heen. Voor andere maanden de
/// hele maand.
enum BankLowPointWindow {
    static func range(for month: YearMonth, current: YearMonth, today: Date) -> (from: Date, to: Date) {
        let cal = YearMonth.calendar
        let monthEnd = month.date(day: month.dayCount)
        guard month == current else { return (month.firstDay, monthEnd) }
        let todayStart = cal.startOfDay(for: today)
        let ahead = cal.date(byAdding: .day, value: 30, to: todayStart) ?? todayStart
        return (todayStart, max(monthEnd, ahead))
    }
}

/// De tekst van de waarschuwing bij het laagste dagsaldo. nil als alles in orde is.
struct BankLowPointNote: Equatable {
    let text: String
    let severe: Bool

    /// - Parameters:
    ///   - low: de dag met het laagste saldo (uit de dagboekhouding, dus hetzelfde saldo als op de dagkaarten).
    ///   - buffer: de gewenste buffer op de bankrekening.
    ///   - balanceNow: het saldo van nu, nil als dat niet bekend is.
    static func make(low: DayTotals, buffer: Double, balanceNow: Double?, today: Date) -> BankLowPointNote? {
        guard let lowBalance = low.bankBalance else { return nil }
        let cal = YearMonth.calendar
        let past = cal.startOfDay(for: low.date) < cal.startOfDay(for: today)
        let isToday = DayText.isSameDay(low.date, today)
        let day = DayText.weekdayShort(low.date)
        let balance = Fmt.euro(lowBalance)
        if lowBalance < 0 {
            if past {
                return BankLowPointNote(text: "Op \(day) stond je saldo onder nul (\(balance)).", severe: true)
            }
            let when = isToday ? "vandaag" : "op \(day)"
            return BankLowPointNote(text: "Let op: \(when) staat je saldo onder nul (\(balance)). Kijk of je een uitgave of overschrijving naar een andere dag kunt zetten.",
                                    severe: true)
        }
        // De buffermelding is bedoeld voor een dip die je plan veroorzaakt. Zit je nu al onder je buffer,
        // dan zie je dat bij het blok Buffer en blijft deze balk weg, zodat de melding "onder nul" opvalt.
        // Is het saldo van nu niet bekend, dan is er niets om mee te vergelijken en blijft de melding ook weg.
        if let now = balanceNow, buffer > 0 && lowBalance < buffer && now >= buffer && !past {
            let start = isToday ? "Vandaag" : "Op \(day)"
            return BankLowPointNote(text: "\(start) zakt je saldo naar \(balance). Dat is onder je gewenste buffer van \(Fmt.euro(buffer)).",
                                    severe: false)
        }
        return nil
    }
}

// EINDE LOGICA

// MARK: - Een gebeurtenis in beeld

/// Hoe een gebeurtenis eruitziet: icoon, kleur en bedrag. Inkomen en rente groen, uitgaven rood,
/// overschrijvingen naar potten en beleggingen olijf.
struct DayEventStyle {
    let symbol: String
    let color: Color
    let kindText: String
    let amount: Double

    init(_ event: DayEvent) {
        let shown = event.bankAmount != 0 ? event.bankAmount : event.potAmount
        amount = shown
        switch event.kind {
        case .salary:
            symbol = "briefcase.fill"
            color = Theme.positive
            kindText = "Salaris"
        case .income:
            symbol = "plus.circle.fill"
            color = Theme.positive
            kindText = "Inkomsten"
        case .expense:
            let fromPotOnly = event.bankAmount == 0 && event.potAmount != 0
            symbol = fromPotOnly ? "tray.full.fill" : "minus.circle.fill"
            color = Theme.negative
            kindText = fromPotOnly ? "Uitgave uit spaarpot" : "Uitgave"
        case .toPot:
            symbol = "tray.and.arrow.down.fill"
            color = Theme.accent
            kindText = "Overschrijving naar spaarpot"
        case .toHolding:
            symbol = "chart.line.uptrend.xyaxis"
            color = Theme.accent
            kindText = "Overschrijving naar belegging"
        case .interest:
            symbol = "percent"
            color = Theme.positive
            kindText = "Rente op spaarpot"
        case .bankEntry:
            symbol = "building.columns.fill"
            color = shown < 0 ? Theme.negative : (shown > 0 ? Theme.positive : Theme.accent)
            kindText = "Boeking op je rekening"
        }
    }

    /// "+ € 3.000" of "− € 1.000"
    var amountText: String {
        CashflowText.signed(amount)
    }
}

/// Eén regel met een gebeurtenis: icoon, titel, soort en bedrag. Geplande gebeurtenissen zijn iets lichter.
/// Met `showsDate` staat de datum bij de soort (voor salaris dat vaker dan eens per maand binnenkomt).
struct DayEventRow: View {
    let event: DayEvent
    var showsDate = false
    var showsChevron = false

    private var caption: String {
        var parts = [DayEventStyle(event).kindText]
        if showsDate { parts.append(DayText.short(event.date)) }
        if event.isPlanned { parts.append("gepland") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let style = DayEventStyle(event)
        HStack(spacing: 10) {
            SymbolBadge(symbol: style.symbol, color: style.color, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(style.amountText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(style.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: style.amountText)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(event.isPlanned ? 0.8 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - De cijfers van één dag

/// Eén regel met een omschrijving links en een bedrag rechts (saldo's op een dag).
private struct DayValueRow: View {
    let title: String
    var caption: String? = nil
    let text: String
    var color: Color = .primary
    var bold = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(text)
                .font(Font.subheadline.weight(bold ? .bold : .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: text)
        }
    }
}

/// Een kleine tegel met een titel en een bedrag.
private struct DayFigureTile: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .animation(Theme.motion, value: text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .tile()
        .accessibilityElement(children: .combine)
    }
}

/// Binnen, eruit en overgeschreven van één dag. Het teken laat zien welke kant het opgaat; "Overgeschreven" staat er alleen
/// als er die dag iets naar spaarpotten of beleggingen gaat (of terug naar de bank).
struct DayFlowTiles: View {
    let day: DayTotals

    var body: some View {
        let moved = day.totalTransferred
        HStack(spacing: 8) {
            DayFigureTile(title: "Binnen", text: CashflowText.signed(day.inflow),
                          color: day.inflow > 0 ? Theme.positive : Color.secondary)
            DayFigureTile(title: "Eruit", text: CashflowText.signed(-day.outflow),
                          color: day.outflow > 0 ? Theme.negative : Color.secondary)
            if moved != 0 {
                DayFigureTile(title: moved > 0 ? "Overgeschreven" : "Teruggeboekt",
                              text: Fmt.euro(abs(moved)), color: Theme.accent)
            }
        }
    }
}

/// Het saldo van de bankrekening en van de spaarpotten aan het eind van een dag, en wat er die dag nog te verdelen is.
/// Precies de waarden van `DayTotals`, op de kaart van de dag en in het blok "Per dag" op de bankpagina. Bij het saldo staat
/// ook het saldo aan het begin van de dag, zodat de dag sluit: begin + binnen − eruit − overgeschreven = eind.
struct DayBalanceRows: View {
    let day: DayTotals
    var showsBank = true
    var showsPots = true
    var showsRemaining = true

    private func caption(opening: Double?) -> String {
        guard let opening else { return "Aan het eind van de dag" }
        return "Aan het eind van de dag · begin \(Fmt.euro(opening))"
    }

    var body: some View {
        VStack(spacing: 8) {
            if showsBank {
                if let balance = day.bankBalance {
                    DayValueRow(title: "Saldo bankrekening", caption: caption(opening: day.openingBank), text: Fmt.euro(balance),
                                color: balance < 0 ? Theme.negative : Color.primary, bold: true)
                } else {
                    DayValueRow(title: "Saldo bankrekening", text: "onbekend", color: Color.secondary)
                }
            }
            if let measured = day.measuredBalance {
                DayValueRow(title: "Saldo dat je invulde", caption: "Zo vulde je het zelf in voor deze dag",
                            text: Fmt.euro(measured))
                if day.bankCorrection != 0 {
                    DayValueRow(title: "Verschil met wat de app verwachtte", text: CashflowText.signed(day.bankCorrection),
                                color: day.bankCorrection < 0 ? Theme.negative : Theme.positive)
                }
            }
            if showsPots {
                DayValueRow(title: "Spaarpotten totaal", caption: caption(opening: day.openingPots), text: Fmt.euro(day.potsTotal))
                if day.potEntriesNet != 0 {
                    DayValueRow(title: "Handmatig op spaarpotten", text: CashflowText.signed(day.potEntriesNet))
                }
            }
            if showsRemaining {
                DayValueRow(title: "Nog te verdelen", caption: "Deze maand, t/m deze dag", text: Fmt.euro(day.remainingSoFar),
                            color: day.remainingSoFar < 0 ? Theme.negative : Color.primary)
            }
        }
    }
}

// MARK: - Grafiek van het dagsaldo

/// Lijn met vlak eronder voor het saldo aan het eind van elke dag. Geplande dagen (na vandaag) staan gestippeld en lichter,
/// de nulstreep is rood gestippeld. Een gekozen dag krijgt een stip. De punten zijn de dagen uit de dagboekhouding,
/// dus dezelfde saldi als op de dagkaarten.
struct DayBalanceChart: View {
    let days: [DayTotals]
    var selected: Date? = nil
    var height: CGFloat = 190

    var body: some View {
        let items = DayChartItem.items(from: days)
        let actual = items.filter { !$0.planned }
        let bridge: [DayChartItem] = actual.last.map { [$0] } ?? []
        let future = bridge + items.filter { $0.planned }
        let lowest = items.min(by: { $0.value < $1.value })
        let chosen: DayChartItem? = selected.flatMap { day in
            items.first(where: { DayText.isSameDay($0.date, day) })
        }
        // De hoogte volgt de saldi, met wat ruimte. Zo zie je het dagverloop ook bij een hoog saldo.
        // De nulstreep staat er alleen bij als nul binnen beeld valt.
        let lowValue = lowest?.value ?? 0
        let highValue = items.map { $0.value }.max() ?? 0
        let pad = max((highValue - lowValue) * 0.12, 50)
        let floorValue = lowValue - pad
        let ceilingValue = highValue + pad
        let showsZero = floorValue <= 0 && ceilingValue >= 0
        Chart {
            ForEach(items) { item in
                AreaMark(x: .value("Dag", item.date),
                         yStart: .value("Basis", floorValue),
                         yEnd: .value("Saldo", item.value))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.30), Theme.accent.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.linear)
            }
            ForEach(actual) { item in
                LineMark(x: .value("Dag", item.date), y: .value("Saldo", item.value),
                         series: .value("Soort", "Werkelijk"))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.linear)
            }
            if future.count > 1 {
                ForEach(future) { item in
                    LineMark(x: .value("Dag", item.date), y: .value("Saldo", item.value),
                             series: .value("Soort", "Verwacht"))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .interpolationMethod(.linear)
                }
            }
            if showsZero {
                RuleMark(y: .value("Nul", 0.0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.negative.opacity(0.7))
            }
            if let low = lowest, low.value < 0 {
                PointMark(x: .value("Dag", low.date), y: .value("Saldo", low.value))
                    .foregroundStyle(Theme.negative)
            }
            if let pick = chosen {
                PointMark(x: .value("Dag", pick.date), y: .value("Saldo", pick.value))
                    .foregroundStyle(Color.primary)
            }
        }
        .chartYScale(domain: floorValue...ceilingValue)
        .chartAxes(shown: true)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(DayText.short(date)).font(.caption2) }
                }
            }
        }
        .frame(height: height)
        .animation(Theme.motion, value: items)
        .accessibilityLabel("Grafiek van je banksaldo per dag")
    }
}

// MARK: - Waarschuwing: onder nul of onder de buffer

/// Meldt wanneer het dagsaldo onder nul komt (of onder de gewenste buffer), met de datum.
/// Voor de huidige maand kijkt hij vanaf vandaag (een dip in het verleden verbergt dan geen dip die nog komt)
/// en 30 dagen vooruit, dus ook over de maandwisseling heen. Voor andere maanden kijkt hij naar de hele maand.
/// De saldi komen uit de dagboekhouding, dezelfde als op de dagkaarten. Toont niets als alles in orde is.
struct BankLowPointNotice: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let today = store.today
        // Zonder een enkel meetpunt of boeking is er nergens een saldo: dan valt er niets te rekenen.
        if d.hasBankBalance {
            let book = LedgerBook(d, today: today)
            let window = BankLowPointWindow.range(for: month, current: store.now, today: today)
            if let low = CashflowLowPoint.lowest(in: book.days(from: window.from, to: window.to)),
               let note = BankLowPointNote.make(low: low,
                                                buffer: d.bankBuffer(current: store.now),
                                                balanceNow: d.bankBalanceNowIfKnown(current: store.now, today: today),
                                                today: today) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: note.severe ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(note.severe ? Theme.negative : Theme.warning)
                    Text(note.text)
                        .font(.footnote)
                        .foregroundStyle(note.severe ? Theme.negative : Color.primary)
                    Spacer(minLength: 0)
                }
                .padding(Theme.cardInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(tint: (note.severe ? Theme.negative : Theme.warning).opacity(0.22))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Bankrekening: per dag

/// Blok "Per dag" op de bankpagina: kies een datum en zie wat er die dag binnenkomt, eruit gaat en wordt overgeschreven,
/// het saldo van de bankrekening en de spaarpotten aan het eind van de dag, en wat er t/m die dag nog te verdelen is.
/// Dat zijn dezelfde `DayTotals` als op de pagina "Dag voor dag". Eronder een grafiek van het dagsaldo.
struct BankDayBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var date = Date()
    @State private var rangeChoice: DayChartRange?

    private var dayRange: ClosedRange<Date> {
        BankDayBounds.range(startMonth: store.data.startMonth, today: store.today)
    }

    private func clampedDay(_ value: Date) -> Date {
        BankDayBounds.clamp(value, to: dayRange)
    }

    /// De gekozen dag, met een korte animatie zodat saldo en gebeurtenissen niet hard omspringen.
    private var animatedDate: Binding<Date> {
        Binding<Date>(get: { date },
                      set: { newValue in withAnimation(Theme.quickMotion) { date = clampedDay(newValue) } })
    }

    private func shiftDay(_ amount: Int) {
        let cal = YearMonth.calendar
        withAnimation(Theme.quickMotion) {
            date = clampedDay(cal.date(byAdding: .day, value: amount, to: date) ?? date)
        }
    }

    var body: some View {
        let d = store.data
        let today = store.today
        let focus = router.focusMonth
        let book = LedgerBook(d, today: today)
        let defaultRange: DayChartRange = focus == store.now ? .next30 : .month
        let range = rangeChoice ?? defaultRange
        GlassBlock(title: "Per dag", symbol: "calendar",
                   subtitle: "Binnen, eruit en saldo op elke dag",
                   tint: Theme.olive.opacity(0.3)) {
            dayPicker(today: today)
            dayDetails(d, book: book)
            chartSection(book, range: range, defaultRange: defaultRange, focus: focus, today: today)
        }
        .onAppear {
            if focus != store.now { date = clampedDay(focus.date(day: 1)) }
        }
        .onChange(of: router.focusMonth) { _, newMonth in
            rangeChoice = nil
            withAnimation(Theme.quickMotion) {
                date = clampedDay(newMonth == store.now ? store.today : newMonth.date(day: 1))
            }
        }
    }

    // MARK: Onderdelen

    @ViewBuilder
    private func dayPicker(today: Date) -> some View {
        HStack {
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left").padding(8).contentShape(Rectangle())
            }
            .accessibilityLabel("Vorige dag")
            Spacer()
            DatePicker("Dag", selection: animatedDate, in: dayRange, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.locale, Fmt.locale)
            Spacer()
            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right").padding(8).contentShape(Rectangle())
            }
            .accessibilityLabel("Volgende dag")
        }
        .buttonStyle(.plain)
        if !DayText.isSameDay(date, today) {
            ChipButton(title: "Terug naar vandaag", symbol: "arrow.uturn.backward") {
                withAnimation(Theme.quickMotion) { date = today }
            }
        }
    }

    @ViewBuilder
    private func dayDetails(_ d: FinanceData, book: LedgerBook) -> some View {
        let totals = book.day(date)
        let multipleSalaries = book.ledger(YearMonth(date: date)).salaryPayoutCount > 1
        VStack(alignment: .leading, spacing: 2) {
            Text("Saldo aan het eind van \(totals.isToday ? "vandaag" : DayText.weekdayShort(date))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let balance = totals.bankBalance {
                BigAmount(value: balance, font: .system(.title, design: .rounded, weight: .bold),
                          color: balance < 0 ? Theme.negative : Color.primary)
            } else {
                Text("Op deze dag is je saldo nog niet bekend.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if totals.isPlanned {
                Text("Verwacht: deze dag ligt nog voor je.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        DayFlowTiles(day: totals)
        if totals.events.isEmpty {
            Text("Op deze dag komt er niets binnen en gaat er niets weg.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(totals.events) { event in
                    DayEventRow(event: event, showsDate: multipleSalaries && event.kind == .salary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(10)
            .tile()
        }
        DayBalanceRows(day: totals, showsBank: false, showsPots: !d.pots.isEmpty)
        if !d.hasBankBalance {
            Text("Vul je saldo in of zet er geld op. Dan zie je per dag hoeveel je hebt, ook voor dagen die nog komen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func chartSection(_ book: LedgerBook, range: DayChartRange, defaultRange: DayChartRange,
                              focus: YearMonth, today: Date) -> some View {
        let span = range.window(focus: focus, today: today)
        let days = book.days(from: span.from, to: span.to).filter { $0.bankBalance != nil }
        let lowest = CashflowLowPoint.lowest(in: days)
        Divider()
        Text("Saldo per dag")
            .font(.subheadline.weight(.semibold))
        Picker("Periode van de grafiek", selection: Binding(get: { rangeChoice ?? defaultRange },
                                                           set: { rangeChoice = $0 })) {
            Text("Komende 30 dagen").tag(DayChartRange.next30)
            Text(Fmt.month(focus)).tag(DayChartRange.month)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        if days.count > 1 {
            DayBalanceChart(days: days, selected: date)
            if let low = lowest, let lowBalance = low.bankBalance, let end = days.last, let endBalance = end.bankBalance {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    StatTile(title: "Laagste saldo", value: Fmt.euro(lowBalance),
                             color: lowBalance < 0 ? Theme.negative : Color.primary,
                             caption: DayText.short(low.date))
                    StatTile(title: "Saldo op het eind", value: Fmt.euro(endBalance),
                             color: endBalance < 0 ? Theme.negative : Color.primary,
                             caption: DayText.short(end.date))
                }
            }
            Text("Gestippeld en lichter is gepland. De rode stippellijn is nul.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Voor deze periode is je saldo nog niet bekend.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bankrekening: komende 14 dagen

/// Wat er de komende 14 dagen gebeurt, dag voor dag, met het saldo aan het eind van elke dag (uit de dagboekhouding).
struct BankUpcomingBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let d = store.data
        let today = store.today
        let cal = YearMonth.calendar
        let start = cal.startOfDay(for: today)
        let end = cal.date(byAdding: .day, value: 13, to: start) ?? start
        let book = LedgerBook(d, today: today)
        let busy = book.days(from: start, to: end).filter { !$0.events.isEmpty }
        GlassBlock(title: "Komende 14 dagen", symbol: "calendar.badge.clock",
                   subtitle: "\(DayText.short(start)) t/m \(DayText.short(end))") {
            if busy.isEmpty {
                Text("De komende 14 dagen komt er niets binnen en gaat er niets weg.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(busy) { day in
                        UpcomingDayRow(day: day)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        if day.id != busy.last?.id { Divider() }
                    }
                }
            }
            if !d.hasBankBalance {
                Text("Vul je saldo in om ook het saldo per dag te zien.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ChipButton(title: "Alle dagen bekijken", symbol: "calendar") {
                // Het pad van de tab waar je nu bent, zodat "terug" bij deze pagina uitkomt.
                router.open(.cashflow)
            }
        }
    }
}

/// Eén dag in de lijst "Komende 14 dagen": datum, saldo aan het eind van de dag en de gebeurtenissen.
struct UpcomingDayRow: View {
    let day: DayTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(DayText.weekdayShort(day.date)).font(.subheadline.weight(.semibold))
                    if day.isToday { Text("Vandaag").font(.caption).foregroundStyle(Theme.accent) }
                }
                Spacer(minLength: 8)
                if let balance = day.bankBalance {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Saldo").font(.caption2).foregroundStyle(.secondary)
                        Text(Fmt.euro(balance))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(balance < 0 ? Theme.negative : Color.primary)
                            .contentTransition(.numericText())
                            .animation(Theme.motion, value: balance)
                    }
                }
            }
            ForEach(day.events) { event in
                DayEventRow(event: event)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Dag voor dag: de maand in cijfers

/// Een regel in een sluitend overzicht: teken, omschrijving en bedrag.
private struct LedgerLineRow: View {
    let row: CashflowRow

    private var tone: Color {
        switch row.tone {
        case .neutral: return Color.primary
        case .positive: return Theme.positive
        case .negative: return Theme.negative
        case .accent: return Theme.accent
        }
    }

    private var titleFont: Font {
        switch row.style {
        case .line: return Font.subheadline
        case .detail: return Font.footnote
        case .total: return Font.subheadline.weight(.bold)
        }
    }

    private var amountFont: Font {
        switch row.style {
        case .line: return Font.subheadline.weight(.semibold)
        case .detail: return Font.footnote
        case .total: return Font.subheadline.weight(.bold)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Boven het eind staat een streep: begin + regels = eind.
            if row.kind == .end { Divider() }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.sign)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(titleFont)
                        .foregroundStyle(row.style == .detail ? Color.secondary : Color.primary)
                        .lineLimit(2)
                    if let note = row.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                amountView
            }
            .padding(.leading, row.style == .detail ? 22 : 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var amountView: some View {
        if let amount = row.amount {
            Text(row.showsSign ? CashflowText.signed(amount) : Fmt.euro(amount))
                .font(amountFont)
                .foregroundStyle(row.style == .detail ? Color.secondary : tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: amount)
        } else {
            Text("onbekend")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Rij die naar een pagina leidt, met het bedrag zoals op die pagina.
private struct LedgerLinkRow: View {
    let symbol: String
    let title: String
    var caption: String? = nil
    let value: Double
    var tone: Color = .primary
    let destination: Destination

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: symbol, color: Theme.accent, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let caption {
                        Text(caption).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(Fmt.euro(value))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .animation(Theme.motion, value: value)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .tile()
        }
        .buttonStyle(.plain)
    }
}

/// De bankrekening van de maand: begin, wat er binnenkwam, eruit ging en werd overgeschreven, en het eind.
/// Handmatige stortingen, opnames en overboekingen staan er apart bij als ze er zijn.
struct CashflowBankBlock: View {
    let ledger: MonthLedger
    let lowest: DayTotals?
    /// Het saldo van nu (alleen in de huidige maand, en alleen als het bekend is).
    let balanceNow: Double?
    /// Is er ooit een saldo ingevuld of een boeking gemaakt?
    let hasBalance: Bool

    var body: some View {
        let lowBalance = lowest?.bankBalance
        let lowText = lowBalance.map { Fmt.euro($0) } ?? "–"
        let lowCaption = lowest.map { DayText.weekdayShort($0.date) }
        GlassBlock(title: "Bankrekening", symbol: "building.columns.fill", subtitle: Fmt.month(ledger.month),
                   tint: Theme.olive.opacity(0.3)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                if let balanceNow {
                    StatTile(title: "Saldo nu", value: Fmt.euro(balanceNow),
                             color: balanceNow < 0 ? Theme.negative : Color.primary)
                }
                StatTile(title: "Laagste saldo", value: lowText,
                         color: (lowBalance ?? 0) < 0 ? Theme.negative : Color.primary,
                         caption: lowCaption)
            }
            VStack(spacing: 8) {
                ForEach(CashflowSummary.bankRows(ledger)) { row in
                    LedgerLineRow(row: row)
                        .transition(.opacity)
                }
            }
            if ledger.openingBank == nil && ledger.closingBank != nil {
                Text("Je saldo is pas later in de maand bekend, dus er is nog geen beginsaldo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !hasBalance {
                Text("Vul je saldo in op de bankrekening. Dan rekent de app per dag uit hoeveel je hebt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Bedragen staan afgerond op hele euro's, de berekening zelf klopt op de cent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// De spaarpotten van de maand: begin, inleg, rente, wat er uit potten is betaald en het eind.
struct CashflowPotsBlock: View {
    let ledger: MonthLedger

    var body: some View {
        GlassBlock(title: "Spaarpotten", symbol: "tray.full.fill", subtitle: Fmt.month(ledger.month),
                   headerLink: .pots) {
            VStack(spacing: 8) {
                ForEach(CashflowSummary.potsRows(ledger)) { row in
                    LedgerLineRow(row: row)
                        .transition(.opacity)
                }
            }
            Text("Inleg telt mee vanaf de overschrijfdag, rente vanaf de uitbetaaldag en een uitgave uit een pot vanaf de dag van die uitgave.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// De koppeling met het Overzicht: inkomen, uitgaven, gespaard, belegd en nog te verdelen van de maand, met precies
/// dezelfde waarden als op het Overzicht, en een kleine bevestiging dat alles sluit.
struct CashflowOverviewBlock: View {
    let ledger: MonthLedger
    let isOK: Bool

    var body: some View {
        let fromPots = ledger.expensesFromPots
        GlassBlock(title: "Je overzicht", symbol: "chart.bar.xaxis", subtitle: "Dezelfde cijfers als in je overzicht",
                   headerLink: .overview) {
            VStack(spacing: 8) {
                LedgerLinkRow(symbol: "briefcase.fill", title: "Inkomen", value: ledger.income, destination: .income)
                LedgerLinkRow(symbol: "minus.circle.fill", title: "Uitgaven",
                              caption: fromPots > 0 ? "Waarvan \(Fmt.euro(fromPots)) uit spaarpotten" : nil,
                              value: ledger.expensesTotal, destination: .expenses)
                LedgerLinkRow(symbol: "tray.full.fill", title: "Gespaard", value: ledger.saved, destination: .pots)
                LedgerLinkRow(symbol: "chart.line.uptrend.xyaxis", title: "Belegd", value: ledger.invested,
                              destination: .portfolio)
                LedgerLinkRow(symbol: "square.split.2x2.fill", title: "Nog te verdelen",
                              caption: "Inkomen min uitgaven van je rekening, gespaard en belegd",
                              value: ledger.remaining, tone: ledger.remaining < 0 ? Theme.negative : Color.primary,
                              destination: .distribute)
            }
            if isOK {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Klopt met je overzicht")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.positive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("De cijfers sluiten niet, zie de melding bovenaan.")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.negative)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
    }
}

/// De rode melding als de bankrekening, de spaarpotten of het overzicht niet sluiten, met per afwijking het verschil.
struct CashflowCheckBanner: View {
    let check: LedgerCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("De cijfers sluiten niet")
            }
            .font(.subheadline.weight(.semibold))
            ForEach(check.issues) { issue in
                Text(issue.text).font(.footnote)
            }
        }
        .foregroundStyle(Theme.negative)
        .padding(Theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Theme.negative.opacity(0.22))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Dag voor dag

/// Een regel die in een maand staat en die je vanuit de dagpagina kunt wijzigen.
struct CashflowLineTarget: Identifiable {
    let line: MoneyLine
    let kind: FinanceData.LineKind
    let month: YearMonth
    var id: UUID { line.id }
}

/// Wat een tik op een gebeurtenis doet.
enum CashflowAction {
    case open(Destination)
    case edit(CashflowLineTarget)
    case none
}

/// Alle dagen van een maand: wat er binnenkomt, weggaat en wordt overgeschreven, met het saldo van de bankrekening en de
/// spaarpotten aan het eind van elke dag. Bovenaan sluit de maand: begin + binnen − eruit − overgeschreven = eind, met
/// dezelfde cijfers als het Overzicht, "Nog te verdelen", de spaarpotten en de bankrekening.
struct CashflowPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing: CashflowLineTarget?
    @State private var filter: CashflowDayFilter = .all
    /// De lijst scrolt één keer naar vandaag bij het openen. Komt de pagina terug in beeld (na een tik op een
    /// gebeurtenis en weer terug), dan blijft de lijst staan waar je was.
    @State private var didScrollToToday = false

    var body: some View {
        let d = store.data
        let month = router.focusMonth
        let today = store.today
        // Eén dagboek voor de hele pagina: alle cijfers hieronder komen uit deze maand.
        let book = LedgerBook(d, today: today)
        let ledger = book.ledger(month)
        let check = LedgerCheck(ledger)
        let lookup = CashflowLineLookup(plan: d.plan(for: month))
        let lowest = CashflowLowPoint.lowest(in: ledger.days)
        let balanceNow: Double? = month == store.now ? d.bankBalanceNowIfKnown(current: store.now, today: today) : nil
        PageScaffold(title: "Dag voor dag") {
            ScrollViewReader { proxy in
                VStack(spacing: Theme.pageSpacing) {
                    MonthPickerBlock()
                    BankLowPointNotice(month: month)
                    if !check.isOK {
                        CashflowCheckBanner(check: check)
                    }
                    EqualSizeGrid(minimumColumnWidth: 340) {
                        CashflowBankBlock(ledger: ledger, lowest: lowest, balanceNow: balanceNow, hasBalance: d.hasBankBalance)
                        if !d.pots.isEmpty {
                            CashflowPotsBlock(ledger: ledger)
                        }
                        CashflowOverviewBlock(ledger: ledger, isOK: check.isOK)
                    }
                    chartBlock(ledger)
                    daysSection(d, ledger: ledger, lookup: lookup, month: month, proxy: proxy)
                }
                .onAppear {
                    guard !didScrollToToday else { return }
                    didScrollToToday = true
                    scrollToToday(proxy, ledger: ledger)
                }
            }
        }
        .sheet(item: $editing) { target in
            MoneyLineSheet(line: target.line, kind: target.kind, month: target.month,
                           defaultExpenseKind: target.line.kind)
        }
    }

    // MARK: Grafiek

    @ViewBuilder
    private func chartBlock(_ ledger: MonthLedger) -> some View {
        let days = ledger.days.filter { $0.bankBalance != nil }
        if days.count > 1 {
            GlassBlock(title: "Saldo per dag", symbol: "chart.xyaxis.line") {
                DayBalanceChart(days: days)
                Text("Gestippeld en lichter is gepland. De rode stippellijn is nul.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Lijst per dag

    private var filterBinding: Binding<CashflowDayFilter> {
        Binding<CashflowDayFilter>(get: { filter },
                                   set: { newValue in withAnimation(Theme.motion) { filter = newValue } })
    }

    @ViewBuilder
    private func daysSection(_ d: FinanceData, ledger: MonthLedger, lookup: CashflowLineLookup,
                             month: YearMonth, proxy: ScrollViewProxy) -> some View {
        let days = filter.days(of: ledger)
        let multipleSalaries = ledger.salaryPayoutCount > 1
        let hasToday = CashflowScroll.todayTarget(in: ledger) != nil
        GlassBlock(title: "Dag voor dag", symbol: "calendar", subtitle: "\(CashflowText.days(days.count)) in \(Fmt.month(month))") {
            Picker("Welke dagen", selection: filterBinding) {
                ForEach(CashflowDayFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if hasToday {
                ChipButton(title: "Naar vandaag", symbol: "arrow.down.to.line") {
                    scrollToToday(proxy, ledger: ledger, delay: false)
                }
            }
        }
        if days.isEmpty {
            GlassBlock(title: "Gebeurtenissen", symbol: "list.bullet") {
                EmptyHint(symbol: "calendar", title: "Niets in \(Fmt.month(month))",
                          message: "Er komt niets binnen, gaat niets weg en er wordt niets overgeschreven. Stel je salaris, inkomsten en uitgaven in met een dag naar keuze.")
            }
        } else {
            // Het id van elke kaart is zijn dagnummer, zowel voor de lijst (ForEach) als voor het scrollen: in een lazy raster
            // vindt `scrollTo` alleen kaarten die nog niet getekend zijn via de id's van de ForEach.
            LazyVGrid(columns: Theme.blockColumns, spacing: Theme.pageSpacing) {
                ForEach(days, id: \.day) { day in
                    dayCard(d, day: day, lookup: lookup, month: month, multipleSalaries: multipleSalaries)
                        .id(day.day)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            if days.contains(where: { $0.isPlanned }) {
                Text("Lichtere dagen liggen nog voor je: ze staan in je plan maar zijn nog niet gebeurd.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
        }
    }

    @ViewBuilder
    private func dayCard(_ d: FinanceData, day: DayTotals, lookup: CashflowLineLookup,
                         month: YearMonth, multipleSalaries: Bool) -> some View {
        GlassBlock(title: DayText.weekdayShort(day.date),
                   symbol: day.isToday ? "calendar.badge.clock" : "calendar",
                   subtitle: daySubtitle(day),
                   tint: day.isToday ? Theme.olive.opacity(0.3) : nil) {
            VStack(spacing: 10) {
                DayFlowTiles(day: day)
                if day.events.isEmpty {
                    Text("Geen boekingen op deze dag.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 10) {
                        ForEach(day.events) { event in
                            eventRow(event, lookup: lookup, month: month,
                                     showsDate: multipleSalaries && event.kind == .salary)
                        }
                    }
                }
                Divider()
                DayBalanceRows(day: day, showsPots: !d.pots.isEmpty)
            }
            .opacity(day.isPlanned ? 0.8 : 1)
        }
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    private func daySubtitle(_ day: DayTotals) -> String? {
        if day.isToday { return "Vandaag" }
        if day.isPlanned { return "Gepland" }
        return nil
    }

    @ViewBuilder
    private func eventRow(_ event: DayEvent, lookup: CashflowLineLookup, month: YearMonth, showsDate: Bool) -> some View {
        switch action(for: event, lookup: lookup, month: month) {
        case .open(let destination):
            NavigationLink(value: destination) {
                DayEventRow(event: event, showsDate: showsDate, showsChevron: true)
            }
            .buttonStyle(.plain)
        case .edit(let target):
            Button { editing = target } label: {
                DayEventRow(event: event, showsDate: showsDate, showsChevron: true)
            }
            .buttonStyle(.plain)
        case .none:
            DayEventRow(event: event, showsDate: showsDate)
        }
    }

    // MARK: Hulpjes

    /// Scrolt naar de kaart van vandaag, als de maand de huidige is. Bij het openen kort wachten: de lijst heeft zijn
    /// plek pas na de eerste layout.
    private func scrollToToday(_ proxy: ScrollViewProxy, ledger: MonthLedger, delay: Bool = true) {
        #if DEBUG
        // De screenshots van CI (demo-modus) tonen de pagina vanaf de bovenkant, met de maandsamenvatting in beeld.
        if delay && DebugLaunch.isDemo { return }
        #endif
        guard let target = CashflowScroll.todayTarget(in: ledger) else { return }
        Task { @MainActor in
            if delay { try? await Task.sleep(nanoseconds: 450_000_000) }
            withAnimation(Theme.motion) { proxy.scrollTo(target, anchor: .top) }
        }
    }

    /// Een tik op een gebeurtenis: de regel wijzigen, of naar de pot of belegging waar het bij hoort.
    private func action(for event: DayEvent, lookup: CashflowLineLookup, month: YearMonth) -> CashflowAction {
        switch event.kind {
        case .salary:
            return .open(.income)
        case .income:
            if let id = event.lineID, let line = lookup.income[id] {
                return .edit(CashflowLineTarget(line: line, kind: .income, month: month))
            }
            return .none
        case .expense:
            if let id = event.lineID, let line = lookup.expenses[id] {
                return .edit(CashflowLineTarget(line: line, kind: .expense, month: month))
            }
            return .none
        case .toPot, .interest:
            if let id = event.potID { return .open(.pot(id)) }
            return .none
        case .toHolding:
            if let id = event.holdingID { return .open(.holding(id)) }
            return .none
        case .bankEntry:
            return .none
        }
    }
}
