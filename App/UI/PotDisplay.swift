import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in PotDisplayTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - Teksten en cijfers rond rente

/// Kleine hulpjes voor teksten rond rente en dagen, zodat tegels, het bewerkblad en de detailpagina hetzelfde zeggen.
enum PotFormat {
    /// "1 januari 2027".
    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Fmt.locale
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    /// Rente-bedragen: onder de 10 euro met centen (anders staat er "€ 0"), daarboven afgerond op hele euro's.
    static func interest(_ value: Double) -> String {
        if value != 0 && abs(value) < 10 { return Fmt.euroExact(value) }
        return Fmt.euro(value)
    }

    /// "de 25e".
    static func dayName(_ day: Int) -> String {
        "de \(day)e"
    }

    /// Naam van een maand (1...12), bijvoorbeeld "januari".
    static func monthName(_ number: Int) -> String {
        Fmt.monthNames[min(max(number, 1), 12) - 1]
    }

    /// "januari, april en juli".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " en " + items[items.count - 1]
        }
    }

    /// De maanden (1...12) waarin een pot rente uitbetaalt. Zelfde regel als de rekenmotor:
    /// vanaf de eerste uitbetaalmaand telkens `intervalMonths` verder.
    static func payoutMonths(_ payout: InterestPayout, firstMonth: Int) -> [Int] {
        let interval = max(1, payout.intervalMonths)
        let anchor = min(max(firstMonth, 1), 12)
        return (1...12).filter { (($0 - anchor) % interval + interval) % interval == 0 }
    }

    /// De eerste uitbetaalmaand van het jaar die bij dit ritme past: bij elk kwartaal januari t/m maart, bij elk
    /// half jaar januari t/m juni, bij elk jaar elke maand. Maandelijks heeft er geen last van (alleen begrensd op 1...12).
    /// De rekenmotor telt vanaf deze maand telkens `intervalMonths` verder, dus een maand erboven geeft dezelfde
    /// uitbetalingen als de maand die hier uitkomt.
    static func firstMonth(_ month: Int, for payout: InterestPayout) -> Int {
        let clamped = min(max(month, 1), 12)
        guard payout != .monthly else { return clamped }
        let interval = max(1, payout.intervalMonths)
        return (clamped - 1) % interval + 1
    }

    /// De maanden die je kunt kiezen als eerste uitbetaling van het jaar: 1...3 bij kwartaal, 1...6 bij half jaar, 1...12 bij jaar.
    static func firstMonthChoices(for payout: InterestPayout) -> ClosedRange<Int> {
        1...min(12, max(1, payout.intervalMonths))
    }

    /// "+€ 120", "€ -30" of "€ 0": een verschil dat op nul afrondt krijgt geen plus.
    static func signed(_ value: Double) -> String {
        let shown = value.rounded()
        if shown == 0 { return Fmt.euro(0) }
        return (shown > 0 ? "+" : "") + Fmt.euro(value)
    }

    /// "morgen" of "over 12 dagen".
    static func daysAhead(_ days: Int) -> String {
        days <= 1 ? "morgen" : "over \(days) dagen"
    }

    /// "+ € 300" of "− € 60" voor een boeking in de lijst met komende boekingen; rente met centen onder de 10 euro.
    static func bookingAmount(_ value: Double, isInterest: Bool) -> String {
        let text = isInterest ? interest(abs(value)) : Fmt.euro(abs(value))
        return (value >= 0 ? "+ " : "− ") + text
    }

    /// "Je krijgt rente in januari en juli, op de 1e."
    static func schedule(_ payout: InterestPayout, firstMonth: Int, day: Int) -> String {
        var text: String
        if payout == .monthly {
            text = "Je krijgt elke maand rente, op \(dayName(day))."
        } else {
            let names = payoutMonths(payout, firstMonth: firstMonth).map { monthName($0) }
            text = "Je krijgt rente in \(list(names)), op \(dayName(day))."
        }
        if day > 28 {
            text += " Heeft een maand die dag niet, dan is het de laatste dag van die maand."
        }
        return text
    }

    /// "1 januari 2027, ongeveer € 12" (zonder "ongeveer" als de uitbetaling al vaststaat).
    static func nextPayment(_ payment: InterestPayment) -> String {
        let approx = payment.isProjected ? "ongeveer " : ""
        return longDate(payment.date) + ", " + approx + interest(payment.amount)
    }
}

