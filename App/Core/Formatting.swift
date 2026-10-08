import Foundation

/// Opmaak van bedragen, percentages en periodes in het Nederlands.
enum Fmt {
    static let locale = Locale(identifier: "nl_NL")

    private static func formatter(fractionDigits: ClosedRange<Int>) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.minimumFractionDigits = fractionDigits.lowerBound
        f.maximumFractionDigits = fractionDigits.upperBound
        return f
    }

    /// Standaard weergave van bedragen: afgerond op hele euro's, "€ 1.235". Overal in de app gebruiken.
    static func euro(_ value: Double) -> String {
        euroWhole(value)
    }

    /// "€ 1.235" (zonder centen). Rondt af en toont nooit "-€ 0".
    static func euroWhole(_ value: Double) -> String {
        var rounded = value.rounded()
        if rounded == 0 { rounded = 0 }
        return formatter(fractionDigits: 0...0).string(from: NSNumber(value: rounded)) ?? "€ \(Int(rounded))"
    }

    /// "€ 1.234,56": alleen voor bedragen waar centen ertoe doen, zoals een uurloon of een koers.
    static func euroExact(_ value: Double) -> String {
        var cents = (value * 100).rounded() / 100
        if cents == 0 { cents = 0 }
        return formatter(fractionDigits: 2...2).string(from: NSNumber(value: cents)) ?? "€ \(value)"
    }

    /// Kort voor assen: "€1,2k", "€3,4 mln".
    static func compact(_ value: Double) -> String {
        let a = abs(value)
        let sign = value < 0 ? "-" : ""
        if a >= 1_000_000 { return sign + "€" + trimmed(a / 1_000_000, 1) + " mln" }
        if a >= 10_000 { return sign + "€" + trimmed(a / 1_000, 0) + "k" }
        if a >= 1_000 { return sign + "€" + trimmed(a / 1_000, 1) + "k" }
        return sign + "€" + trimmed(a, 0)
    }

    private static func trimmed(_ v: Double, _ digits: Int) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// Breuk naar percentage: 0.065 → "6,5%".
    static func percent(_ fraction: Double, digits: Int = 1) -> String {
        trimmed(fraction * 100, digits) + "%"
    }

    /// Getal voor invulvelden: 1234.5 → "1234,5" (zonder duizendtallen).
    static func input(_ value: Double, maxDigits: Int = 2) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = maxDigits
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static let monthNames = ["januari", "februari", "maart", "april", "mei", "juni",
                             "juli", "augustus", "september", "oktober", "november", "december"]
    static let shortMonthNames = ["jan", "feb", "mrt", "apr", "mei", "jun",
                                  "jul", "aug", "sep", "okt", "nov", "dec"]

    /// "oktober 2026"
    static func month(_ m: YearMonth) -> String { "\(monthNames[m.month - 1]) \(m.year)" }

    /// "okt"
    static func shortMonth(_ m: YearMonth) -> String { shortMonthNames[m.month - 1] }

    /// "okt '26"
    static func shortMonthYear(_ m: YearMonth) -> String {
        let yy = m.year % 100
        return "\(shortMonthNames[m.month - 1]) '\(yy < 10 ? "0\(yy)" : "\(yy)")"
    }

    /// Titel van een periode, bijv. "oktober 2026", "1e halfjaar 2026", "2026".
    static func period(_ mode: PeriodMode, containing m: YearMonth) -> String {
        switch mode {
        case .month: return month(m)
        case .halfYear: return "\(m.half)e halfjaar \(m.year)"
        case .year: return "\(m.year)"
        }
    }

    /// "3 jaar en 4 maanden", "5 maanden", "nu al bereikt".
    static func duration(months: Int) -> String {
        if months <= 0 { return "nu al bereikt" }
        let years = months / 12
        let rest = months % 12
        let y = years == 1 ? "1 jaar" : "\(years) jaar"
        let m = rest == 1 ? "1 maand" : "\(rest) maanden"
        if years == 0 { return m }
        if rest == 0 { return y }
        return "\(y) en \(m)"
    }

    static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    static func dateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: d)
    }
}

/// Leest bedragen die mensen intikken: "12,5", "1.234,56", "€ 12.50", "1 234".
enum AmountParser {
    static func parse(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "€", with: "")
        s = s.replacingOccurrences(of: "%", with: "")
        s = s.replacingOccurrences(of: " ", with: "")
        s = s.replacingOccurrences(of: "\u{00A0}", with: "")
        guard !s.isEmpty else { return nil }

        let hasComma = s.contains(",")
        let dotCount = s.filter { $0 == "." }.count
        if hasComma {
            // Komma is de decimaalscheiding, punten zijn duizendtallen.
            s = s.replacingOccurrences(of: ".", with: "")
            s = s.replacingOccurrences(of: ",", with: ".")
        } else if dotCount > 1 {
            // "1.234.567" → duizendtallen.
            s = s.replacingOccurrences(of: ".", with: "")
        }
        else if dotCount == 1, let dot = s.firstIndex(of: ".") {
            // "1.234" (precies drie cijfers na de punt) is een duizendtal, "12.5" een decimaal.
            let after = s[s.index(after: dot)...]
            if after.count == 3, !s.hasPrefix("0.") { s = s.replacingOccurrences(of: ".", with: "") }
        }
        return Double(s)
    }
}
