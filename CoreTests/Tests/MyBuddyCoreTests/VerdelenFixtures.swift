import XCTest
import Foundation
@testable import MyBuddyCore

// Hulpjes voor de tests van de nieuwe verdeelmogelijkheden (docs/work/plan2.md): een vaste dataset in het formaat van vlak voor
// deze ronde (HEAD c0130b2 / 0333505, met startdatum maar zonder extra bedrag, extra overschrijfdata, bankrij of doel met meer potten),
// waarvan de uitvoer van de coderingen als tekst is vastgelegd in `VerdelenLegacyOutput.swift`.

/// Een vast UUID met een nummer erin, zodat de dataset en de vastgelegde uitvoer altijd hetzelfde zijn.
func verdelenFixtureID(_ number: Int) -> UUID {
    let digits = String(number)
    let padded = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    return UUID(uuidString: "7E4D0000-0000-4000-8000-" + padded) ?? UUID()
}

/// Een vast moment: dagen na 1 januari 2026 12:00 UTC plus uren (de coderingen schrijven ISO 8601 in UTC).
func verdelenFixtureDate(day: Int, hour: Double = 0) -> Date {
    Date(timeIntervalSince1970: 1_767_268_800 + Double(day) * 86_400 + hour * 3_600)
}

/// De dataset van het oude formaat: percentage-potten (op salaris en op alle inkomsten), een pot met een vast bedrag en een eigen
/// overschrijfdag, een belegging met een percentage en een met een vast bedrag, een doel met een pot (en een doel met eigen waarden
/// en een met beleggingen), maanden met `allocations` en `percentAllocations`, een salaris met uurloon en een startdatum midden in
/// de maand. Een gebruiker die de nieuwe functies nooit gebruikt krijgt precies zo'n bestand; de coderingen moeten er byte voor
/// byte hetzelfde van maken als vóór deze ronde.
func verdelenFixtureLegacyData() -> FinanceData {
    var d = FinanceData(startMonth: YearMonth(year: 2026, month: 3))
    d.setStart(CalendarDay(year: 2026, month: 3, day: 12))
    d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 17.5, hoursPerWeek: 36, payDay: 24)

    let buffer = verdelenFixtureID(1)
    let holiday = verdelenFixtureID(2)
    let car = verdelenFixtureID(3)
    let world = verdelenFixtureID(4)
    let bonds = verdelenFixtureID(5)

    var bufferPot = Pot(id: buffer, name: "Buffer", symbol: "shield.lefthalf.filled", colorIndex: 1, goalAmount: 6_000,
                        goalDate: verdelenFixtureDate(day: 500), monthlyContribution: 200, startMonth: YearMonth(year: 2026, month: 3),
                        createdAt: verdelenFixtureDate(day: 1))
    bufferPot.interestRate = 0.015
    bufferPot.interestPayout = .monthly
    bufferPot.transferDay = 5
    var holidayPot = Pot(id: holiday, name: "Vakantie", symbol: "airplane", colorIndex: 3, goalAmount: nil, goalDate: nil,
                         monthlyContribution: 100, startMonth: YearMonth(year: 2026, month: 3), createdAt: verdelenFixtureDate(day: 2))
    holidayPot.contributionMode = .percentage
    holidayPot.contributionPercent = 4.25
    holidayPot.contributionBasis = .salary
    var carPot = Pot(id: car, name: "Auto", symbol: "car", colorIndex: 5, goalAmount: 4_000, goalDate: nil, monthlyContribution: 50,
                     startMonth: YearMonth(year: 2026, month: 4), createdAt: verdelenFixtureDate(day: 3))
    carPot.contributionMode = .percentage
    carPot.contributionPercent = 2
    carPot.contributionBasis = .allIncome
    d.pots = [bufferPot, holidayPot, carPot]

    var worldFund = Holding(id: world, name: "Wereldfonds", kind: .etf, ticker: "VWCE.DE", units: 8, investedTotal: 900,
                            expectedReturn: 0.06, annualCost: 0.002, monthlyContribution: 60,
                            startMonth: YearMonth(year: 2026, month: 3), transferDay: 12,
                            snapshots: [ValueSnapshot(id: verdelenFixtureID(31), date: verdelenFixtureDate(day: 30), value: 950, invested: 900)],
                            lastPrice: 119, lastPriceDate: verdelenFixtureDate(day: 31), priceCurrency: "EUR")
    worldFund.contributionMode = .percentage
    worldFund.contributionPercent = 8
    worldFund.contributionBasis = .salary
    let bondFund = Holding(id: bonds, name: "Obligaties", kind: .etf, ticker: nil, units: 0, investedTotal: 0,
                           expectedReturn: 0.03, annualCost: 0.001, monthlyContribution: 40,
                           startMonth: YearMonth(year: 2026, month: 3), transferDay: nil, snapshots: [],
                           lastPrice: nil, lastPriceDate: nil, priceCurrency: nil)
    d.holdings = [worldFund, bondFund]

    var march = MonthPlan()
    march.extraIncome = [MoneyLine(id: verdelenFixtureID(11), name: "Bijverdienste", amount: 250, isRecurring: false, kind: .fixed,
                                   day: 20, potShares: [], seriesID: nil, isException: false)]
    march.expenses = [
        MoneyLine(id: verdelenFixtureID(13), name: "Huur", amount: 950, isRecurring: true, kind: .fixed, day: 1, potShares: [],
                  seriesID: verdelenFixtureID(14), isException: false),
        MoneyLine(id: verdelenFixtureID(15), name: "Fiets", amount: 120, isRecurring: false, kind: .variable, day: 15,
                  potShares: [PotShare(id: verdelenFixtureID(16), potID: buffer, amount: 50)], seriesID: nil, isException: false)
    ]
    march.allocations = [buffer.uuidString: 200, bonds.uuidString: 40]
    march.percentAllocations = [holiday.uuidString: PercentRule(percent: 4.25, basis: .salary),
                                world.uuidString: PercentRule(percent: 8, basis: .salary)]
    d.months["2026-03"] = march
    var april = MonthPlan()
    april.hoursOverride = 120.5
    april.transferDay = 7
    april.allocations = [buffer.uuidString: 250, holiday.uuidString: 80, bonds.uuidString: 40]
    april.percentAllocations = [car.uuidString: PercentRule(percent: 3, basis: .allIncome),
                                world.uuidString: PercentRule(percent: 7.5, basis: .allIncome)]
    d.months["2026-04"] = april
    var may = MonthPlan()
    may.salaryOverride = 2_400
    d.months["2026-05"] = may

    d.potEntries = [
        PotEntry(id: verdelenFixtureID(21), potID: buffer, date: verdelenFixtureDate(day: 66, hour: 1), amount: 800, kind: .opening,
                 note: "", pairID: nil),
        PotEntry(id: verdelenFixtureID(22), potID: buffer, date: verdelenFixtureDate(day: 80), amount: -75, kind: .withdrawal,
                 note: "Fiets", pairID: nil)
    ]
    d.bankSnapshots = [BankSnapshot(id: verdelenFixtureID(41), date: verdelenFixtureDate(day: 70, hour: 0.5), balance: 2_150.5, note: "Begin")]
    d.bankEntries = [BankEntry(id: verdelenFixtureID(51), date: verdelenFixtureDate(day: 75), amount: 60, kind: .deposit, note: "Verjaardag",
                               potID: nil, pairID: nil)]

    var vacation = LifeGoal(id: verdelenFixtureID(61), name: "Vakantie Japan", kind: .vacation)
    vacation.targetAmount = 3_500
    vacation.targetDate = verdelenFixtureDate(day: 300)
    vacation.funding = .pot(holiday)
    var own = LifeGoal(id: verdelenFixtureID(62), name: "Camper", kind: .custom)
    own.targetAmount = 12_000
    own.funding = .custom(start: 500, monthly: 150, annualReturn: 0.03)
    let retirement = LifeGoal(id: verdelenFixtureID(63), name: "Pensioen", kind: .retirement)
    d.goals = [vacation, own, retirement]
    d.homePotIDs = [holiday, buffer]
    d.homeHoldingIDs = [world]
    d.settings.bankBufferMonths = 3
    d.modifiedAt = verdelenFixtureDate(day: 90, hour: 3.25)
    return d
}
