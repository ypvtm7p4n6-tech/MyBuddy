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
        // Twee FNV-1a-hashes met verschillende startwaarden, daarna door een mixer gehaald.
        var h1: UInt64 = 0xcbf2_9ce4_8422_2325
        var h2: UInt64 = 0x9e37_79b9_7f4a_7c15
        for byte in text.utf8 {
            h1 = (h1 ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            h2 = (h2 ^ UInt64(byte) ^ 0xa5) &* 0x0000_0100_0000_01b3
            h2 = (h2 << 13) | (h2 >> 51)
        }
        let a = mix(h1)
        let b = mix(h2 ^ a)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: a >> UInt64(56 - 8 * i))
            bytes[8 + i] = UInt8(truncatingIfNeeded: b >> UInt64(56 - 8 * i))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // versie 5-achtig
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func mix(_ x: UInt64) -> UInt64 {
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
}

/// Alles wat het saldo van een pot bepaalt: de gewone boekingen en de rente-uitbetalingen.
/// Opgeslagen uitbetalingen staan alleen in `payments` (niet in `ledger`), zodat ze nooit dubbel tellen.
struct PotFlows {
    var ledger: CentsLedger
    /// Opgeslagen en verwachte uitbetalingen, oplopend op datum.
    var payments: [InterestPayment]

    /// Saldo in hele centen vóór `limit`.
    func cents(before limit: Date) -> Int {
        var total = ledger.sum(before: limit)
        for payment in payments {
            if payment.date >= limit { break }
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
    /// De periode zijn de maanden tussen twee uitbetalingen, eindigend in de uitbetaalmaand (bij maandelijks
    /// dus alleen die maand), en alleen maanden vanaf de startmaand van de pot. Eerdere uitbetalingen (opgeslagen of
    /// verwacht) tellen mee in het saldo, de uitbetaling zelf niet. Afgerond op centen, nooit negatief.
    func potFlows(_ pot: Pot, throughMonth last: YearMonth) -> PotFlows {
        let payoutMonths = interestPayoutMonths(for: pot, through: last)
        guard !payoutMonths.isEmpty else {
            return PotFlows(ledger: potLedger(for: pot, throughMonth: last), payments: [])
        }

        let managedIDs = Set(payoutMonths.map { InterestRules.entryID(for: pot.id, month: $0) })
        let ledger = potLedger(for: pot, throughMonth: last, excluding: managedIDs)

        var stored: [UUID: PotEntry] = [:]
        for e in potEntries where e.potID == pot.id && managedIDs.contains(e.id) && stored[e.id] == nil {
            stored[e.id] = e
        }

        let interval = max(1, pot.interestPayout.intervalMonths)
        let firstMonth = InterestRules.firstMonth(for: pot, dataStart: startMonth)
        let cal = YearMonth.calendar
        var payments: [InterestPayment] = []

        for month in payoutMonths {
            let entryID = InterestRules.entryID(for: pot.id, month: month)
            let paymentID = InterestRules.paymentID(for: pot.id, month: month)

            if let entry = stored[entryID] {
                payments.append(InterestPayment(potID: pot.id, date: entry.date, amount: entry.amount,
                                                isProjected: false, id: paymentID))
                continue
            }

            var sum = 0
            var m = max(month.adding(-(interval - 1)), firstMonth)
            while m <= month {
                let limit = DayMath.nextDayStart(after: m.date(day: 1, calendar: cal), calendar: cal)
                var balance = ledger.sum(before: limit)
                for earlier in payments where earlier.date < limit {
                    balance = CentsMath.add(balance, CentsMath.int(earlier.amount))
                }
                sum = CentsMath.add(sum, balance)
                m = m.adding(1)
            }
            let raw = (pot.interestRate * Double(sum) / 12).rounded()
            guard raw.isFinite, raw > 0 else { continue }
            let cents = Int(min(raw, Double(CentsMath.limit)))
            let date = month.date(day: YearMonth.clampedDay(pot.interestPayoutDay), calendar: cal)
            payments.append(InterestPayment(potID: pot.id, date: date, amount: CentsMath.value(cents),
                                            isProjected: true, id: paymentID))
        }
        payments.sort { $0.date < $1.date }
        return PotFlows(ledger: ledger, payments: payments)
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

    /// De eerstvolgende uitbetaling na `today` (verwacht of al opgeslagen). nil zonder rente.
    func nextInterestPayment(for potID: UUID, asOf today: Date = Date()) -> InterestPayment? {
        guard let pot = self.pot(potID), InterestRules.isActive(pot) else { return nil }
        let flows = potFlows(pot, throughMonth: YearMonth(date: today).adding(26))
        return flows.payments.first { $0.date > today }
    }

    // MARK: Boeken

    /// Boekt de uitbetalingen die tot en met `date` aan de beurt waren en nog niet zijn opgeslagen als
    /// `PotEntry(kind: .interest)`. Het id is vast (afgeleid van pot en maand), dus twee aanroepen of twee apparaten
    /// maken nooit dubbele boekingen. Geeft het aantal nieuwe boekingen terug.
    @discardableResult
    mutating func applyDueInterest(upTo date: Date = Date()) -> Int {
        let last = YearMonth(date: date)
        var fresh: [PotEntry] = []
        for pot in pots where InterestRules.isActive(pot) {
            let flows = potFlows(pot, throughMonth: last)
            for payment in flows.payments where payment.isProjected && payment.date <= date && payment.amount > 0 {
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
