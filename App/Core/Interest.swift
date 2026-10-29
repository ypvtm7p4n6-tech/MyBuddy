import Foundation

/// Eén rente-uitbetaling van een spaarpot: opgeslagen (`isProjected == false`) of verwacht.
struct InterestPayment: Identifiable, Equatable {
    var potID: UUID
    var date: Date
    var amount: Double
    var isProjected: Bool
    /// Blijft gelijk wanneer een verwachte uitbetaling wordt opgeslagen: "interest-<pot>-<jjjj-mm>".
    var id: String
}

/// Stabiele id's uit een tekst, zonder CryptoKit, zodat het ook op Linux werkt.
/// Dezelfde tekst geeft altijd dezelfde UUID, op elk apparaat. Dit mag nooit veranderen, want
/// opgeslagen boekingen zijn eraan herkenbaar.
enum StableID {
    static func uuid(_ text: String) -> UUID {
        Prefix(text).uuid()
    }

    /// De hash van een beginstuk, om veel id's met dezelfde begintekst snel te maken: `Prefix("a|b|").uuid(adding: "c")`
    /// is precies `uuid("a|b|c")`.
    struct Prefix {
        // Twee FNV-1a-hashes met verschillende startwaarden, daarna door een mixer gehaald.
        private var h1: UInt64 = 0xcbf2_9ce4_8422_2325
        private var h2: UInt64 = 0x9e37_79b9_7f4a_7c15

        init(_ text: String) {
            absorb(text)
        }

        private mutating func absorb(_ text: String) {
            for byte in text.utf8 { absorb(byte: byte) }
        }

        private mutating func absorb(byte: UInt8) {
            h1 = (h1 ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            h2 = (h2 ^ UInt64(byte) ^ 0xa5) &* 0x0000_0100_0000_01b3
            h2 = (h2 << 13) | (h2 >> 51)
        }

        /// Het id van de tekst tot nu toe.
        func uuid() -> UUID {
            let a = StableID.mix(h1)
            let b = StableID.mix(h2 ^ a)
            @inline(__always) func byte(_ x: UInt64, _ i: UInt64) -> UInt8 { UInt8(truncatingIfNeeded: x >> (56 - 8 * i)) }
            return UUID(uuid: (byte(a, 0), byte(a, 1), byte(a, 2), byte(a, 3), byte(a, 4), byte(a, 5),
                               (byte(a, 6) & 0x0F) | 0x50,   // versie 5-achtig
                               byte(a, 7),
                               (byte(b, 0) & 0x3F) | 0x80,   // variant
                               byte(b, 1), byte(b, 2), byte(b, 3), byte(b, 4), byte(b, 5), byte(b, 6), byte(b, 7)))
        }

        /// Het id van de tekst tot nu toe plus de sleutel van `month` ("2026-10"): precies `uuid(adding: month.key)`,
        /// zonder die tekst eerst te maken.
        func uuid(addingKeyOf month: YearMonth) -> UUID {
            guard (0...9_999).contains(month.year), (1...12).contains(month.month) else { return uuid(adding: month.key) }
            var copy = self
            copy.absorb(byte: UInt8(48 + month.year / 1_000))
            copy.absorb(byte: UInt8(48 + month.year / 100 % 10))
            copy.absorb(byte: UInt8(48 + month.year / 10 % 10))
            copy.absorb(byte: UInt8(48 + month.year % 10))
            copy.absorb(byte: 45)
            copy.absorb(byte: UInt8(48 + month.month / 10))
            copy.absorb(byte: UInt8(48 + month.month % 10))
            return copy.uuid()
        }

        /// Het id van de tekst tot nu toe plus `suffix`.
        func uuid(adding suffix: String) -> UUID {
            var copy = self
            copy.absorb(suffix)
            return copy.uuid()
        }
    }

    fileprivate static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9e37_79b9_7f4a_7c15
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

/// Afspraken over rente die op meer plekken in de rekenmotor nodig zijn.
enum InterestRules {
    /// Een pot betaalt alleen rente bij een positief percentage.
    static func isActive(_ pot: Pot) -> Bool {
        pot.interestRate > 0 && pot.interestRate.isFinite
    }

    /// Vaste id van de opgeslagen uitbetaling van `potID` in `month`.
    static func entryID(for potID: UUID, month: YearMonth) -> UUID {
        StableID.uuid("interest|\(potID.uuidString)|\(month.key)")
    }

