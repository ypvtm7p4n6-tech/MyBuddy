import XCTest
import Foundation
@testable import MyBuddyCore

// Hulpjes voor de tests van de startdatum (golf 1 van docs/work/plan.md): een vaste dataset in het oude formaat, zonder startdatum,
// waarvan de uitvoer van de coderingen van HEAD (b944e43) als tekst is vastgelegd in `StartDateLegacyOutput.swift`.

/// Een vast UUID met een nummer erin, zodat de dataset en de vastgelegde uitvoer altijd hetzelfde zijn.
func startFixtureID(_ number: Int) -> UUID {
    let digits = String(number)
    let padded = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    return UUID(uuidString: "5AD7E000-0000-4000-8000-" + padded) ?? UUID()
}

/// Een vast moment: dagen na 1 januari 2026 12:00 UTC plus uren (de coderingen schrijven ISO 8601 in UTC, dus de tijdzone van de
/// machine speelt geen rol bij het vergelijken).
func startFixtureDate(day: Int, hour: Double = 0) -> Date {
    Date(timeIntervalSince1970: 1_767_268_800 + Double(day) * 86_400 + hour * 3_600)
}

/// De dataset van het oude formaat: elk veld van `FinanceData` heeft een waarde, maar GEEN startdatum en geen werkuren. Een
/// gebruiker die nooit een startdatum zet, krijgt precies zo'n bestand; de coderingen moeten er byte voor byte hetzelfde van maken
/// als voor de startdatum bestond.
func startFixtureLegacyData() -> FinanceData {
    var d = FinanceData(startMonth: YearMonth(year: 2026, month: 9))
    d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 14.35, hoursPerWeek: 32, payDay: 25)
    d.salary.setSchedule(.weeks, interval: 4, anchor: CalendarDay(year: 2026, month: 9, day: 11))

    let potA = startFixtureID(1)
    let potB = startFixtureID(2)
    let holdingA = startFixtureID(3)

    var buffer = Pot(id: potA, name: "Buffer", symbol: "shield.lefthalf.filled", colorIndex: 1, goalAmount: 5_000,
                     goalDate: startFixtureDate(day: 400), monthlyContribution: 150, startMonth: YearMonth(year: 2026, month: 9),
                     createdAt: startFixtureDate(day: 1))
    buffer.interestRate = 0.02
    buffer.interestPayout = .quarterly
    buffer.interestPayoutDay = 28
    buffer.interestPayoutMonth = 3
    buffer.transferDay = 3
    var holiday = Pot(id: potB, name: "Vakantie", symbol: "airplane", colorIndex: 3, goalAmount: nil, goalDate: nil,
                      monthlyContribution: 100, startMonth: YearMonth(year: 2026, month: 10),
                      createdAt: startFixtureDate(day: 2))
    holiday.contributionMode = .percentage
    holiday.contributionPercent = 3.5
    holiday.contributionBasis = .allIncome
    d.pots = [buffer, holiday]

    var holding = Holding(id: holdingA, name: "Wereldfonds", kind: .etf, ticker: "VWCE.DE", units: 12.5, investedTotal: 1_250,
                          expectedReturn: 0.06, annualCost: 0.002, monthlyContribution: 75,
                          startMonth: YearMonth(year: 2026, month: 9), transferDay: 5,
                          snapshots: [ValueSnapshot(id: startFixtureID(31), date: startFixtureDate(day: 20), value: 1_300, invested: 1_250)],
                          lastPrice: 104.4, lastPriceDate: startFixtureDate(day: 30), priceCurrency: "EUR")
    holding.contributionMode = .percentage
    holding.contributionPercent = 10
    holding.contributionBasis = .salary
    d.holdings = [holding]

    var first = MonthPlan()
    first.extraIncome = [MoneyLine(id: startFixtureID(11), name: "Zorgtoeslag", amount: 120, isRecurring: true, kind: .fixed,
                                   day: 20, potShares: [], seriesID: startFixtureID(12), isException: false)]
    first.expenses = [
        MoneyLine(id: startFixtureID(13), name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 1, potShares: [],
                  seriesID: startFixtureID(14), isException: false),
        MoneyLine(id: startFixtureID(15), name: "Tandarts", amount: 100, isRecurring: false, kind: .variable, day: nil,
                  potShares: [PotShare(id: startFixtureID(16), potID: potA, amount: 40)], seriesID: nil, isException: true)
    ]
    first.allocations = [potA.uuidString: 150, holdingA.uuidString: 75]
    first.transferDay = 3
    first.percentAllocations = [potB.uuidString: PercentRule(percent: 3.5, basis: .allIncome)]
    first.skippedSeries = [startFixtureID(17)]
    first.endedSeries = [startFixtureID(18)]
    d.months["2026-09"] = first
    var second = MonthPlan()
    second.salaryOverride = 2_000
    second.hoursOverride = 120.5
    d.months["2026-10"] = second

    d.potEntries = [
        PotEntry(id: startFixtureID(21), potID: potA, date: startFixtureDate(day: 1, hour: 1), amount: 500, kind: .opening,
                 note: "", pairID: nil),
        PotEntry(id: startFixtureID(22), potID: potA, date: startFixtureDate(day: 12), amount: 50, kind: .deposit,
                 note: "Van bankrekening", pairID: startFixtureID(23)),
        PotEntry(id: startFixtureID(24), potID: potA, date: startFixtureDate(day: 90), amount: 2.5, kind: .interest,
                 note: "Rente 2% per jaar", pairID: nil)
    ]
    d.bankSnapshots = [
        BankSnapshot(id: startFixtureID(41), date: startFixtureDate(day: 2, hour: 0.5), balance: 1_850.25, note: "Begin"),
        BankSnapshot(id: startFixtureID(42), date: startFixtureDate(day: 40), balance: -12.5, note: "")
    ]
    d.bankEntries = [
        BankEntry(id: startFixtureID(51), date: startFixtureDate(day: 12), amount: -50, kind: .toPot, note: "Naar Buffer",
                  potID: potA, pairID: startFixtureID(23)),
        BankEntry(id: startFixtureID(52), date: startFixtureDate(day: 15), amount: 80, kind: .deposit, note: "", potID: nil, pairID: nil)
    ]
    var goal = LifeGoal(id: startFixtureID(61), name: "Vakantie Japan", kind: .vacation)
    goal.targetAmount = 3_500
    goal.targetDate = startFixtureDate(day: 300)
    goal.funding = .pot(potA)
    d.goals = [goal]
    d.homePotIDs = [potB, potA]
    d.homeHoldingIDs = [holdingA]
    d.settings.inflation = 0.025
    d.settings.bankBufferMonths = 3
    d.settings.blockOrder = ["overview": ["upcoming", "pots"]]
    d.appliedAccelerators = [AppliedAccelerator(id: startFixtureID(71), acceleratorID: "savings-rate", goalID: startFixtureID(61),
                                                title: "Hogere spaarrente", date: startFixtureDate(day: 50),
                                                summary: ["Rente van 1% naar 2%"], before: AcceleratorBackup())]
    d.modifiedAt = startFixtureDate(day: 60, hour: 3.25)
    return d
}