/// Rente die een pot (of alle potten) echt heeft gekregen.
struct PotInterestReceived: Equatable {
    var total: Double
    var thisYear: Double
}

enum PotInterestStats {
    /// Wat er aan rente is bijgeschreven op of voor `today`: opgeslagen boekingen plus uitbetalingen die al
    /// aan de beurt waren maar nog niet zijn opgeslagen (die tellen al wel mee in het saldo).
    /// Zonder `potID` telt het alle potten.
    ///
    /// Per KALENDERDAG, zoals het saldo van de pot: een uitbetaling van vandaag (die op 12:00 staat) telt de hele dag mee,
    /// ook voor 12:00. Anders zou "Ontvangen" een uitbetaling missen die al in het saldo zit.
    static func received(in d: FinanceData, potID: UUID? = nil, asOf today: Date) -> PotInterestReceived {
        let cal = YearMonth.calendar
        let limit = DayMath.planLimit(for: today)
        let year = cal.component(.year, from: today)
        let wanted: Set<UUID> = potID.map { Set([$0]) } ?? Set(d.pots.map { $0.id })
        var total = 0
        var thisYear = 0

        for entry in d.countedPotEntries where entry.kind == .interest && entry.date < limit && wanted.contains(entry.potID) {
            let cents = CentsMath.int(entry.amount)
            total = CentsMath.add(total, cents)
            if cal.component(.year, from: entry.date) == year { thisYear = CentsMath.add(thisYear, cents) }
        }

        for pot in d.pots where wanted.contains(pot.id) && InterestRules.isActive(pot) {
            let payments = d.interestPayments(for: pot.id, from: pot.startMonth.firstDay, to: today, asOf: today)
            for payment in payments where payment.isProjected && payment.date < limit {
                let cents = CentsMath.int(payment.amount)
                total = CentsMath.add(total, cents)
                if cal.component(.year, from: payment.date) == year { thisYear = CentsMath.add(thisYear, cents) }
            }
        }
        return PotInterestReceived(total: CentsMath.value(total), thisYear: CentsMath.value(thisYear))
    }
}

/// Wat de regels in de geschiedenis van een pot nodig hebben om te weten welke boeking erachter zit
/// en of je die mag verwijderen.
struct PotHistoryContext {
    let potID: UUID
    /// Id's van de opgeslagen rente-boekingen van deze pot.
    let storedInterest: Set<UUID>
    /// Id's van de uitbetalingen die de app zelf beheert: bij actieve rente schrijft de app die direct weer bij.
    let managedInterest: Set<UUID>

    init(pot: Pot, data: FinanceData, through last: YearMonth) {
        potID = pot.id
        storedInterest = Set(data.countedPotEntries.filter { $0.potID == pot.id && $0.kind == .interest }.map { $0.id })
        managedInterest = Set(data.interestPayoutMonths(for: pot, through: last)
            .map { InterestRules.entryID(for: pot.id, month: $0) })
    }

    /// De opgeslagen boeking achter een regel. nil voor maandverdelingen, geplande uitgaven en verwachte rente.
    func entryID(for item: PotTimelineItem) -> UUID? {
        if item.isMonthlyAllocation { return nil }
        if let id = UUID(uuidString: item.id) { return id }
        // Opgeslagen rente draagt de id van de uitbetaling ("interest-<pot>-<jjjj-mm>"); de boeking zelf heeft een vast id.
        guard item.kind == .interest else { return nil }
        let id = InterestRules.entryID(for: potID, month: YearMonth(date: item.date))
        return storedInterest.contains(id) ? id : nil
    }

    /// De boeking die je mag verwijderen. Rente die de app zelf beheert nooit: bij actieve rente boekt de app ontbrekende
    /// rente bij de volgende start (of het volgende bewaren van de pot) opnieuw, dus verwijderen helpt niet en maakt alleen de
    /// geschiedenis onbetrouwbaar. Klopt het saldo niet, pas het dan aan met "Saldo aanpassen". Staat de rente uit, dan
    /// schrijft de app niets meer bij en zijn de al bijgeschreven regels wel te verwijderen.
    func deletableEntryID(for item: PotTimelineItem) -> UUID? {
        guard let id = entryID(for: item) else { return nil }
        return managedInterest.contains(id) ? nil : id
    }
}

// MARK: - Doel en voortgang van een spaarpot

