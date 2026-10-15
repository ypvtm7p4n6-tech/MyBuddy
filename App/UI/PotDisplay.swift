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

        for entry in d.potEntries where entry.kind == .interest && entry.date < limit && wanted.contains(entry.potID) {
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
        storedInterest = Set(data.potEntries.filter { $0.potID == pot.id && $0.kind == .interest }.map { $0.id })
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

    /// De boeking die je mag verwijderen. Rente nooit: de app boekt ontbrekende rente bij de volgende start
    /// (of het volgende bewaren van de pot) opnieuw, dus verwijderen helpt niet en maakt alleen de geschiedenis
    /// onbetrouwbaar. Klopt het saldo niet, pas het dan aan met "Saldo aanpassen".
    func deletableEntryID(for item: PotTimelineItem) -> UUID? {
        guard item.kind != .interest, let id = entryID(for: item) else { return nil }
        return managedInterest.contains(id) ? nil : id
    }
}