    /// De vaste id's van `months` in één keer (sneller dan `entryID` per maand, met dezelfde uitkomst).
    static func entryIDs(for potID: UUID, months: [YearMonth]) -> [UUID] {
        let prefix = StableID.Prefix("interest|\(potID.uuidString)|")
        return months.map { prefix.uuid(addingKeyOf: $0) }
    }

    static func paymentID(for potID: UUID, month: YearMonth) -> String {
        "interest-\(potID.uuidString)-\(month.key)"
    }

    /// De eerste maand waarin een pot rente kan krijgen: de startmaand van de pot, of de startmaand van de
    /// gegevens als die later is. Alle rente-berekeningen gebruiken deze ene plek.
    ///
    /// Let op: zet je rente aan op een pot die al langer bestaat, dan telt (en boekt `applyDueInterest`) de rente
    /// vanaf deze maand, dus ook over het verleden. Wil je dat voorkomen, begrens dan hier, bijvoorbeeld met een
    /// vastgelegde "rente vanaf"-maand per pot.
    static func firstMonth(for pot: Pot, dataStart: YearMonth) -> YearMonth {
        max(pot.startMonth, dataStart)
    }

    /// De laatste maand waarvan het saldo op de eerste dag meetelt in een uitbetaling op `day` van `payoutMonth`.
    /// Een uitbetaling betaalt rente over de tijd vóór de uitbetaaldag. Op de 1e is de uitbetaalmaand nog niet
    /// begonnen, dus telt de maand ervoor als laatste; vanaf de 2e telt de uitbetaalmaand zelf mee.
    /// Zo betaalt "elk jaar op 1 januari" de rente over januari t/m december van het jaar ervoor.
    static func lastCoveredMonth(payoutMonth: YearMonth, day: Int) -> YearMonth {
        day <= 1 ? payoutMonth.adding(-1) : payoutMonth
    }
}

/// Het eind van de eerste dag van een maand (begin van de tweede), onthouden zodat meer potten het niet steeds opnieuw uitrekenen.
final class FirstDayLimits {
    private var cache: [Int: Date] = [:]
    private let calendar = YearMonth.calendar

    func endOfFirstDay(of month: YearMonth) -> Date {
        if let known = cache[month.index] { return known }
        let value = DayMath.nextDayStart(after: month.date(day: 1, calendar: calendar), calendar: calendar)
        cache[month.index] = value
        return value
    }
}

/// De uitbetalingen die al klaar zijn terwijl de volgende wordt uitgerekend, met een lopende som: wat er aan rente
/// is uitbetaald vóór een moment, zonder elke keer alles langs te lopen.
private struct RunningPayments {
    private var dates: [Date] = []
    private var prefix: [Int] = [0]
    private var inOrder = true

    mutating func append(date: Date, cents: Int) {
        if let last = dates.last, date < last { inOrder = false }
        dates.append(date)
        prefix.append(CentsMath.add(prefix[prefix.count - 1], cents))
    }

    /// Som (in hele centen) van de uitbetalingen met een datum vóór `limit`.
    func sum(before limit: Date) -> Int {
        if inOrder {
            var lo = 0
            var hi = dates.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if dates[mid] < limit { lo = mid + 1 } else { hi = mid }
            }
            return prefix[lo]
        }
        var total = 0
        for index in dates.indices where dates[index] < limit {
            total = CentsMath.add(total, CentsMath.add(prefix[index + 1], -prefix[index]))
        }
        return total
    }
}

/// De boekingen van een pot in twee lijsten op datum.
struct PotLedgers {
    /// Handmatige boekingen (`PotEntry`): ze houden hun eigen tijdstip.
    var entries: CentsLedger
    /// Wat uit het plan komt: de maandverdeling en de potdelen van uitgaven. Ze gelden per kalenderdag.
    var plan: CentsLedger

