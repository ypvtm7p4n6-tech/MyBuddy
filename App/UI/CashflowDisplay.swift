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

    /// Een rente-uitkomst met teken: onder de 10 euro met centen ("+ € 1,25"), daarboven op hele euro's, zoals overal voor
    /// rente (`PotFormat.interest`). Zonder dit staat er "+ € 1" waar de pagina van de pot "€ 1,25" zegt.
    static func signedInterest(_ amount: Double) -> String {
        let sign = amount > 0 ? "+ " : (amount < 0 ? "− " : "")
        return sign + PotFormat.interest(abs(amount))
    }

    /// "1 dag", "12 dagen".
    static func days(_ count: Int) -> String {
        count == 1 ? "1 dag" : "\(count) dagen"
    }

    /// "Vandaag" of "Gepland" bij een dag; nil voor een dag die al geweest is.
    static func status(of day: DayTotals) -> String? {
        if day.isToday { return "Vandaag" }
        if day.isPlanned { return "Gepland" }
        return nil
    }

    /// De naam van wat er van het inkomen overblijft (termenlijst): "Nog te verdelen" voor deze en komende maanden,
    /// "Overgehouden" voor een maand die voorbij is.
    static func leftoverTitle(month: YearMonth, current: YearMonth) -> String {
        month >= current ? "Nog te verdelen" : "Overgehouden"
    }

    /// Het saldo aan het eind van een maand: "Verwacht eind oktober" (deze en komende maanden) of "Saldo eind september".
    static func monthEndTitle(_ month: YearMonth, current: YearMonth) -> String {
        let name = Fmt.monthNames[min(max(month.month, 1), 12) - 1]
        return month >= current ? "Verwacht eind \(name)" : "Saldo eind \(name)"
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

    /// Het bedrag zoals de regel het toont: rente onder de 10 euro met centen, een regel met teken met plus of min, de rest
    /// op hele euro's. nil als het bedrag onbekend is.
    var amountText: String? {
        guard let amount else { return nil }
        if kind == .interest { return PotFormat.interest(amount) }
        return showsSign ? CashflowText.signed(amount) : Fmt.euro(amount)
    }
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
            rows.append(CashflowRow(kind: .inflowPlan, title: "Inkomen", sign: "", amount: l.planInflow, style: .detail))
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

/// De controle "klopt het met de maandcijfers?". Is alles in orde (`MonthLedger.allReconciles`), dan zijn er geen
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
                             text: "\(title): maandcijfers \(Fmt.euroExact(overview)), dagen \(Fmt.euroExact(days)) (verschil \(text(a - b)))."))
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
            out.append(Issue(id: "overview", text: "De dagen sluiten niet met de maandcijfers van deze maand."))
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

// MARK: Wat een tik op een gebeurtenis doet

/// Een regel die in een maand staat en die je vanuit Dag voor dag kunt wijzigen.
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

    /// Een tik op een gebeurtenis: de regel wijzigen, of naar de pot, de belegging of Inkomen waar het bij hoort.
    static func make(for event: DayEvent, lookup: CashflowLineLookup, month: YearMonth) -> CashflowAction {
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
    ///   - buffer: het minimumsaldo dat je op de bankrekening wilt houden (niet de noodbuffer van Noodbuffer).
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
            return BankLowPointNote(text: "Let op: \(when) staat je saldo onder nul (\(balance)). Kijk of je een uitgave of inleg naar een andere dag kunt zetten.",
                                    severe: true)
        }
        // De melding over het minimumsaldo is bedoeld voor een dip die je plan veroorzaakt. Zit je nu al onder je minimumsaldo,
        // dan zie je dat bij Minimumsaldo en blijft deze melding weg, zodat de melding "onder nul" opvalt.
        // Is het saldo van nu niet bekend, dan is er niets om mee te vergelijken en blijft de melding ook weg.
        if let now = balanceNow, buffer > 0 && lowBalance < buffer && now >= buffer && !past {
            let start = isToday ? "Vandaag" : "Op \(day)"
            return BankLowPointNote(text: "\(start) zakt je saldo naar \(balance). Dat is onder je minimumsaldo van \(Fmt.euro(buffer)).",
                                    severe: false)
        }
        return nil
    }

    /// De melding voor `month`, uit de dagboekhouding van `book`: het laagste saldo in het bereik van `BankLowPointWindow`, met
    /// het minimumsaldo en het saldo van nu uit de rekenmotor. nil zonder enig saldo of meetpunt, en als alles in orde is.
    static func forMonth(_ month: YearMonth, in data: FinanceData, current: YearMonth, today: Date,
                         book: LedgerBook) -> BankLowPointNote? {
        // Zonder een enkel meetpunt of boeking is er nergens een saldo: dan valt er niets te rekenen.
        guard data.hasBankBalance else { return nil }
        let window = BankLowPointWindow.range(for: month, current: current, today: today)
        guard let low = CashflowLowPoint.lowest(in: book.days(from: window.from, to: window.to)) else { return nil }
        return BankLowPointNote.make(low: low,
                                     buffer: data.bankBuffer(current: current),
                                     balanceNow: data.bankBalanceNowIfKnown(current: current, today: today),
                                     today: today)
    }
}

