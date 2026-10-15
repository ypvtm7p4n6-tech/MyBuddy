import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in CashflowDisplayTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - Logica van de dagschermen (zonder SwiftUI)
//
// Alles tussen "BEGIN LOGICA" en "EINDE LOGICA" is Foundation-only en leest alleen uit de dagboekhouding van de
// rekenmotor (`MonthLedger` en `DayTotals`, zie Ledger.swift). Er wordt hier geen bedrag zelf uitgerekend: de
// schermen tonen wat de motor levert, zodat Overzicht, "Nog te verdelen", spaarpotten, bankrekening en dagen
// precies dezelfde cijfers hebben. Alleen waar een bedrag uit twee motorwaarden samengesteld wordt (bijvoorbeeld
// "overgeschreven" = spaarpotten + beleggingen) of waar een verschil getoond moet worden (de controle), gebeurt dat
// in hele centen (`CentsMath`) en staat het hieronder uitgelegd.


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