    /// Saldo in hele centen vóór `limit` (alles op dezelfde grens, zoals voor het eind van een dag).
    func cents(before limit: Date) -> Int {
        CentsMath.add(entries.sum(before: limit), plan.sum(before: limit))
    }
}

/// Alles wat het saldo van een pot bepaalt: de gewone boekingen en de rente-uitbetalingen.
/// Opgeslagen uitbetalingen staan alleen in `payments` (niet in `entries`), zodat ze nooit dubbel tellen.
///
/// Voor een saldo aan het EIND van een dag hebben alle soorten dezelfde bovengrens (het begin van de dag erna).
/// Voor "nu" niet: handmatige boekingen tellen tot en met hun eigen tijdstip, planboekingen en rente-uitbetalingen
/// (ook de opgeslagen: ze zijn door het plan bepaald) tot en met de hele dag.
struct PotFlows {
    /// Handmatige boekingen, met hun eigen tijdstip.
    var entries: CentsLedger
    /// Maandverdeling en potdelen van uitgaven, per kalenderdag.
    var plan: CentsLedger
    /// Opgeslagen en verwachte uitbetalingen, oplopend op datum.
    private(set) var payments: [InterestPayment]
    /// De vaste id's (`InterestRules.entryID`) van de uitbetalingen die hier apart meetellen. Opgeslagen boekingen
    /// met zo'n id zitten in `payments` en dus niet nog eens in `entries`.
    var managedIDs: Set<UUID> = []

    /// Datums en lopende som (in hele centen) van `payments`, om snel het saldo op een moment te vinden.
    private var paymentDates: [Date] = []
    private var paymentPrefix: [Int] = [0]

    init(ledgers: PotLedgers, payments: [InterestPayment], managedIDs: Set<UUID> = []) {
        self.entries = ledgers.entries
        self.plan = ledgers.plan
        self.payments = payments
        self.managedIDs = managedIDs
        var running = 0
        var sums = [0]
        sums.reserveCapacity(payments.count + 1)
        var inOrder = true
        for (index, payment) in payments.enumerated() {
            running = CentsMath.add(running, CentsMath.int(payment.amount))
            sums.append(running)
            if index > 0 && payment.date < payments[index - 1].date { inOrder = false }
        }
        // De uitbetalingen staan op datum; zo niet, dan tellen we ze één voor één (zie `cents`).
        paymentDates = inOrder ? payments.map { $0.date } : []
        paymentPrefix = sums
    }

    /// Saldo in hele centen vóór `limit` (alles op dezelfde grens: het eind van een dag).
    func cents(before limit: Date) -> Int {
        cents(entriesBefore: limit, planBefore: limit)
    }

    /// Saldo in hele centen met aparte bovengrenzen: handmatige boekingen vóór `entriesBefore`, planboekingen en
    /// rente vóór `planBefore`.
    func cents(entriesBefore: Date, planBefore: Date) -> Int {
        var total = CentsMath.add(entries.sum(before: entriesBefore), plan.sum(before: planBefore))
        if payments.isEmpty { return total }
        if paymentDates.count == payments.count {
            // Op datum: het aantal uitbetalingen vóór de grens zoeken.
            var lo = 0
            var hi = paymentDates.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if paymentDates[mid] < planBefore { lo = mid + 1 } else { hi = mid }
            }
            return CentsMath.add(total, paymentPrefix[lo])
        }
        for payment in payments where payment.date < planBefore {
            total = CentsMath.add(total, CentsMath.int(payment.amount))
        }
        return total
    }
}

extension FinanceData {
    // MARK: Rooster van uitbetalingen

    /// De maanden waarin de pot rente uitbetaalt, t/m `last`. Bij maandelijks elke maand; anders alle maanden
    /// waarvoor (maand − uitbetaalmaand) deelbaar is door het aantal maanden tussen twee uitbetalingen.
    /// De eerste mogelijke uitbetaling is in de startmaand van de pot (of de startmaand van de gegevens).
    func interestPayoutMonths(for pot: Pot, through last: YearMonth) -> [YearMonth] {
        guard InterestRules.isActive(pot) else { return [] }
        let first = InterestRules.firstMonth(for: pot, dataStart: startMonth)
        guard last >= first else { return [] }
        let interval = max(1, pot.interestPayout.intervalMonths)
        let payoutMonth = min(max(pot.interestPayoutMonth, 1), 12)
        var out: [YearMonth] = []
        var m = first
        var count = 0
        while m <= last && count < 2_400 {
            let offset = ((m.month - payoutMonth) % interval + interval) % interval
            if interval == 1 || offset == 0 { out.append(m) }
            m = m.adding(1)
            count += 1
        }
        return out
    }