// MARK: - Een eenvoudige begroting voor de rekenvoorbeelden

/// Een moment op een dag van een maand, lokale tijd (de rekenmotor werkt in de kalender van het apparaat).
func startMoment(_ month: YearMonth, _ dayNumber: Int, hour: Int = 12) -> Date {
    YearMonth.calendar.date(from: DateComponents(year: month.year, month: month.month, day: dayNumber, hour: hour)) ?? month.firstDay
}

/// Een dag in oktober 2026.
func startOct(_ dayNumber: Int) -> CalendarDay {
    CalendarDay(year: 2026, month: 10, day: dayNumber)
}

/// Oktober 2026 met een vast salaris van 3.000 op de 25e (maandelijks), huur van 900 op de 1e, boodschappen van 350 op de 10e, een
/// abonnement van 20 zonder dag (de 1e), een toeslag van 120 op de 20e (elke maand) en een bijverdienste van 200 zonder dag (de
/// salarisdag, alleen in oktober). Zonder startdatum: inkomen 3.320 en uitgaven 1.270.
func startBaseData() -> FinanceData {
    var d = FinanceData(startMonth: oct2026)
    d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
    var plan = MonthPlan()
    plan.expenses = [
        MoneyLine(name: "Huur", amount: 900, isRecurring: true, kind: .fixed, day: 1),
        MoneyLine(name: "Boodschappen", amount: 350, isRecurring: true, kind: .variable, day: 10),
        MoneyLine(name: "Abonnement", amount: 20, isRecurring: true, kind: .fixed)
    ]
    plan.extraIncome = [
        MoneyLine(name: "Toeslag", amount: 120, isRecurring: true, day: 20),
        MoneyLine(name: "Bijverdienste", amount: 200, isRecurring: false)
    ]
    d.months[oct2026.key] = plan
    return d
}

/// De cijfers van een maand in euro's, om de verwachting als getal te kunnen schrijven.
struct StartFigures: Equatable {
    var income: Double
    var expenses: Double
    var saved: Double = 0
    var invested: Double = 0

    init(income: Double, expenses: Double, saved: Double = 0, invested: Double = 0) {
        self.income = income
        self.expenses = expenses
        self.saved = saved
        self.invested = invested
    }

    init(_ d: FinanceData, _ month: YearMonth) {
        let f = d.monthFigures(month)
        income = CentsMath.value(f.income)
        expenses = CentsMath.value(f.expenses)
        saved = CentsMath.value(f.saved)
        invested = CentsMath.value(f.invested)
    }
}