extension PotFormat {
    /// "Doel bereikt" of "Nog € 1.368 te gaan".
    static func goalStatus(balance: Double, goal: Double) -> String {
        balance >= goal ? "Doel bereikt" : "Nog \(Fmt.euro(goal - balance)) te gaan"
    }

    /// De voortgang voor VoiceOver: "43 procent, 1.032 euro van 2.400 euro". Boven de 100% staat het echte percentage.
    static func progressSpeech(balance: Double, goal: Double, progress: Double) -> String {
        let percent: Int = progress.isFinite ? Int((min(max(progress, 0), 99) * 100).rounded()) : 0
        return "\(percent) procent, \(ChartText.euro(balance)) van \(ChartText.euro(goal))"
    }
}

// MARK: - De kop van een albumpagina

/// De teksten in de kop van de albumpagina van een spaarpot of belegging: de ondertitel en de feiten onder het kerngetal. Alleen
/// teksten uit bestaande cijfers (saldo, doel, rente, inleg); er wordt niets nieuws uitgerekend.
enum SavingAlbumText {
    /// "Spaarpot", of "Spaarpot · doel € 2.400" als de pot een doel heeft.
    static func potSubtitle(goal: Double?) -> String {
        guard let goal, goal > 0 else { return "Spaarpot" }
        return "Spaarpot · doel \(Fmt.euro(goal))"
    }

    /// De feiten onder het saldo van een pot: hoe ver je bent (of dat er geen doel is), de rente en de inleg. `interestRate` is nil
    /// zonder actieve rente; `progress` is de breuk van het doel (nil zonder doel).
    static func potFacts(balance: Double, goal: Double?, progress: Double?, interestRate: Double?,
                         contribution: String?) -> [String] {
        var facts: [String] = []
        if let goal, goal > 0 {
            var text = PotFormat.goalStatus(balance: balance, goal: goal)
            if let progress {
                text = "\(Fmt.percent(progress, digits: 0)) van je doel · " + text
            }
            facts.append(text)
        } else {
            facts.append("Geen doel ingesteld")
        }
        if let interestRate {
            facts.append("\(Fmt.percent(interestRate, digits: 2)) rente per jaar")
        }
        if let contribution {
            facts.append(contribution)
        }
        return facts
    }

    /// "Inleg € 300 deze maand", of bij een percentage "Inleg 10% van je salaris, € 300 deze maand". nil zonder inleg.
    static func contributionFact(_ info: ContributionInfo?) -> String? {
        guard let info, info.hasContribution else { return nil }
        if info.isPercent {
            return "Inleg \(info.ruleText), \(Fmt.euro(info.amount)) deze maand"
        }
        return "Inleg \(Fmt.euro(info.amount)) deze maand"
    }

    /// De ondertitel van een pot in de lijst: "Doel € 2.400 · 43%" (of "Geen doel ingesteld"), met de rente erachter als die er is en
    /// op een tweede regel de inleg als percentage (`ContributionInfo.listLine`).
    static func potListSubtitle(goal: Double?, progress: Double?, interestRate: Double?, contributionLine: String?) -> String {
        var parts: [String] = []
        if let progress, let goal, goal > 0 {
            parts.append("Doel \(Fmt.euro(goal))")
            parts.append(Fmt.percent(progress, digits: 0))
        } else {
            parts.append("Geen doel ingesteld")
        }
        if let interestRate {
            parts.append("\(Fmt.percent(interestRate, digits: 2)) rente")
        }
        var text = parts.joined(separator: " · ")
        if let contributionLine {
            text += "\n" + contributionLine
        }
        return text
    }

    /// "ETF", of "ETF · VWRL" als de belegging een ticker heeft.
    static func holdingSubtitle(kind: String, ticker: String?) -> String {
        guard let ticker, !ticker.isEmpty else { return kind }
        return "\(kind) · \(ticker)"
    }

    /// De feiten onder de waarde van een belegging: sinds wanneer je belegt, of de waarde geschat is, en de inleg.
    static func holdingFacts(startMonth: YearMonth, isEstimated: Bool, contribution: String?) -> [String] {
        var facts: [String] = ["Belegd sinds \(Fmt.month(startMonth))"]
        if isEstimated {
            facts.append("Waarde geschat uit je inleg")
        }
        if let contribution {
            facts.append(contribution)
        }
        return facts
    }