    /// Boekingen en rente van een pot t/m `last`.
    ///
    /// Rente per uitbetaling = rente / 12 × som van het saldo op de eerste dag van elke maand in de periode.
    /// De periode loopt vanaf de maand na de vorige uitbetaling (of de startmaand van de pot) t/m de laatste
    /// maand die de uitbetaling meeneemt (`InterestRules.lastCoveredMonth`). Bij een vast ritme zijn dat de maanden
    /// tussen twee uitbetalingen. Eerdere uitbetalingen (opgeslagen of verwacht) tellen mee in het saldo, de
    /// uitbetaling zelf niet. Afgerond op centen, nooit negatief.
    ///
    /// Opgeslagen rente (ook van een eerder ritme of handmatig) geldt als uitbetaald t/m de maand die ze meenam.
    /// Wissel je van ritme, dan betaalt de app die maanden dus niet nog een keer en laat ze er ook geen vallen.
    /// Het resultaat hangt niet af van `last`: alle opgeslagen rente van de pot telt altijd mee.
    func potFlows(_ pot: Pot, throughMonth last: YearMonth) -> PotFlows {
        potFlows(for: [pot], throughMonth: last)[pot.id]
            ?? PotFlows(ledgers: PotLedgers(entries: CentsLedger(), plan: CentsLedger()), payments: [])
    }

    /// De flows van alle potten in één keer (sneller dan `potFlows` per pot: de maanden en uitgaven worden één keer
    /// doorlopen). Op pot-id.
    func allPotFlows(throughMonth last: YearMonth) -> [UUID: PotFlows] {
        potFlows(for: pots, throughMonth: last)
    }

    /// Zoals `potFlows(_:throughMonth:)` voor meer potten tegelijk, op pot-id.
    func potFlows(for requested: [Pot], throughMonth last: YearMonth) -> [UUID: PotFlows] {
        // Een pot telt één keer (zoals `pot(_:)` de eerste met een id pakt).
        var seen = Set<UUID>()
        let targets = requested.filter { seen.insert($0.id).inserted }
        let limits = FirstDayLimits()
        var payoutMonthsByPot: [UUID: [YearMonth]] = [:]
        var idsByPot: [UUID: [UUID]] = [:]
        var managedByPot: [UUID: Set<UUID>] = [:]
        for pot in targets {
            let payoutMonths = interestPayoutMonths(for: pot, through: last)
            payoutMonthsByPot[pot.id] = payoutMonths
            if !payoutMonths.isEmpty {
                let ids = InterestRules.entryIDs(for: pot.id, months: payoutMonths)
                idsByPot[pot.id] = ids
                managedByPot[pot.id] = Set(ids)
            }
        }
        let ledgers = potLedgers(for: targets, throughMonth: last, excluding: managedByPot)

        var result: [UUID: PotFlows] = [:]
        for pot in targets {
            guard let ledger = ledgers[pot.id] else { continue }
            guard let payoutMonths = payoutMonthsByPot[pot.id], !payoutMonths.isEmpty,
                  let ids = idsByPot[pot.id], let managed = managedByPot[pot.id] else {
                result[pot.id] = PotFlows(ledgers: ledger, payments: [])
                continue
            }
            let payments = interestPayments(of: pot, payoutMonths: payoutMonths, entryIDs: ids, managedIDs: managed,
                                            ledgers: ledger, limits: limits)
            result[pot.id] = PotFlows(ledgers: ledger, payments: payments, managedIDs: managed)
        }
        return result
    }

