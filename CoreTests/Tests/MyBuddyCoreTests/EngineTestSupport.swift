import XCTest
import Foundation
@testable import MyBuddyCore

// Hulpjes voor de tests van de rekenmotor (dagen, rente, potdelen).

let engNov2026 = YearMonth(year: 2026, month: 11)
let engDec2026 = YearMonth(year: 2026, month: 12)
let engJan2027 = YearMonth(year: 2027, month: 1)
let engFeb2027 = YearMonth(year: 2027, month: 2)
let engMar2027 = YearMonth(year: 2027, month: 3)
let engJan2028 = YearMonth(year: 2028, month: 1)
let engFeb2028 = YearMonth(year: 2028, month: 2)

/// Een moment op een dag in uren na middernacht (0,5 = 00:30, 8 = 08:00, 18 = 18:00).
/// Handig voor meetmomenten vlak voor of na de gebeurtenissen van 12:00.
func engTime(_ month: YearMonth, _ day: Int, hour: Double) -> Date {
    let midnight = YearMonth.calendar.date(from: DateComponents(year: month.year, month: month.month, day: day)) ?? month.firstDay
    return midnight.addingTimeInterval(hour * 3_600)
}

/// Hele centen van een bedrag, om bedragen exact te vergelijken zonder marge.
func engCents(_ value: Double) -> Int {
    Int((value * 100).rounded())
}

/// Dag van de maand (1...31) van een datum.
func engDayNumber(_ date: Date) -> Int {
    YearMonth.calendar.component(.day, from: date)
}

func engHour(_ date: Date) -> Int {
    YearMonth.calendar.component(.hour, from: date)
}

/// Twee spaarpotten zonder inleg: Vakantie (beginsaldo 400) en Buffer (beginsaldo 900), beide vanaf 1 augustus 2026.
/// De beginsaldi staan op 1 augustus 12:00.
func engTwoPotData() -> (data: FinanceData, vakantie: Pot, buffer: Pot) {
    var d = makeBaseData()
    let vakantie = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: aug2026)
    let buffer = Pot(name: "Buffer", monthlyContribution: 0, startMonth: aug2026)
    d.addPot(vakantie, openingBalance: 400, now: day(aug2026, 1))
    d.addPot(buffer, openingBalance: 900, now: day(aug2026, 1))
    return (d, vakantie, buffer)
}

/// Gegevens zonder inkomen en uitgaven met één spaarpot met rente. Het beginsaldo staat op 1 augustus 12:00.
func engInterestData(rate: Double = 0.02, payout: InterestPayout = .monthly, payoutDay: Int = 28, payoutMonth: Int = 1,
                     opening: Double = 1_200, monthly: Double = 0, start: YearMonth = aug2026,
                     transferDay: Int? = nil) -> (data: FinanceData, pot: Pot) {
    var d = FinanceData(startMonth: aug2026)
    var pot = Pot(name: "Spaar", monthlyContribution: monthly, startMonth: start)
    pot.interestRate = rate
    pot.interestPayout = payout
    pot.interestPayoutDay = payoutDay
    pot.interestPayoutMonth = payoutMonth
    pot.transferDay = transferDay
    d.addPot(pot, openingBalance: opening, now: day(start, 1))
    return (d, pot)
}

/// Pseudo-toevalsgenerator met vaste zaadwaarde, zodat tests herhaalbaar zijn.
struct EngRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 11
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }

    mutating func chance(_ percent: Int) -> Bool {
        int(1...100) <= percent
    }

    /// Een bedrag in hele centen tussen `low` en `high` euro.
    mutating func amount(_ low: Int, _ high: Int) -> Double {
        Double(int(low * 100...high * 100)) / 100
    }
}