    /// De ondertitel van een belegging in de lijst: "VWRL · € 112,40" (of de soort zonder ticker), met erachter hoeveel je tot nu
    /// toe won of verloor ("+3,1%", "−2,0%") of "Geschat". `gainFraction` is nil zonder inleg.
    static func holdingListSubtitle(base: String, isEstimated: Bool, gainFraction: Double?) -> String {
        if isEstimated { return base + " · Geschat" }
        guard let gainFraction else { return base }
        let sign = gainFraction >= 0 ? "+" : "−"
        return base + " · " + sign + Fmt.percent(abs(gainFraction))
    }
}

// MARK: - Wat er op Home staat

/// De keuze van potten en beleggingen voor Home: maximaal `potLimit` potten en `holdingLimit` beleggingen, in
/// de volgorde waarin je tikt. De rekenmotor bewaart de keuze (`homePotIDs`, `homeHoldingIDs`); dit is alleen de logica van het blad.
enum FavoritePicker {
    static let potLimit = 3
    static let holdingLimit = 4

    /// Een tik op een id: staat hij in de keuze, dan verdwijnt hij (de rest schuift op); anders komt hij erbij zolang er plek is.
    static func toggled(_ id: UUID, in selected: [UUID], limit: Int) -> [UUID] {
        var result = selected
        if let index = result.firstIndex(of: id) {
            result.remove(at: index)
        } else if result.count < limit {
            result.append(id)
        }
        return result
    }

    /// Hoeveel lege plekken ("Kies pot") er zijn bij `chosen` gekozen potten.
    static func emptySlots(chosen: Int, limit: Int = potLimit) -> Int {
        max(0, limit - chosen)
    }

    /// Wat een lege plek doet.
    enum SlotAction: Equatable {
        /// Een pot kiezen die er nog niet in staat.
        case choose
        /// Er is geen pot meer om te kiezen: een nieuwe pot maken.
        case create
    }

    /// Een lege plek kiest een pot zolang er een pot is die nog niet gekozen is, en maakt anders een nieuwe pot.
    static func slotAction(chosen: Int, available: Int) -> SlotAction {
        available > chosen ? .choose : .create
    }
}

// MARK: - Het formulier van een belegging

/// De keuzes en teksten van het formulier "Belegging" (plan par. 5.2, K19), en wat "Bewaar" met de gegevens doet.
enum HoldingForm {
    /// "Belegd sinds" kiest uit de laatste tien jaar, in maanden.
    static let startMonthSpan = 120

    static let unitsHint = "Vul ook het aantal stuks in, anders kan de app de waarde niet uitrekenen."
    static let estimateHint = "Met Belegd sinds en Totaal ingelegd tekent de app de groei vanaf die maand, zonder rendement. Vul Huidige waarde in voor de echte waarde."
    static let trackedValueHint = "Met een koers en een aantal rekent de app de waarde zelf uit. Laat dit leeg tot de koers binnen is."

    /// De maanden voor "Belegd sinds": de huidige maand eerst, tien jaar terug. Valt de gekozen maand erbuiten (een oudere
    /// belegging uit een import, of een maand in de toekomst), dan staat ze er ook in, zodat de keuzelijst haar keuze altijd kent.
    static func startMonthChoices(current: YearMonth, selected: YearMonth) -> [YearMonth] {
        var months: [YearMonth] = []
        for offset in 0..<startMonthSpan { months.append(current.adding(-offset)) }
        if !months.contains(selected) {
            if selected > current { months.insert(selected, at: 0) } else { months.append(selected) }
        }
        return months
    }

    /// Er is een ticker maar geen aantal: dan kan de app de waarde niet uitrekenen.
    static func needsUnitsHint(ticker: String, units: Double) -> Bool {
        let hasTicker = !ticker.trimmingCharacters(in: .whitespaces).isEmpty
        return hasTicker && !(units > 0)
    }

    /// De waarde volgt de koers: er is een ticker en een aantal.
    static func isTracked(ticker: String, units: Double) -> Bool {
        let hasTicker = !ticker.trimmingCharacters(in: .whitespaces).isEmpty
        return hasTicker && units > 0
    }

    /// Wat de belegging nu waard is, onder het veld "Huidige waarde" bij een bestaande belegging. nil zonder waarde.
    static func currentValueNote(_ state: HoldingState?) -> String? {
        guard let state else { return nil }
        let value = Fmt.euro(state.value)
        if state.isEstimated { return "Nu \(value), geschat uit je inleg." }
        return "Nu \(value), volgens je laatste waarde-update."
    }