    /// De uitbetalingen van één pot: opgeslagen waar die er zijn, anders verwacht (zie `potFlows`).
    private func interestPayments(of pot: Pot, payoutMonths: [YearMonth], entryIDs: [UUID], managedIDs: Set<UUID>,
                                  ledgers: PotLedgers, limits: FirstDayLimits) -> [InterestPayment] {
        var stored: [UUID: PotEntry] = [:]
        let counted = countedPotEntries
        for e in counted where e.potID == pot.id && managedIDs.contains(e.id) && stored[e.id] == nil {
            stored[e.id] = e
        }

        let interval = max(1, pot.interestPayout.intervalMonths)
        let firstMonth = InterestRules.firstMonth(for: pot, dataStart: startMonth)
        let cal = YearMonth.calendar

        // Tot en met welke maand is er al rente uitbetaald? Opgeslagen rente telt altijd mee, ook van ná `last`.
        var settled: YearMonth?
        for e in counted where e.potID == pot.id && e.kind == .interest && e.amount > 0 {
            let covered = InterestRules.lastCoveredMonth(payoutMonth: YearMonth(date: e.date, calendar: cal),
                                                         day: DayMath.dayNumber(of: e.date, calendar: cal))
            settled = max(settled ?? covered, covered)
        }

        var payments: [InterestPayment] = []
        var earlier = RunningPayments()
        let paymentPrefix = "interest-\(pot.id.uuidString)-"

        for (index, month) in payoutMonths.enumerated() {
            let paymentID = paymentPrefix + month.key

            if let entry = stored[entryIDs[index]] {
                payments.append(InterestPayment(potID: pot.id, date: entry.date, amount: entry.amount,
                                                isProjected: false, id: paymentID))
                earlier.append(date: entry.date, cents: CentsMath.int(entry.amount))
                continue
            }

            let end = InterestRules.lastCoveredMonth(payoutMonth: month, day: pot.interestPayoutDay)
            var begin = settled.map { $0.adding(1) } ?? end.adding(-(interval - 1))
            if begin < firstMonth { begin = firstMonth }
            // Alles tot en met `end` is al uitbetaald (of de pot begon er nog niet): niets te betalen.
            guard begin <= end else { continue }
            settled = end

            var sum = 0
            var m = begin
            while m <= end {
                let limit = limits.endOfFirstDay(of: m)
                let balance = CentsMath.add(ledgers.cents(before: limit), earlier.sum(before: limit))
                sum = CentsMath.add(sum, balance)
                m = m.adding(1)
            }
            let raw = (pot.interestRate * Double(sum) / 12).rounded()
            guard raw.isFinite, raw > 0 else { continue }
            let cents = Int(min(raw, Double(CentsMath.limit)))
            let date = month.date(day: YearMonth.clampedDay(pot.interestPayoutDay), calendar: cal)
            payments.append(InterestPayment(potID: pot.id, date: date, amount: CentsMath.value(cents),
                                            isProjected: true, id: paymentID))
            earlier.append(date: date, cents: cents)
        }
        payments.sort { $0.date < $1.date }
        return payments
    }

    // MARK: Opvragen

    /// Opgeslagen en verwachte uitbetalingen met een datum van `from` t/m `to` (op dagniveau), oplopend.
    /// Uitbetalingen van nul euro komen niet voor.
    func interestPayments(for potID: UUID, from: Date, to: Date, asOf today: Date = Date()) -> [InterestPayment] {
        guard let pot = self.pot(potID) else { return [] }
        let cal = YearMonth.calendar
        let lower = cal.startOfDay(for: from)
        let upper = DayMath.nextDayStart(after: to, calendar: cal)
        guard upper > lower else { return [] }
        let flows = potFlows(pot, throughMonth: YearMonth(date: to))
        return flows.payments.filter { $0.date >= lower && $0.date < upper }
    }

    /// De eerstvolgende uitbetaling na vandaag (verwacht of al opgeslagen). nil zonder rente.
    /// Per kalenderdag: een uitbetaling van vandaag telt al als ontvangen (ook voor 12:00), de volgende is dus
    /// de eerste op een latere dag.
    func nextInterestPayment(for potID: UUID, asOf today: Date = Date()) -> InterestPayment? {
        guard let pot = self.pot(potID), InterestRules.isActive(pot) else { return nil }
        let flows = potFlows(pot, throughMonth: YearMonth(date: today).adding(26))
        let planLimit = DayMath.planLimit(for: today)
        return flows.payments.first { $0.date >= planLimit }
    }

    // MARK: Boeken

    /// Boekt de uitbetalingen die tot en met de dag van `date` aan de beurt waren en nog niet zijn opgeslagen als
    /// `PotEntry(kind: .interest)`. Per kalenderdag: een uitbetaling van vandaag wordt vandaag al geboekt, ook
    /// voor 12:00. Het id is vast (afgeleid van pot en maand), dus twee aanroepen of twee apparaten
    /// maken nooit dubbele boekingen. Geeft het aantal nieuwe boekingen terug.
    @discardableResult
    mutating func applyDueInterest(upTo date: Date = Date()) -> Int {
        let last = YearMonth(date: date)
        let planLimit = DayMath.planLimit(for: date)
        var fresh: [PotEntry] = []
        for pot in pots where InterestRules.isActive(pot) {
            let flows = potFlows(pot, throughMonth: last)
            for payment in flows.payments where payment.isProjected && payment.date < planLimit && payment.amount > 0 {
                let month = YearMonth(date: payment.date)
                fresh.append(PotEntry(id: InterestRules.entryID(for: pot.id, month: month), potID: pot.id,
                                      date: payment.date, amount: payment.amount, kind: .interest,
                                      note: "Rente \(Fmt.percent(pot.interestRate)) per jaar"))
            }
        }
        potEntries.append(contentsOf: fresh)
        return fresh.count
    }
}
