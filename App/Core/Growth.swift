import Foundation

/// Eenheid van de tijdshorizon in de toekomstschatting.
enum HorizonUnit: String, CaseIterable, Identifiable {
    case days, weeks, months, years
    var id: String { rawValue }

    var title: String {
        switch self {
        case .days: return "dagen"
        case .weeks: return "weken"
        case .months: return "maanden"
        case .years: return "jaren"
        }
    }

    /// Een gemiddelde maand heeft 30,4375 dagen (365,25 / 12).
    func months(_ value: Double) -> Double {
        switch self {
        case .days: return value / 30.4375
        case .weeks: return value * 7 / 30.4375
        case .months: return value
        case .years: return value * 12
        }
    }
}

enum ReturnScenario: String, CaseIterable, Identifiable {
    case cautious, expected, optimistic
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cautious: return "Voorzichtig"
        case .expected: return "Verwacht"
        case .optimistic: return "Optimistisch"
        }
    }

    /// Verschil met het verwachte rendement, in procentpunten per jaar.
    var delta: Double {
        switch self {
        case .cautious: return -0.02
        case .expected: return 0
        case .optimistic: return 0.02
        }
    }
}

struct ProjectionResult: Equatable {
    var total: Double
    /// Startbedrag plus alle inleg.
    var contributed: Double
    var growth: Double { (total - contributed).cents }
    /// Totaal in koopkracht van vandaag.
    var real: Double
}

struct CurvePoint: Identifiable, Equatable {
    var t: Double      // in de gekozen eenheid
    var value: Double
    var id: Double { t }
}

/// Rente-op-rente rekenwerk. Rendementen zijn per jaar, groei en inleg gaan per maand
/// (inleg aan het eind van de maand).
enum Growth {
    static let fallbackReturn = 0.05
    static let maxMonths = 1200 // 100 jaar

    static func monthlyRate(annual: Double) -> Double {
        let a = max(annual, -0.99)
        return pow(1 + a, 1.0 / 12.0) - 1
    }

    /// Reëel rendement: nominaal rendement gecorrigeerd voor inflatie.
    static func realReturn(nominal: Double, inflation: Double) -> Double {
        (1 + nominal) / (1 + inflation) - 1
    }

    static func deflate(_ value: Double, years: Double, inflation: Double) -> Double {
        value / pow(1 + inflation, years)
    }

    /// Waarde na `months` maanden (mag een gebroken getal zijn, voor dagen en weken).
    static func futureValue(start: Double, monthly: Double, annualReturn: Double, months: Double) -> Double {
        let t = max(0, months)
        let rm = monthlyRate(annual: annualReturn)
        let g = 1 + rm
        let whole = t.rounded(.down)
        let frac = t - whole
        let startPart = start * pow(g, t)
        let contribution: Double
        if abs(rm) < 1e-12 {
            contribution = monthly * whole
        } else {
            contribution = monthly * (pow(g, whole) - 1) / rm * pow(g, frac)
        }
        return startPart + contribution
    }

    static func projection(start: Double, monthly: Double, annualReturn: Double, months: Double, inflation: Double) -> ProjectionResult {
        let total = futureValue(start: start, monthly: monthly, annualReturn: annualReturn, months: months)
        let contributed = start + monthly * max(0, months).rounded(.down)
        let real = deflate(total, years: months / 12, inflation: inflation)
        return ProjectionResult(total: total.cents, contributed: contributed.cents, real: real.cents)
    }

    /// Punten voor een grafiek van 0 t/m `totalMonths`, met de x-as in `unit`.
    static func curve(start: Double, monthly: Double, annualReturn: Double, totalMonths: Double, unit: HorizonUnit, steps: Int = 36) -> [CurvePoint] {
        guard steps > 0 else { return [] }
        var points: [CurvePoint] = []
        for i in 0...steps {
            let months = totalMonths * Double(i) / Double(steps)
            let value = futureValue(start: start, monthly: monthly, annualReturn: annualReturn, months: months)
            let x: Double
            switch unit {
            case .days: x = months * 30.4375
            case .weeks: x = months * 30.4375 / 7
            case .months: x = months
            case .years: x = months / 12
            }
            points.append(CurvePoint(t: x, value: value.cents))
        }
        return points
    }

    /// Waarde per maand 0...months (voor doelgrafieken).
    static func monthlySeries(start: Double, monthly: Double, annualReturn: Double, months: Int, stepUp: Double = 0, oneOff: Double = 0) -> [Double] {
        guard months >= 0 else { return [] }
        let rm = monthlyRate(annual: annualReturn)
        var values: [Double] = []
        var v = start + oneOff
        var c = monthly
        values.append(v)
        if months == 0 { return values }
        for n in 1...months {
            v = v * (1 + rm) + c
            values.append(v)
            if n % 12 == 0 { c *= (1 + stepUp) }
        }
        return values
    }

    /// Na hoeveel maanden bereik je `target`? nil = niet binnen 100 jaar.
    /// `stepUp`: je inleg stijgt elk jaar met dit percentage. `oneOff`: eenmalige storting nu.
    static func monthsToReach(target: Double, start: Double, monthly: Double, annualReturn: Double,
                              stepUp: Double = 0, oneOff: Double = 0, maxMonths: Int = Growth.maxMonths) -> Int? {
        var v = start + oneOff
        if v >= target { return 0 }
        let rm = monthlyRate(annual: annualReturn)
        var c = monthly
        for n in 1...maxMonths {
            v = v * (1 + rm) + c
            if v >= target { return n }
            if n % 12 == 0 { c *= (1 + stepUp) }
        }
        return nil
    }

    /// Maandelijkse inleg die nodig is om in `months` maanden `target` te halen.
    static func requiredMonthly(target: Double, start: Double, annualReturn: Double, months: Int) -> Double {
        guard months > 0 else { return max(0, target - start).cents }
        let rm = monthlyRate(annual: annualReturn)
        let grownStart = start * pow(1 + rm, Double(months))
        let gap = target - grownStart
        if gap <= 0 { return 0 }
        if abs(rm) < 1e-12 { return (gap / Double(months)).cents }
        let factor = (pow(1 + rm, Double(months)) - 1) / rm
        return max(0, gap / factor).cents
    }

    /// Hoeveel kapitaal je nodig hebt om `monthlyAmount` per maand op te nemen volgens de opnameregel (bijv. 4%).
    static func capitalNeeded(monthlyAmount: Double, withdrawalRate: Double) -> Double {
        guard withdrawalRate > 0 else { return 0 }
        return (monthlyAmount * 12 / withdrawalRate).cents
    }

    /// Kapitaal dat nodig is om `years` jaar lang `monthlyAmount` per maand op te nemen (lijfrente).
    static func annuityCapital(monthlyAmount: Double, years: Int, annualReturn: Double) -> Double {
        guard years > 0 else { return 0 }
        let yearly = monthlyAmount * 12
        if abs(annualReturn) < 1e-12 { return (yearly * Double(years)).cents }
        let factor = (1 - pow(1 + annualReturn, -Double(years))) / annualReturn
        return (yearly * factor).cents
    }
}
