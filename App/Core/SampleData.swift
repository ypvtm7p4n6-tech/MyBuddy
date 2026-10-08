import Foundation

extension FinanceData {
    /// Voorbeelddata om de app uit te proberen. Past zich aan de huidige datum aan.
    static func sample(now: Date = Date()) -> FinanceData {
        let current = YearMonth(date: now)
        let start = current.adding(-5)
        var d = FinanceData(startMonth: start)

        d.salary = SalarySettings(mode: .hourly, fixedMonthly: 0, hourlyRate: 21.5, hoursPerWeek: 36)

        // Terugkerende regels in de eerste maand; de rest wordt daaruit afgeleid.
        var firstPlan = MonthPlan()
        firstPlan.expenses = [
            MoneyLine(name: "Huur", amount: 925, isRecurring: true),
            MoneyLine(name: "Boodschappen", amount: 340, isRecurring: true, kind: .variable),
            MoneyLine(name: "Zorgverzekering", amount: 140, isRecurring: true),
            MoneyLine(name: "Energie en water", amount: 120, isRecurring: true),
            MoneyLine(name: "Vervoer (brandstof of OV)", amount: 80, isRecurring: true, kind: .variable),
            MoneyLine(name: "Abonnementen", amount: 45, isRecurring: true)
        ]
        firstPlan.extraIncome = [MoneyLine(name: "Zorgtoeslag", amount: 120, isRecurring: true)]
        d.months[start.key] = firstPlan

        let openDate = start.firstDay.addingTimeInterval(3_600)
        let buffer = Pot(name: "Buffer", symbol: "shield.lefthalf.filled", colorIndex: 0,
                         goalAmount: 6_000, goalDate: nil, monthlyContribution: 150, startMonth: start)
        let holiday = Pot(name: "Vakantie", symbol: "airplane", colorIndex: 3,
                          goalAmount: 2_400, goalDate: current.adding(8).firstDay, monthlyContribution: 120, startMonth: start)
        let laptop = Pot(name: "Nieuwe laptop", symbol: "laptopcomputer", colorIndex: 4,
                         goalAmount: 1_500, goalDate: nil, monthlyContribution: 75, startMonth: start)
        d.addPot(buffer, openingBalance: 2_800, now: openDate)
        d.addPot(holiday, openingBalance: 450, now: openDate)
        d.addPot(laptop, openingBalance: 300, now: openDate)

        // Beleggingen met zes maanden meetpunten.
        func snapshots(base: Double, monthlyDeposit: Double, monthlyGrowth: Double, investedStart: Double) -> [ValueSnapshot] {
            var list: [ValueSnapshot] = []
            var value = base
            var invested = investedStart
            for i in 0..<6 {
                let m = start.adding(i)
                if i > 0 {
                    value = value * (1 + monthlyGrowth) + monthlyDeposit
                    invested += monthlyDeposit
                }
                list.append(ValueSnapshot(date: m.firstDay.addingTimeInterval(14 * 86_400), value: value.cents, invested: invested.cents))
            }
            return list
        }

        var world = Holding(name: "Wereld ETF", kind: .etf, ticker: "VWCE.DE", units: 40, investedTotal: 4_600,
                            expectedReturn: 0.065, annualCost: 0.002, monthlyContribution: 200, startMonth: start)
        world.snapshots = snapshots(base: 3_700, monthlyDeposit: 200, monthlyGrowth: 0.009, investedStart: 3_600)
        d.holdings.append(world)

        var bitcoin = Holding(name: "Bitcoin", kind: .crypto, ticker: "BTC-EUR", units: 0.02, investedTotal: 1_200,
                              expectedReturn: 0.10, annualCost: 0.005, monthlyContribution: 0, startMonth: start)
        bitcoin.snapshots = snapshots(base: 1_500, monthlyDeposit: 0, monthlyGrowth: 0.02, investedStart: 1_200)
        d.holdings.append(bitcoin)

        var bonds = Holding(name: "Obligatiefonds", kind: .bonds, ticker: nil, units: nil, investedTotal: 2_400,
                            expectedReturn: 0.03, annualCost: 0.003, monthlyContribution: 50, startMonth: start)
        bonds.snapshots = snapshots(base: 2_150, monthlyDeposit: 50, monthlyGrowth: 0.002, investedStart: 2_150)
        d.holdings.append(bonds)

        d.addBankSnapshot(balance: 2_350, note: "Beginsaldo", date: start.firstDay.addingTimeInterval(7_200))

        var pension = LifeGoal(name: "Met pensioen", kind: .retirement)
        pension.monthlySpending = 2_300
        pension.otherMonthlyIncome = 1_200
        pension.currentAge = 34
        pension.withdrawalRate = 0.04
        d.goals.append(pension)

        var partTime = LifeGoal(name: "4 dagen werken", kind: .partTime)
        partTime.hoursFrom = 36
        partTime.hoursTo = 28
        partTime.withdrawalRate = 0.04
        partTime.currentAge = 34
        d.goals.append(partTime)

        d.materialize(upTo: current)
        return d
    }
}