// MARK: Binnen en eruit

/// De cijfers van "Binnen en eruit" voor een maand, allemaal uit dezelfde bronnen als de rest van de app: `expenseOverview`
/// (inkomen, uitgaven, inleg) en het bankdeel van elke uitgavenregel (`fromBank(of:)`). Er wordt hier niets zelf uitgerekend.
/// Inkomen min wat van de bank gaat min inleg is `leftAfterTransfers`, hetzelfde getal als `remaining(in:)`.
struct BankFlowFigures: Equatable {
    let income: Double
    /// Alle vaste en variabele uitgaven, ook wat uit spaarpotten komt.
    let fixed: Double
    let variable: Double
    /// Het deel van de uitgaven dat uit spaarpotten wordt betaald.
    let fromPots: Double
    /// Het deel van de vaste en de variabele uitgaven dat van de bankrekening gaat.
    let fixedFromBank: Double
    let variableFromBank: Double
    let toPots: Double
    let toInvestments: Double
    let leftAfterExpenses: Double
    let leftAfterTransfers: Double

    init(_ d: FinanceData, month: YearMonth) {
        let overview = d.expenseOverview(in: month)
        income = overview.income
        fixed = overview.fixed
        variable = overview.variable
        fromPots = overview.fromPots
        toPots = overview.toPots
        toInvestments = overview.toInvestments
        leftAfterExpenses = overview.leftAfterExpenses
        leftAfterTransfers = overview.leftAfterTransfers
        fixedFromBank = BankFlowFigures.bankPart(d, month: month, kind: .fixed)
        variableFromBank = BankFlowFigures.bankPart(d, month: month, kind: .variable)
    }

    /// Het deel van de uitgaven van één soort dat van de bankrekening gaat, zoals de rekenmotor het boekt per regel.
    private static func bankPart(_ d: FinanceData, month: YearMonth, kind: ExpenseKind) -> Double {
        guard month >= d.startMonth else { return 0 }
        let cents = d.expenseLines(in: month, kind: kind).map { CentsMath.int(d.fromBank(of: $0)) }
        return CentsMath.value(CentsMath.sum(cents))
    }

    /// Er komt niets binnen, er gaat niets uit en er is niets ingelegd: dan is er niets om te tonen.
    var isEmpty: Bool {
        income == 0 && fixed == 0 && variable == 0 && toPots == 0 && toInvestments == 0
    }
}

// MARK: Boekingen

/// Een regel in de lijst Boekingen: een ingevuld saldo of een boeking op de bankrekening.
struct BankHistoryItem: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let title: String
    let detail: String
    /// Bij een ingevuld saldo het saldo, anders het bedrag van de boeking (positief = erbij).
    let amount: Double
    let isSnapshot: Bool

    /// Alle ingevulde saldi en boekingen, de nieuwste eerst (bij dezelfde datum in een vaste volgorde).
    static func items(from d: FinanceData) -> [BankHistoryItem] {
        var list: [BankHistoryItem] = []
        for snapshot in d.bankSnapshots {
            list.append(BankHistoryItem(id: snapshot.id, date: snapshot.date, title: "Saldo ingevuld", detail: snapshot.note,
                                        amount: snapshot.balance, isSnapshot: true))
        }
        for entry in d.bankEntries {
            list.append(BankHistoryItem(id: entry.id, date: entry.date, title: entry.kind.title, detail: entry.note,
                                        amount: entry.amount, isSnapshot: false))
        }
        return list.sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// De tekst voor de bevestiging bij het verwijderen van een boeking, of nil als de boeking los staat (dan is verwijderen
    /// veilig en vraagt de app niets).
    static func removalWarning(forBankEntry id: UUID, in d: FinanceData) -> String? {
        guard let entry = d.bankEntries.first(where: { $0.id == id }) else { return nil }
        // Een overboeking met `pairID`: de rekenmotor verwijdert beide helften en zegt zelf wat er verdwijnt.
        if let warning = d.pairedEntries(ofBank: id).warning { return warning }
        // Een oude overboeking zonder `pairID`: alleen de kant op de bankrekening verdwijnt.
        if entry.kind == .toPot || entry.kind == .fromPot {
            return "Dit verwijdert alleen de boeking op de bankrekening. De bijbehorende boeking bij de spaarpot blijft staan; die verwijder je bij de spaarpot."
        }
        return nil
    }
}

// MARK: Komende dagen

/// Het venster van de kaart "Komende dagen" op het Overzicht: de komende 14 dagen, vandaag meegerekend.
enum UpcomingDaysWindow {
    static let length = 14

    /// Van het begin van vandaag tot en met de laatste dag van het venster.
    static func range(today: Date) -> (from: Date, to: Date) {
        let cal = YearMonth.calendar
        let start = cal.startOfDay(for: today)
        let end = cal.date(byAdding: .day, value: length - 1, to: start) ?? start
        return (start, end)
    }

    /// De dagen in het venster waarop iets gebeurt, met hun saldo uit de dagboekhouding.
    static func busyDays(in book: LedgerBook, today: Date) -> [DayTotals] {
        let window = range(today: today)
        return book.days(from: window.from, to: window.to).filter { !$0.events.isEmpty }
    }
}