    /// Bewaart de belegging uit het formulier. Een nieuwe belegging met een ingevulde "Huidige waarde" krijgt een waarde-update van
    /// vandaag, ook met een ticker (komt de koers binnen, dan neemt die de waarde van vandaag over). Bij wijzigen zet een
    /// ingevulde waarde de waarde-update van vandaag (een tweede update op dezelfde dag vervangt de eerste); leeg laat de
    /// waarden zoals ze zijn. Zonder waarde-update tekent de app de afgeleide lijn uit "Totaal ingelegd" en "Belegd sinds".
    static func save(_ holding: Holding, isNew: Bool, enteredValue: Double, into data: inout FinanceData,
                     current: YearMonth, now: Date = Date()) {
        let entered: Double? = (enteredValue.isFinite && enteredValue > 0) ? enteredValue : nil
        if isNew {
            data.addHolding(holding, initialValue: entered, now: now)
            return
        }
        data.updateHolding(holding, current: current, now: now)
        if let entered {
            let invested = holding.investedTotal > 0 ? holding.investedTotal : entered
            data.addSnapshot(holdingID: holding.id, value: entered, invested: invested, date: now)
        }
    }
}

// MARK: - Cijfers van Beleggingen en een belegging

/// De cijfers bovenaan Beleggingen: waarde, ingelegd en winst van nu (per kalenderdag, zoals de bank en de spaarpotten). Zijn alle
/// beleggingen geschat uit je inleg (nog geen waarde-update), dan staat er "Geschat" bij het bedrag en zijn Winst en Rendement
/// verborgen: ze zijn dan 0 en zeggen niets.
struct PortfolioFigures: Equatable {
    var value: Double
    var invested: Double
    var gain: Double
    var isEstimated: Bool

    init(_ d: FinanceData, current: YearMonth, today: Date) {
        value = d.portfolioValue(current: current, today: today)
        invested = d.portfolioInvested(current: current, today: today)
        gain = d.portfolioGain(current: current, today: today)
        var states: [HoldingState] = []
        for holding in d.holdings {
            if let state = d.holdingStateNow(holding, current: current, today: today) { states.append(state) }
        }
        isEstimated = !states.isEmpty && states.allSatisfy { $0.isEstimated }
    }

    /// Winst als breuk van wat je inlegde; nil zolang er niets is ingelegd.
    var gainFraction: Double? { invested > 0 ? gain / invested : nil }

    /// Winst en Rendement tonen: er is iets ingelegd en de waarde is niet alleen geschat.
    var showsGain: Bool { invested > 0 && !isEstimated }
}

/// De cijfers van één belegging, uit haar toestand van nu.
struct HoldingFigures: Equatable {
    var value: Double
    var invested: Double
    var gain: Double
    var gainFraction: Double?
    var isEstimated: Bool

    init(_ state: HoldingState?) {
        value = state?.value ?? 0
        invested = state?.invested ?? 0
        gain = state?.gain ?? 0
        gainFraction = state?.gainFraction
        isEstimated = state?.isEstimated ?? false
    }

    var showsGain: Bool { invested > 0 && !isEstimated }
}

// MARK: - Een grafiek in het klein

/// De kernwaarden naast een kleine grafiek zonder assen (Home en Sparen): het begin en het eind als tekst, zodat de lijn nooit
/// alleen staat. nil als er niets te tekenen valt (de lege staat staat dan in een regel).
struct TrendGlance: Equatable {
    /// "mei '26 € 7.350". nil bij een enkel punt.
    var start: String?
    /// "Nu € 8.966", of "Nu € 3.000 (geschat)" bij een lijn uit je inleg.
    var end: String

    init?(_ model: TrendModel) {
        guard model.empty == nil, let line = model.lines.first else { return nil }
        let history = line.points.filter { $0.kind != .projected }
        guard let last = history.last else { return nil }
        var text = "Nu \(Fmt.euroWhole(last.value))"
        if last.kind == .estimated { text += " (geschat)" }
        end = text
        if history.count > 1, let first = history.first {
            start = "\(Fmt.shortMonthYear(YearMonth(date: first.date))) \(Fmt.euroWhole(first.value))"
        } else {
            start = nil
        }
    }
}

// MARK: - Koershistorie

enum PriceHistoryText {
    /// De reden dat de koershistorie niet kwam, als zin met een punt. `PriceTrend` zet er "Controleer je internet en de ticker." achter.
    static func failure(_ description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "Ophalen mislukt." }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }
}
