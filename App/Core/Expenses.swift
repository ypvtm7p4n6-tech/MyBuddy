import Foundation

/// Een standaard uitgavenpost met een richtbedrag per maand.
struct StandardExpense: Equatable {
    var name: String
    var amount: Double
    var kind: ExpenseKind
    var symbol: String
}

/// Gangbare Nederlandse huishoudposten met ruwe richtbedragen (alleenstaande volwassene).
/// Het zijn schattingen om mee te beginnen; de gebruiker past ze aan.
enum StandardExpenses {
    static let all: [StandardExpense] = fixed + variable

    static let fixed: [StandardExpense] = [
        StandardExpense(name: "Huur of hypotheek", amount: 900, kind: .fixed, symbol: "house.fill"),
        StandardExpense(name: "Gas, water en licht", amount: 150, kind: .fixed, symbol: "bolt.fill"),
        StandardExpense(name: "Zorgverzekering", amount: 150, kind: .fixed, symbol: "cross.case.fill"),
        StandardExpense(name: "Gemeente- en waterschapsbelasting", amount: 60, kind: .fixed, symbol: "building.columns.fill"),
        StandardExpense(name: "Inboedel- en aansprakelijkheidsverzekering", amount: 20, kind: .fixed, symbol: "shield.fill"),
        StandardExpense(name: "Internet en tv", amount: 50, kind: .fixed, symbol: "wifi"),
        StandardExpense(name: "Mobiele telefoon", amount: 25, kind: .fixed, symbol: "iphone"),
        StandardExpense(name: "Abonnementen en lidmaatschappen", amount: 40, kind: .fixed, symbol: "repeat")
    ]

    static let variable: [StandardExpense] = [
        StandardExpense(name: "Boodschappen", amount: 350, kind: .variable, symbol: "cart.fill"),
        StandardExpense(name: "Uit eten en drinken", amount: 80, kind: .variable, symbol: "fork.knife"),
        StandardExpense(name: "Vervoer (brandstof of OV)", amount: 100, kind: .variable, symbol: "car.fill"),
        StandardExpense(name: "Kleding en schoenen", amount: 60, kind: .variable, symbol: "tshirt.fill"),
        StandardExpense(name: "Persoonlijke verzorging", amount: 40, kind: .variable, symbol: "comb.fill"),
        StandardExpense(name: "Vrije tijd en hobby's", amount: 80, kind: .variable, symbol: "gamecontroller.fill"),
        StandardExpense(name: "Cadeaus en uitjes", amount: 40, kind: .variable, symbol: "gift.fill"),
        StandardExpense(name: "Onvoorzien", amount: 50, kind: .variable, symbol: "questionmark.circle.fill")
    ]
}

/// Wat er in een maand binnenkomt, uitgaat en overblijft.
struct ExpenseOverview: Equatable {
    var income: Double
    var fixed: Double
    var variable: Double
    var toPots: Double
    var toInvestments: Double
    /// Het deel van de uitgaven dat uit spaarpotten betaald wordt. Dat kost het maandbudget niets.
    var fromPots: Double = 0

    private func cents(_ value: Double) -> Int { CentsMath.int(value) }

    /// Totaal van alle uitgaven, ook wat uit spaarpotten komt.
    var expenses: Double { CentsMath.value(cents(fixed) + cents(variable)) }
    /// Uitgaven die van de bankrekening gaan.
    var expensesFromBank: Double { CentsMath.value(cents(fixed) + cents(variable) - cents(fromPots)) }
    /// Wat er na de uitgaven nog is (alleen wat van de bank gaat telt mee).
    var leftAfterExpenses: Double {
        CentsMath.value(cents(income) - (cents(fixed) + cents(variable) - cents(fromPots)))
    }
    /// Wat er na uitgaven en overschrijvingen naar spaarpotten en beleggingen overblijft.
    /// Gelijk aan `FinanceData.remaining(in:)`.
    var leftAfterTransfers: Double {
        CentsMath.value(cents(income) - (cents(fixed) + cents(variable) - cents(fromPots))
                        - cents(toPots) - cents(toInvestments))
    }
    /// Aandeel van het inkomen dat naar vaste uitgaven gaat (0...1+); 0 zonder inkomen.
    var fixedShare: Double { income > 0 ? fixed / income : 0 }
    var variableShare: Double { income > 0 ? variable / income : 0 }
}

extension FinanceData {
    func expenseLines(in month: YearMonth, kind: ExpenseKind) -> [MoneyLine] {
        plan(for: month).expenses.filter { $0.kind == kind }
    }

    /// De uitgaven van een soort in `month` die meetellen: in de startmaand alleen die op of na de startdag.
    func countedExpenseLines(in month: YearMonth, kind: ExpenseKind) -> [MoneyLine] {
        plan(for: month).expenses.filter { $0.kind == kind && expenseCounts($0, in: month) }
    }

    func expenseOverview(in month: YearMonth) -> ExpenseOverview {
        let lines = month >= startMonth ? plan(for: month).expenses.filter { expenseCounts($0, in: month) } : []
        func total(_ kind: ExpenseKind) -> Double {
            CentsMath.value(CentsMath.sum(lines.filter { $0.kind == kind }.map { CentsMath.int($0.amount) }))
        }
        let figures = monthFigures(month)
        return ExpenseOverview(income: CentsMath.value(figures.income),
                               fixed: total(.fixed),
                               variable: total(.variable),
                               toPots: CentsMath.value(figures.saved),
                               toInvestments: CentsMath.value(figures.invested),
                               fromPots: CentsMath.value(figures.fromPots))
    }

    /// Welke standaardposten ontbreken nog in deze maand (op naam, hoofdletterongevoelig).
    func missingStandardExpenses(in month: YearMonth) -> [StandardExpense] {
        let names = Set(plan(for: month).expenses.map { $0.name.lowercased() })
        return StandardExpenses.all.filter { !names.contains($0.name.lowercased()) }
    }

    /// Vult de standaardposten in met een richtbedrag. Bestaande regels blijven staan.
    /// Geeft het aantal toegevoegde regels terug.
    @discardableResult
    mutating func fillStandardExpenses(in month: YearMonth) -> Int {
        let missing = missingStandardExpenses(in: month)
        guard !missing.isEmpty else { return 0 }
        // Een standaardpost waarvan er al een reeks bestaat die in deze maand is overgeslagen of pas later begint, komt terug
        // in diezelfde reeks (een tweede reeks zou vanaf de maand erna dubbel staan).
        for item in missing {
            addOrResumeRecurringLine(MoneyLine(name: item.name, amount: item.amount, isRecurring: true, kind: item.kind),
                                     kind: .expense, in: month)
        }
        return missing.count
    }
}
