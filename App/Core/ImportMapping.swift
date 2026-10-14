import Foundation

// Rijen uit een spreadsheet herkennen en indelen, en daarna aan de gegevens toevoegen.
//
// Stappen:
// 1. `ImportMapper.draft(from:)` zoekt in elk werkblad de kopregel (omschrijving, bedrag, categorie, ...), bepaalt de
//    kolommen en deelt elke rij in: inkomen, vaste lasten, variabele lasten, spaarpot of belegging. Dat gaat op volgorde van
//    zekerheid: een categoriekolom, een kopje in het blad ("Vaste lasten"), de naam van het blad, een ticker, en dan
//    Nederlandse trefwoorden. Elke rij krijgt een zekerheid (hoog, middel, laag) en een reden.
// 2. De gebruiker kijkt de `ImportDraft` na en past rijen aan.
// 3. `FinanceData.applyImport` voegt de rijen TOE aan een maand. Er wordt niets vervangen of gewist.

// MARK: - Soorten

/// Waar een regel uit het bestand in de app terechtkomt.
enum ImportCategory: String, CaseIterable, Identifiable, Codable {
    case inkomen
    case vasteLasten
    case variabeleLasten
    case spaarpot
    case belegging
    /// Totaalregels en dingen die we niet kunnen gebruiken.
    case overslaan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inkomen: return "Inkomen"
        case .vasteLasten: return "Vaste lasten"
        case .variabeleLasten: return "Variabele lasten"
        case .spaarpot: return "Spaarpotten"
        case .belegging: return "Beleggingen"
        case .overslaan: return "Overslaan"
        }
    }

    var symbol: String {
        switch self {
        case .inkomen: return "eurosign.circle.fill"
        case .vasteLasten: return "house.fill"
        case .variabeleLasten: return "cart.fill"
        case .spaarpot: return "tray.full.fill"
        case .belegging: return "chart.line.uptrend.xyaxis"
        case .overslaan: return "slash.circle"
        }
    }

    /// De soort uitgave, voor vaste en variabele lasten.
    var expenseKind: ExpenseKind? {
        switch self {
        case .vasteLasten: return .fixed
        case .variabeleLasten: return .variable
        default: return nil
        }
    }

    /// Alles behalve `.overslaan`, in de volgorde waarin het in het overzicht staat.
    static var selectable: [ImportCategory] {
        [.inkomen, .vasteLasten, .variabeleLasten, .spaarpot, .belegging]
    }
}

/// Hoe zeker we zijn van de indeling van een rij.
enum ImportConfidence: Int, Comparable, Codable, CaseIterable {
    case laag = 0
    case middel = 1
    case hoog = 2

    static func < (lhs: ImportConfidence, rhs: ImportConfidence) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .laag: return "Lage zekerheid"
        case .middel: return "Gemiddelde zekerheid"
        case .hoog: return "Hoge zekerheid"
        }
    }
}

/// Bij een spaarpot of belegging: is het bedrag wat je elke maand inlegt, of wat er nu in zit?
enum ImportAmountMeaning: String, Codable, CaseIterable, Identifiable {
    case perMaand
    case saldo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .perMaand: return "Inleg per maand"
        case .saldo: return "Huidig bedrag"
        }
    }
}

// MARK: - Rijen en conceptlijst

/// Eén regel uit het bestand, ingedeeld.
struct ImportRow: Identifiable, Equatable {
    var id: UUID
    /// Naam van het blad, of van het bestand bij CSV.
    var sheet: String
    /// Rijnummer in het bestand (1 is de eerste rij); 0 als het er niet één is.
    var sourceRow: Int
    var name: String
    /// Altijd positief; of het eruit of erbij gaat volgt uit de categorie.
    var amount: Double
    var category: ImportCategory
    /// Dag van de maand (1...31), als het bestand die noemt.
    var day: Int?
    var confidence: ImportConfidence
    /// Waarom deze categorie, bijvoorbeeld "woord 'huur' herkend".
    var reason: String
    /// Wat we voor je gekozen hebben, bijvoorbeeld "Bedrag van oktober".
    var note: String
    /// Staat de rij aan? Uitgezette rijen worden niet geïmporteerd.
    var isIncluded: Bool
    /// Alleen voor spaarpot en belegging.
    var meaning: ImportAmountMeaning
    var ticker: String?
    var units: Double?
    /// Belegging: wat er in totaal is ingelegd, als het bestand dat apart noemt (anders geldt het bedrag).
    var invested: Double?
    /// Spaarpot of belegging: wat er nu in zit, als het bestand dat naast de inleg per maand noemt (kolom Saldo of Waarde).
    /// Het telt alleen mee als het bedrag zelf "per maand" is; dan wordt het het beginsaldo.
    var balance: Double?

    init(id: UUID = UUID(), sheet: String = "", sourceRow: Int = 0, name: String, amount: Double,
         category: ImportCategory, day: Int? = nil, confidence: ImportConfidence = .hoog,
         reason: String = "", note: String = "", isIncluded: Bool = true,
         meaning: ImportAmountMeaning = .saldo, ticker: String? = nil, units: Double? = nil, invested: Double? = nil,
         balance: Double? = nil) {
        self.id = id
        self.sheet = sheet
        self.sourceRow = sourceRow
        self.name = name
        self.amount = amount
        self.category = category
        self.day = day
        self.confidence = confidence
        self.reason = reason
        self.note = note
        self.isIncluded = isIncluded
        self.meaning = meaning
        self.ticker = ticker
        self.units = units
        self.invested = invested
        self.balance = balance
    }

    /// Wordt deze rij echt geïmporteerd?
    var isActive: Bool { isIncluded && category != .overslaan }
}

/// Aantal en totaal van de aangezette rijen in één categorie.
struct ImportCategorySummary: Identifiable, Equatable {
    var category: ImportCategory
    var count: Int
    var total: Double
    var id: String { category.rawValue }
}

/// Alles wat uit een bestand is gehaald, klaar om na te kijken.
struct ImportDraft: Equatable {
    var fileName: String
    var rows: [ImportRow]
    /// Opmerkingen over het bestand als geheel ("Blad 'Lijsten' is overgeslagen").
    var warnings: [String]

    init(fileName: String = "", rows: [ImportRow] = [], warnings: [String] = []) {
        self.fileName = fileName
        self.rows = rows
        self.warnings = warnings
    }

    var isEmpty: Bool { rows.isEmpty }

    /// De rijen die echt geïmporteerd worden.
    var activeRows: [ImportRow] { rows.filter { $0.isActive } }
    var activeCount: Int { rows.filter { $0.isActive }.count }

    func rows(in category: ImportCategory) -> [ImportRow] {
        rows.filter { $0.category == category }
    }

    func count(of category: ImportCategory) -> Int {
        rows.filter { $0.isActive && $0.category == category }.count
    }

    func total(of category: ImportCategory) -> Double {
        rows.filter { $0.isActive && $0.category == category }.reduce(0.0) { $0 + $1.amount }.cents
    }

    /// Per categorie het aantal en het totaal van de aangezette rijen, in vaste volgorde.
    var summary: [ImportCategorySummary] {
        ImportCategory.selectable.map { category in
            ImportCategorySummary(category: category, count: count(of: category), total: total(of: category))
        }
    }

    // MARK: Aanpassen

    /// Zet een rij in een andere categorie. Kies je "Overslaan", dan gaat de rij uit; anders gaat hij aan.
    mutating func setCategory(_ category: ImportCategory, for id: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].category = category
        rows[i].isIncluded = category != .overslaan
        rows[i].confidence = .hoog
        rows[i].reason = category == .overslaan ? "overgeslagen door jou" : "zelf gekozen"
        if category == .belegging, rows[i].ticker == nil {
            rows[i].ticker = ImportMapper.tickerFromName(rows[i].name)
        }
    }

    mutating func setIncluded(_ included: Bool, for id: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].isIncluded = included && rows[i].category != .overslaan
    }

    mutating func setMeaning(_ meaning: ImportAmountMeaning, for id: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].meaning = meaning
    }

    /// Zet inkomstenregels voor je eigen salaris uit als je salaris al in de instellingen staat, zodat het niet dubbel
    /// meetelt. Alleen een regel die gewoon "Salaris" of "Netto loon" heet gaat uit. Staat er meer bij ("Salaris partner",
    /// "Loon bijbaan"), dan kan het ander inkomen zijn: die blijft aan, met een opmerking.
    /// Geeft het aantal uitgezette rijen terug.
    @discardableResult
    mutating func disableSalaryRows(configuredSalary: Double) -> Int {
        guard configuredSalary > 0 else { return 0 }
        let salaryWords: Set<String> = ["salaris", "loon", "nettosalaris", "nettoloon", "brutosalaris", "brutoloon",
                                        "maandsalaris", "maandloon"]
        // Woorden die een eigen salaris niet anders maken.
        let neutralWords: Set<String> = ["netto", "bruto", "maand", "maandelijks", "mnd", "per", "mijn", "eigen", "vast"]
        let hint = "Staat je eigen salaris al in de instellingen? Zet deze regel dan uit."
        var count = 0
        for i in rows.indices where rows[i].isActive && rows[i].category == .inkomen {
            let tokens = ImportText.normalize(rows[i].name).split(separator: " ").map(String.init)
            guard tokens.contains(where: { salaryWords.contains($0) }) else { continue }
            if tokens.allSatisfy({ salaryWords.contains($0) || neutralWords.contains($0) }) {
                rows[i].isIncluded = false
                rows[i].note = joinNotes(rows[i].note, "Je salaris staat al in je instellingen.")
                count += 1
            } else if !rows[i].note.contains(hint) {
                rows[i].note = joinNotes(rows[i].note, hint)
            }
        }
        return count
    }

    private func joinNotes(_ first: String, _ second: String) -> String {
        first.isEmpty ? second : first + " " + second
    }
}

// MARK: - Toepassen: uitkomst

enum ImportOutcome: String, Equatable {
    case added
    case updated
    case skippedExisting
}

struct ImportReportLine: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var category: ImportCategory
    var amount: Double
    var outcome: ImportOutcome
}

/// Wat er bij het importeren is gebeurd.
struct ImportReport: Equatable {
    var month: YearMonth
    var lines: [ImportReportLine] = []
    /// Rijen die uit stonden en dus niet zijn meegenomen.
    var notSelected = 0
    var notes: [String] = []

    func count(_ outcome: ImportOutcome, in category: ImportCategory? = nil) -> Int {
        lines.filter { $0.outcome == outcome && (category == nil || $0.category == category) }.count
    }

    var addedCount: Int { count(.added) }
    var updatedCount: Int { count(.updated) }
    var skippedCount: Int { count(.skippedExisting) }

    /// Categorieën waar iets mee gebeurd is, in vaste volgorde.
    var categories: [ImportCategory] {
        ImportCategory.selectable.filter { category in lines.contains { $0.category == category } }
    }

    /// "12 toegevoegd, 3 overgeslagen"
    var summaryText: String {
        var parts = ["\(addedCount) toegevoegd"]
        if updatedCount > 0 { parts.append("\(updatedCount) bijgewerkt") }
        parts.append("\(skippedCount) overgeslagen")
        return parts.joined(separator: ", ")
    }
}

/// Wat er gebeurt met een item dat al bestaat (zelfde naam, hoofdletterongevoelig).
enum ImportExistingPolicy {
    /// Laat het bestaande staan en meld "bestaat al".
    case skip
    /// Werk het bestaande bij met het nieuwe bedrag.
    case update
}

// MARK: - Tekst

enum ImportText {
    /// Meer dan dit aantal tekens van een cel kijken we niet naar: een naam of kopje is korter, en een enorme cel
    /// (een plaktekst, een gemanipuleerd bestand) zou anders elke rij en elke kolom opnieuw veel werk kosten.
    static let maxInspectedCharacters = 200

    /// Kleine letters, zonder accenten, leestekens als spaties, één spatie tussen woorden.
    /// Alleen de eerste `maxInspectedCharacters` tekens tellen mee.
    static func normalize(_ text: String) -> String {
        var source = String(text.prefix(maxInspectedCharacters)).lowercased()
        source = source.replacingOccurrences(of: "s&p", with: "sp")
        let folded = source.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var result = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            let isAlphaNumeric = CharacterSet.alphanumerics.contains(scalar)
            if isAlphaNumeric {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    /// Een nette weergavenaam: spaties samengevoegd, kopteken en dubbele punt weg (hoogstens 80 tekens).
    /// Alleen de eerste `maxInspectedCharacters` tekens tellen mee.
    static func cleanName(_ text: String) -> String {
        var name = String(text.prefix(maxInspectedCharacters)).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        while name.contains("  ") { name = name.replacingOccurrences(of: "  ", with: " ") }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = name.first, "-•*·>–—".contains(first) {
            name.removeFirst()
            name = name.trimmingCharacters(in: .whitespaces)
        }
        while let last = name.last, ":;,".contains(last) {
            name.removeLast()
            name = name.trimmingCharacters(in: .whitespaces)
        }
        if name.count > 80 { name = String(name.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return name
    }

    /// Is dit een totaalregel (Totaal, Subtotaal, Saldo, Overschot, ...)? Verwacht genormaliseerde tekst.
    static func isTotalName(_ normalized: String) -> Bool {
        let tokens = normalized.split(separator: " ").map(String.init)
        guard let first = tokens.first else { return false }
        let totalWords: Set<String> = ["totaal", "totalen", "subtotaal", "total", "subtotal", "som", "sum"]
        if totalWords.contains(first) { return true }
        if tokens.contains(where: { $0 == "totaal" || $0 == "subtotaal" || $0 == "totalen" }) { return true }
        let exact: Set<String> = ["saldo", "overschot", "tekort", "resultaat", "netto resultaat", "over", "restant",
                                  "te besteden", "gemiddelde", "gemiddeld", "balans", "verschil", "check", "controle",
                                  "overgehouden", "over na uitgaven", "vrij besteedbaar", "rest", "nog te verdelen",
                                  "uitkomst", "eindsaldo", "beginsaldo", "saldo eind", "per saldo"]
        return exact.contains(normalized)
    }

    /// 1...12 als de tekst een maandnaam (of afkorting) is, eventueel met een jaar erachter.
    static func monthNumber(_ normalized: String) -> Int? {
        let names: [String: Int] = [
            "jan": 1, "januari": 1, "january": 1,
            "feb": 2, "februari": 2, "february": 2,
            "mrt": 3, "maart": 3, "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "mei": 5, "may": 5,
            "jun": 6, "juni": 6, "june": 6,
            "jul": 7, "juli": 7, "july": 7,
            "aug": 8, "augustus": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "okt": 10, "oktober": 10, "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ]
        let tokens = normalized.split(separator: " ").map(String.init)
        guard !tokens.isEmpty, tokens.count <= 2 else { return nil }
        func isYear(_ token: String) -> Bool {
            (token.count == 2 || token.count == 4) && token.allSatisfy { $0.isNumber }
        }
        if let month = names[tokens[0]] {
            if tokens.count == 1 { return month }
            return isYear(tokens[1]) ? month : nil
        }
        // "2026 01" of "01 2026" (uit 2026-01 of 01-2026)
        if tokens.count == 2, tokens.allSatisfy({ $0.allSatisfy { $0.isNumber } }) {
            let a = tokens[0], b = tokens[1]
            if a.count == 4, let month = Int(b), (1...12).contains(month) { return month }
            if b.count == 4, let month = Int(a), (1...12).contains(month) { return month }
        }
        return nil
    }

    /// "15-10-2026", "15/10/26", "15.10.2026" of "2026-10-15".
    static func parseDate(_ text: String) -> SheetDate? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // "20261001" (zoals ING het schrijft)
        if trimmed.count == 8, trimmed.allSatisfy({ $0.isNumber }), let value = Int(trimmed) {
            let year = value / 10_000, month = (value / 100) % 100, day = value % 100
            guard year >= 1900, year <= 2200, (1...12).contains(month), (1...31).contains(day) else { return nil }
            return SheetDate(year: year, month: month, day: day)
        }
        let parts = trimmed.split(whereSeparator: { "-/.".contains($0) }).map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        var year: Int, month: Int, day: Int
        if parts[0].count == 4 {
            year = numbers[0]; month = numbers[1]; day = numbers[2]
        } else {
            day = numbers[0]; month = numbers[1]; year = numbers[2]
            if parts[2].count == 2 { year += 2000 }
        }
        guard (1...12).contains(month), (1...31).contains(day), year >= 1900, year <= 2200 else { return nil }
        return SheetDate(year: year, month: month, day: day)
    }

    /// De dag van de maand uit een cel: 25, "25e", "1ste", een datum.
    static func dayNumber(from cell: CellValue) -> Int? {
        switch cell {
        case .number(let value):
            guard value == value.rounded(), value >= 1, value <= 31 else { return nil }
            return Int(value)
        case .date(let date):
            return date.day
        case .text(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 24 else { return nil }
            if let date = parseDate(text) { return date.day }
            var digits = ""
            var started = false
            for ch in text {
                if ch.isNumber {
                    digits.append(ch)
                    started = true
                } else if started {
                    break
                }
            }
            guard (1...2).contains(digits.count), let day = Int(digits), (1...31).contains(day) else { return nil }
            return day
        default:
            return nil
        }
    }
}

/// Bedragen die als tekst in een cel staan: "€ 1.234,56", "1.234,56", "-45,00", "45 EUR", "(45,00)".
enum AmountText {
    /// Het getal (met teken), of nil als de tekst geen bedrag is.
    static func parse(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 40, !text.contains("%") else { return nil }

        var negative = false
        if text.hasPrefix("("), text.hasSuffix(")") {
            negative = true
            text = String(text.dropFirst().dropLast())
        }

        text = text.lowercased()
        for junk in ["euro", "eur", "€", "$", "per maand", "per mnd", "p.m.", "p/m", "/maand", "/mnd", "pm"] {
            text = text.replacingOccurrences(of: junk, with: " ")
        }
        text = text.replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
        text = String(text.unicodeScalars.filter { !$0.properties.isWhitespace })
        text = text.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")

        // "25,-", "1.050,--" en "25,=" zijn hele euro's: het streepje staat voor de nul-centen en is geen min-teken.
        for suffix in [",--", ",-", ",=", ".--", ".-"] where text.count > suffix.count && text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
            break
        }

        if text.hasPrefix("-") {
            negative = true
            text.removeFirst()
        } else if text.hasPrefix("+") {
            text.removeFirst()
        }
        if text.hasSuffix("-") {
            negative = true
            text.removeLast()
        } else if text.hasSuffix("+") {
            text.removeLast()
        }
        guard !text.isEmpty,
              text.unicodeScalars.allSatisfy({ ($0.value >= 48 && $0.value <= 57) || $0 == "." || $0 == "," }),
              text.contains(where: { $0.isNumber }) else { return nil }

        let commas = text.filter { $0 == "," }.count
        let dots = text.filter { $0 == "." }.count
        var normalized = text
        if commas > 0 && dots > 0 {
            // Het laatste teken is het decimaalteken, het andere scheidt duizendtallen.
            let lastComma = text.lastIndex(of: ",")!
            let lastDot = text.lastIndex(of: ".")!
            if lastComma > lastDot {
                normalized = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                normalized = text.replacingOccurrences(of: ",", with: "")
            }
        } else if commas == 1 {
            normalized = text.replacingOccurrences(of: ",", with: ".")
        } else if commas > 1 {
            normalized = text.replacingOccurrences(of: ",", with: "")
        } else if dots > 1 {
            normalized = text.replacingOccurrences(of: ".", with: "")
        } else if dots == 1 {
            // "1.234" is een duizendtal (Nederlands), "12.5" en "0.123" zijn decimalen.
            let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2, parts[1].count == 3, !parts[0].isEmpty, parts[0].count <= 3, parts[0] != "0" {
                normalized = parts[0] + parts[1]
            }
        }
        guard let value = Double(normalized), value.isFinite else { return nil }
        return negative ? -value : value
    }
}

// MARK: - Trefwoorden

/// Een trefwoord met de categorie waar het bij hoort.
struct ImportKeyword {
    var word: String
    var category: ImportCategory
    /// Sterke woorden geven hoge zekerheid, zwakke (korte of dubbelzinnige) gemiddelde.
    var strong: Bool
    fileprivate var bytes: [UInt8]

    init(word: String, category: ImportCategory, strong: Bool) {
        self.word = word
        self.category = category
        self.strong = strong
        self.bytes = Array(word.utf8)
    }
}

struct ImportKeywordHit: Equatable {
    var word: String
    var category: ImportCategory
    var strong: Bool
    /// Het woord wijst deze kant op, maar er is een goede reden om te twijfelen (bijvoorbeeld "Spaarrente": inkomen of spaarpot).
    var uncertain: Bool = false

    /// Hoe zeker de indeling op grond van dit woord is.
    var confidence: ImportConfidence {
        if uncertain { return .laag }
        return strong ? .hoog : .middel
    }
}

enum ImportKeywords {
    /// Alle trefwoorden, op volgorde van voorrang bij een gelijke stand.
    static let all: [ImportKeyword] = build()

    private static func build() -> [ImportKeyword] {
        var list: [ImportKeyword] = []
        func add(_ category: ImportCategory, strong: [String], weak: [String] = []) {
            for word in strong { list.append(ImportKeyword(word: ImportText.normalize(word), category: category, strong: true)) }
            for word in weak { list.append(ImportKeyword(word: ImportText.normalize(word), category: category, strong: false)) }
        }

        add(.inkomen,
            strong: ["salaris", "nettosalaris", "netto salaris", "brutosalaris", "loon", "nettoloon", "loonstrook", "toeslag",
                     "toeslagen", "zorgtoeslag", "huurtoeslag", "kindgebonden budget", "kinderbijslag", "bonus",
                     "uitkering", "uitkeringen", "aow", "wia", "wao", "ww", "bijstand", "studiefinanciering", "stufi",
                     "huurinkomsten", "huurinkomen", "huuropbrengst", "teruggave", "belastingteruggave",
                     "terugbetaling", "restitutie", "dividend", "dividenduitkering", "rente ontvangen",
                     "inkomsten", "inkomen", "ontvangen", "ontvangst", "ontvangsten", "opbrengst", "omzet", "freelance", "zzp",
                     "declaratie", "vakantiegeld", "dertiende maand", "13e maand", "eindejaarsuitkering",
                     "bijverdienste", "bijbaan", "alimentatie ontvangen", "pensioenuitkering", "pensioen uitkering",
                     "cadeau ontvangen"],
            weak: ["vergoeding", "verkoop"])

        // Een paar Engelse woorden voor bestanden uit buitenlandse programma's.
        add(.inkomen, strong: ["salary", "wage", "wages", "paycheck", "income", "refund", "dividends"])
        add(.belegging, strong: ["investment", "investments", "stock"])
        add(.vasteLasten, strong: ["rent", "mortgage", "insurance", "utilities", "electricity", "subscription", "subscriptions",
                                   "loan", "taxes", "childcare", "membership", "gym"],
            weak: ["rente", "phone", "tax"])
        add(.variabeleLasten, strong: ["groceries", "grocery", "restaurant", "dining", "clothing", "clothes", "fuel", "petrol",
                                       "gasoline", "entertainment", "shopping"],
            weak: ["food", "transport"])

        add(.spaarpot,
            strong: ["sparen", "spaarrekening", "spaarrekeningen", "spaargeld", "spaarpot", "spaarpotten", "spaardoel",
                     "spaarloon", "spaarfonds", "noodfonds", "noodpot", "buffer", "vakantiepot", "vakantiefonds",
                     "vakantiespaarpot", "reservering", "reserveringen", "reservefonds", "emergency fund", "savings",
                     "spaarplan", "potje"],
            weak: ["reserve", "reserveren"])

        add(.belegging,
            strong: ["etf", "etfs", "aandelen", "aandeel", "crypto", "cryptocurrency", "bitcoin", "btc", "ethereum", "eth",
                     "solana", "obligaties", "obligatie", "bonds", "beleggingsfonds", "indexfonds", "vwce", "iwda", "vusa",
                     "sxr8", "eunl", "swda", "vuaa", "cspx", "sp500", "sp 500", "msci", "ftse", "beleggingsrekening",
                     "beleggingen", "belegging", "beleggen", "beleggingsportefeuille", "portefeuille", "pensioen",
                     "pensioenfonds", "lijfrente", "degiro", "bux", "saxo", "flatex", "meesman", "brand new day", "binck",
                     "bolero", "coinbase", "binance", "kraken", "trading", "stocks", "shares", "gold", "vastgoed",
                     "crowdfunding", "peer to peer", "p2p", "grondstoffen", "effecten", "tracker"],
            weak: ["fonds", "index", "world", "goud", "zilver"])

        add(.vasteLasten,
            strong: ["huur", "huurwoning", "hypotheek", "hypotheekrente", "energie", "energierekening", "gasrekening",
                     "waterrekening", "stroomrekening", "elektra", "elektriciteit", "stroom", "gas water licht",
                     "internet", "glasvezel", "televisie", "verzekering", "verzekeringen", "zorgverzekering",
                     "ziektekostenverzekering", "eigen risico", "abonnement", "abonnementen", "lidmaatschap",
                     "lidmaatschappen", "contributie", "sportschool", "fitness", "telefoon", "telefoonabonnement",
                     "simkaart", "belasting", "gemeentebelasting", "waterschapsbelasting", "onroerendezaakbelasting",
                     "ozb", "rioolheffing", "afvalstoffenheffing", "wegenbelasting", "motorrijtuigenbelasting", "mrb",
                     "kinderopvang", "bso", "naschoolse opvang", "peuterspeelzaal", "lening", "leningen", "aflossing",
                     "studieschuld", "studielening", "krediet", "leasing", "lease", "servicekosten", "vve", "erfpacht",
                     "alimentatie", "netflix", "spotify", "disney", "videoland", "streaming", "icloud", "apple music",
                     "youtube premium", "amazon prime", "schoolgeld", "ouderbijdrage", "parkeervergunning",
                     "bankkosten", "rekeningkosten", "woonlasten", "wonen"],
            weak: ["gas", "water", "licht", "tv", "premie", "mobiel", "mobiele", "kabel", "gemeente", "gsm"])

        add(.variabeleLasten,
            strong: ["boodschappen", "supermarkt", "albert heijn", "jumbo", "lidl", "aldi", "uit eten", "restaurant",
                     "horeca", "koffie", "cafe", "kroeg", "afhaal", "thuisbezorgd", "lunch", "snacks", "kleding", "kleren",
                     "schoenen", "benzine", "brandstof", "diesel", "tanken", "openbaar vervoer", "ov chipkaart", "trein",
                     "taxi", "parkeren", "parkeerkosten", "cadeau", "cadeaus", "verjaardag", "verjaardagen", "kado",
                     "hobby", "kapper", "kappers", "kapsalon", "persoonlijke verzorging", "drogist", "kruidvat", "etos",
                     "vrije tijd", "uitjes", "uitje", "uitgaan", "bioscoop", "concert", "pretpark", "theater",
                     "weekendje weg", "huisdier", "dierenarts", "dierenvoer", "medicijnen", "apotheek", "tandarts",
                     "zakgeld", "onvoorzien", "kleine uitgaven", "contant", "bol com", "webshop", "speelgoed", "boeken",
                     "onderhoud", "reparatie", "garage", "apk", "wasserette", "schoonmaak", "meubels", "kinderkleding",
                     "babyspullen", "luiers"],
            weak: ["ov", "bus", "eten", "drinken", "vakantie", "diversen", "overig", "overige", "sport", "amazon", "ah",
                   "tuin", "auto"])

        // Standaardposten van de app: naam en soort komen uit Core/Expenses.swift.
        for item in StandardExpenses.all {
            for token in ImportText.normalize(item.name).split(separator: " ").map(String.init)
            where token.count >= 8 && !["persoonlijke", "gemeente"].contains(token) {
                list.append(ImportKeyword(word: token, category: item.kind == .fixed ? .vasteLasten : .variabeleLasten, strong: false))
            }
        }
        return list
    }

    /// Het beste trefwoord in een tekst. Eerst telt wat een regel *doet* (geld ontvangen, geld opzij zetten), want dat zegt
    /// meer dan waar hij over gaat ("Kinderopvangtoeslag" is inkomen, "Sparen voor vakantie" is sparen). Daarna het langste woord;
    /// bij een gelijke stand de volgorde van `all`. Volgorde van voorrang:
    /// 1. ontvangen geld (ontvangen, uitkering, teruggave, restitutie): inkomen, ook naast een spaarwoord;
    /// 2. rente op spaargeld ("Spaarrente"): inkomen, maar onzeker (het kan ook als spaarpot bedoeld zijn);
    /// 3. een sterk beleggingswoord naast een van de woorden hieronder: de bestemming wint, dus beleggen;
    /// 4. sparen en reserveren (sparen, spaar..., buffer, reservering): spaarpot;
    /// 5. de bron van geld (toeslag, salaris, loon, bonus, vergoeding): inkomen;
    /// 6. "huur" als los woord ("Huur garage"): vaste last, het woord erachter is het onderwerp;
    /// 7. het langste trefwoord.
    static func best(in text: String) -> ImportKeywordHit? {
        let normalized = ImportText.normalize(text)
        guard !normalized.isEmpty else { return nil }
        let tokens = normalized.split(separator: " ").map(String.init)
        let tokenSet = Set(tokens)
        let plain = Array(normalized.utf8)
        let padded = [UInt8(32)] + plain + [UInt8(32)]

        if let hit = intentHit(tokens: tokens, tokenSet: tokenSet, plain: plain, padded: padded) { return hit }

        var best: ImportKeyword?
        for keyword in all {
            if let current = best, keyword.word.count <= current.word.count { continue }
            if matches(keyword, plain: plain, padded: padded, tokens: tokens, tokenSet: tokenSet) { best = keyword }
        }
        guard let found = best else { return nil }
        return ImportKeywordHit(word: found.word, category: found.category, strong: found.strong)
    }

    // MARK: Bedoeling gaat voor onderwerp

    /// Hoe een bedoelingswoord in een woord van de tekst gezocht wordt.
    private enum IntentMatch {
        /// Het hele woord.
        case word
        /// Ergens in een woord ("kinderopvangtoeslag").
        case anywhere
        /// Aan het begin van een woord ("spaarbedrag"), behalve de genoemde woorden.
        case prefix(except: [String])
        /// Aan het begin of eind van een woord ("sparen", "vakantiesparen"), behalve woorden met de genoemde eindes ("besparen").
        case compound(exceptSuffix: [String])
    }

    private struct IntentRule {
        var word: String
        var match: IntentMatch
        var category: ImportCategory
        var strong: Bool

        /// Het woord uit de tekst waarin de regel past, of nil.
        func find(in tokens: [String]) -> String? {
            for token in tokens {
                switch match {
                case .word:
                    if token == word { return token }
                case .anywhere:
                    if token.contains(word) { return token }
                case .prefix(let except):
                    if token.hasPrefix(word), !except.contains(where: { token.hasPrefix($0) }) { return token }
                case .compound(let exceptSuffix):
                    if token.hasPrefix(word) || (token.hasSuffix(word) && !exceptSuffix.contains(where: { token.hasSuffix($0) })) {
                        return token
                    }
                }
            }
            return nil
        }

        func hit(for token: String) -> ImportKeywordHit {
            // Bij een begin van een woord is het gevonden woord zelf informatiever ("spaarbedrag") dan het begin ("spaar").
            if case .prefix = match { return ImportKeywordHit(word: token, category: category, strong: strong) }
            return ImportKeywordHit(word: word, category: category, strong: strong)
        }
    }

    /// Woorden die met "spaar" beginnen maar geen spaargeld zijn: hypotheek, lening, verzekering, lamp, zuinig.
    private static let notSavings = ["spaarhypotheek", "spaarlening", "spaarkrediet", "spaarverzekering", "spaarlamp", "spaarzaam"]

    /// Geld dat binnenkomt. De richting is duidelijk, ook naast een spaarwoord ("Rente spaarrekening ontvangen").
    private static let receivedRules: [IntentRule] = [
        IntentRule(word: "ontvangen", match: .anywhere, category: .inkomen, strong: true),
        IntentRule(word: "ontvangst", match: .anywhere, category: .inkomen, strong: true),
        IntentRule(word: "uitkering", match: .anywhere, category: .inkomen, strong: true),
        IntentRule(word: "teruggave", match: .anywhere, category: .inkomen, strong: true),
        IntentRule(word: "restitutie", match: .anywhere, category: .inkomen, strong: true)
    ]

    /// Geld opzij zetten.
    private static let savingRules: [IntentRule] = [
        IntentRule(word: "sparen", match: .compound(exceptSuffix: ["besparen", "versparen"]), category: .spaarpot, strong: true),
        IntentRule(word: "spaar", match: .prefix(except: notSavings + ["spaarrente"]), category: .spaarpot, strong: true),
        IntentRule(word: "buffer", match: .anywhere, category: .spaarpot, strong: true),
        IntentRule(word: "reservering", match: .anywhere, category: .spaarpot, strong: true),
        IntentRule(word: "reserveren", match: .anywhere, category: .spaarpot, strong: false)
    ]

    /// Waar het geld vandaan komt: wint van een onderwerp ("Kinderopvangtoeslag"), maar niet van een bestemming (sparen, beleggen).
    private static let sourceRules: [IntentRule] = [
        IntentRule(word: "salaris", match: .anywhere, category: .inkomen, strong: true),
        IntentRule(word: "loon", match: .word, category: .inkomen, strong: true),
        IntentRule(word: "toeslag", match: .anywhere, category: .inkomen, strong: true),
        IntentRule(word: "bonus", match: .anywhere, category: .inkomen, strong: true),
        IntentRule(word: "vergoeding", match: .anywhere, category: .inkomen, strong: false)
    ]

    /// De beste regel van een groep die in de tekst past (en het woord waarin hij past): een sterk woord gaat voor een zwak,
    /// daarna het langste woord, daarna de volgorde van de groep. Alle regels van een groep geven dezelfde categorie.
    private static func longest(of rules: [IntentRule], in tokens: [String]) -> (rule: IntentRule, token: String)? {
        var found: (rule: IntentRule, token: String)?
        for rule in rules {
            guard let token = rule.find(in: tokens) else { continue }
            if let current = found {
                if current.rule.strong != rule.strong {
                    if current.rule.strong { continue }
                } else if current.rule.word.count >= rule.word.count {
                    continue
                }
            }
            found = (rule, token)
        }
        return found
    }

    private static func intentHit(tokens: [String], tokenSet: Set<String>, plain: [UInt8], padded: [UInt8]) -> ImportKeywordHit? {
        // 1. Ontvangen geld.
        if let found = longest(of: receivedRules, in: tokens) { return found.rule.hit(for: found.token) }

        // 2. Rente op spaargeld: "Spaarrente", "Rente spaarrekening". Het is meestal een bijschrijving, maar zeker is het niet.
        let isSavingsWord = { (token: String) in token.hasPrefix("spaar") && !notSavings.contains(where: { token.hasPrefix($0) }) }
        if tokens.contains(where: { $0.hasPrefix("spaarrente") })
            || (tokenSet.contains("rente") && tokens.contains(where: isSavingsWord)) {
            return ImportKeywordHit(word: "spaarrente", category: .inkomen, strong: false, uncertain: true)
        }

        let saving = longest(of: savingRules, in: tokens)
        let source = longest(of: sourceRules, in: tokens)
        let huur = tokenSet.contains("huur") && tokens.count > 1
        guard saving != nil || source != nil || huur else { return nil }

        // Een sterk beleggingswoord wijst de bestemming aan ("ETF sparen", "Sparen voor pensioen", "Bonus beleggen"):
        // dan is het beleggen. Bij alleen een zwak beleggingswoord ("fonds", "world") beslist het langste woord, zoals altijd.
        var investing: ImportKeyword?
        var weakInvesting = false
        for keyword in all where keyword.category == .belegging {
            guard matches(keyword, plain: plain, padded: padded, tokens: tokens, tokenSet: tokenSet) else { continue }
            if keyword.strong {
                if investing == nil || keyword.word.count > investing!.word.count { investing = keyword }
            } else {
                weakInvesting = true
            }
        }
        if let investing { return ImportKeywordHit(word: investing.word, category: investing.category, strong: true) }
        if weakInvesting { return nil }

        // 3. Sparen of reserveren.
        if let found = saving { return found.rule.hit(for: found.token) }
        // 4. De bron van het geld.
        if let found = source { return found.rule.hit(for: found.token) }

        // 5. "Huur garage", "Huur parkeerplaats": het woord erachter zegt waarvoor je huurt, het blijft een vaste last.
        // Staat er een inkomstenwoord bij ("Huur inkomsten"), dan beslist het langste woord.
        let income = all.contains { $0.category == .inkomen && matches($0, plain: plain, padded: padded, tokens: tokens, tokenSet: tokenSet) }
        if !income { return ImportKeywordHit(word: "huur", category: .vasteLasten, strong: true) }
        return nil
    }

    private static func matches(_ keyword: ImportKeyword, plain: [UInt8], padded: [UInt8], tokens: [String], tokenSet: Set<String>) -> Bool {
        let word = keyword.word
        if word.contains(" ") { return contains(padded, [UInt8(32)] + keyword.bytes + [UInt8(32)]) }
        switch word.count {
        case 0: return false
        case 1...3: return tokenSet.contains(word)
        case 4: return tokens.contains { $0.hasPrefix(word) }
        default: return contains(plain, keyword.bytes)
        }
    }

    /// Zoekt een reeks bytes in een andere (korte teksten, dus een eenvoudige lus volstaat).
    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        let first = needle[0]
        let last = haystack.count - needle.count
        var i = 0
        while i <= last {
            if haystack[i] == first {
                var j = 1
                while j < needle.count && haystack[i + j] == needle[j] { j += 1 }
                if j == needle.count { return true }
            }
            i += 1
        }
        return false
    }

    /// De standaardpost waar de naam precies mee overeenkomt ("Boodschappen", "Zorgverzekering").
    static func standardExpense(named name: String) -> StandardExpense? {
        let normalized = ImportText.normalize(name)
        guard !normalized.isEmpty else { return nil }
        return StandardExpenses.all.first { ImportText.normalize($0.name) == normalized }
    }
}

/// Kopjes en categoriewaarden: "Vaste lasten", "Inkomsten", "Sparen", ...
enum ImportLabels {
    private static let phrases: [(category: ImportCategory, words: [String])] = [
        (.inkomen, ["inkomsten", "inkomen", "inkomend", "ontvangsten", "income", "baten"]),
        (.vasteLasten, ["vaste lasten", "vaste kosten", "vaste uitgaven", "vaste maandlasten", "maandlasten", "vast",
                        "vaste posten", "verplichte uitgaven", "verplichte lasten", "fixed", "woonlasten"]),
        (.variabeleLasten, ["variabele lasten", "variabele kosten", "variabele uitgaven", "variabel", "variabele posten",
                            "flexibele uitgaven", "flexibele kosten", "variable"]),
        (.spaarpot, ["sparen", "spaarpotten", "spaarpot", "spaargeld", "spaardoelen", "spaardoel", "spaarrekeningen",
                     "spaarrekening", "reserveringen", "reservering", "savings", "buffers", "spaarpotjes"]),
        (.belegging, ["beleggen", "beleggingen", "belegging", "portefeuille", "investeringen", "investeren", "effecten",
                      "investments", "investment", "beleggingsportefeuille", "beleggingsrekening"])
    ]

    /// Algemene kopjes zonder eigen categorie: de trefwoorden beslissen dan per regel.
    private static let generic: Set<String> = ["uitgaven", "kosten", "lasten", "uitgave", "uitgaven per maand",
                                               "maandelijkse uitgaven", "maandelijkse kosten", "overige uitgaven",
                                               "overige kosten", "overig", "diversen", "expenses"]

    /// Kopjes die alleen een categorie aanduiden en nooit een regel zijn, ook niet met een bedrag erbij.
    private static let strongHeadings: Set<String> = [
        "vaste lasten", "vaste kosten", "vaste uitgaven", "variabele lasten", "variabele kosten", "variabele uitgaven",
        "inkomsten", "ontvangsten", "uitgaven", "beleggingen", "spaarpotten", "investeringen"
    ]

    /// De categorie die een kopje of categoriewaarde aanduidt, of nil. Bij twee even sterke kandidaten
    /// ("Sparen en beleggen") geven we niets terug.
    static func category(of text: String) -> (category: ImportCategory, phrase: String)? {
        let normalized = ImportText.normalize(text)
        guard !normalized.isEmpty, normalized.count <= 60 else { return nil }
        var found: [(category: ImportCategory, phrase: String)] = []
        for entry in phrases {
            var bestPhrase: String?
            for word in entry.words where contains(normalized, phrase: word) {
                if bestPhrase == nil || word.count > bestPhrase!.count { bestPhrase = word }
            }
            if let bestPhrase { found.append((entry.category, bestPhrase)) }
        }
        guard !found.isEmpty else { return nil }
        found.sort { $0.phrase.count > $1.phrase.count }
        if found.count > 1, found[0].phrase.count - found[1].phrase.count < 3 { return nil }
        return found[0]
    }

    /// Zoals `category(of:)`, maar alleen als de hele tekst precies een kopje is ("Sparen", "Vaste lasten").
    static func exactCategory(of text: String) -> ImportCategory? {
        let normalized = ImportText.normalize(text)
        for entry in phrases where entry.words.contains(normalized) { return entry.category }
        return nil
    }

    static func isGeneric(_ text: String) -> Bool {
        generic.contains(ImportText.normalize(text))
    }

    static func isStrongHeading(_ text: String) -> Bool {
        strongHeadings.contains(ImportText.normalize(text))
    }

    private static func contains(_ normalized: String, phrase: String) -> Bool {
        normalized == phrase || normalized.hasPrefix(phrase + " ") || normalized.hasSuffix(" " + phrase)
            || normalized.contains(" " + phrase + " ")
    }
}

// MARK: - Kolommen

private enum HeaderKind: Equatable {
    case name, category, amount, income, expense, day, date, ticker, units, price, value, invested, balance
    case direction, note, total
    case month(Int)
}

private struct HeaderInfo {
    var kind: HeaderKind
    var meaning: ImportAmountMeaning? = nil
    /// Hoeveel van het bedrag in de kolom per maand telt (jaarbedrag: 1/12).
    var factor: Double = 1
    var factorNote: String? = nil
}

private enum ForcedKind { case unforced, income, expense }

/// Welke kolom wat bevat.
private struct ColumnLayout {
    var name: Int?
    var category: Int?
    var amount: Int?
    var amountMeaning: ImportAmountMeaning?
    var amountFactor: Double = 1
    var factorNote: String?
    var amountHeader = ""
    var income: Int?
    var expense: Int?
    var forced: ForcedKind = .unforced
    var months: [Int: Int] = [:]
    var day: Int?
    var date: Int?
    var ticker: Int?
    var units: Int?
    var price: Int?
    var value: Int?
    var invested: Int?
    var balance: Int?
    var direction: Int?
    var headerRow = -1
    /// Het deel van het blad waar deze tabel staat (bij twee tabellen naast elkaar); standaard het hele blad.
    var firstColumn = 0
    var endColumn = Int.max
    /// Stond de kolom van de namen onder de kop "Inkomsten" (of "Uitgaven"), dan is dat het kopje voor de rijen eronder.
    var headingTitle: String?
    var headingCategory: ImportCategory?

    /// Heeft kolommen die bij beleggingen horen?
    var hasInvestmentColumns: Bool { ticker != nil || units != nil || price != nil }
}

/// Een kopje waaronder de volgende rijen vallen.
private struct HeadingSection {
    var category: ImportCategory?
    var title: String
}

// MARK: - Herkenning

enum ImportMapper {
    /// De reden bij een regel waar we niets van herkennen en dus raden.
    static let guessReason = "geen herkenbaar woord: gok"

    /// Grootste bedrag per regel dat we serieus nemen (100 miljoen euro); daarboven is het een fout in het bestand.
    static let maxAmount = 100_000_000.0

    /// Maakt van een ingelezen bestand een lijst ingedeelde rijen. `month` is de maand waarvan we bij een
    /// indeling per maand het bedrag nemen (de huidige maand).
    static func draft(from workbook: SpreadsheetWorkbook, preferredMonth month: YearMonth = YearMonth.current()) -> ImportDraft {
        var warnings: [String] = []
        var visible = workbook.tables.filter { !$0.isHidden && $0.hasContent }
        let hiddenCount = workbook.tables.filter { $0.isHidden && $0.hasContent }.count
        if visible.isEmpty {
            // Alleen verborgen bladen met gegevens: dan gebruiken we die toch.
            visible = workbook.tables.filter { $0.hasContent }
        } else if hiddenCount > 0 {
            warnings.append(hiddenCount == 1 ? "Eén verborgen blad is overgeslagen." : "\(hiddenCount) verborgen bladen zijn overgeslagen.")
        }
        if workbook.skippedSheets > 0 {
            warnings.append("Het bestand heeft meer dan \(XLSXReader.maxSheets) bladen. Alleen de eerste \(XLSXReader.maxSheets) zijn gelezen; \(workbook.skippedSheets) bladen zijn overgeslagen.")
        }

        // Een blad per maand (Januari, Februari, ...): neem alleen het blad van de gekozen maand.
        let monthSheets = visible.filter { ImportText.monthNumber(ImportText.normalize($0.name)) != nil }
        if monthSheets.count >= 3 {
            let wanted = monthSheets.first { ImportText.monthNumber(ImportText.normalize($0.name)) == month.month } ?? monthSheets[0]
            let others = monthSheets.filter { $0.name != wanted.name }.map { "'\($0.name)'" }
            visible = visible.filter { table in table.name == wanted.name || !monthSheets.contains(where: { $0.name == table.name }) }
            warnings.append("Het bestand heeft een blad per maand. Alleen blad '\(wanted.name)' is gebruikt; overgeslagen: \(others.joined(separator: ", ")).")
        }

        var rows: [ImportRow] = []
        for table in visible {
            let mapper = TableMapper(table: table, month: month)
            let result = mapper.run()
            rows += result.rows
            warnings += result.warnings
            let hasNumbers = table.rows.contains { row in row.contains { $0.numberValue != nil } }
            if result.rows.isEmpty && hasNumbers {
                warnings.append("In blad '\(table.name)' is geen herkenbare tabel met bedragen gevonden.")
            }
        }

        rows = removeDuplicates(rows)
        return ImportDraft(fileName: workbook.fileName, rows: rows, warnings: warnings)
    }

    // MARK: Dubbelingen

    /// Dezelfde naam in dezelfde categorie: gelijke regels worden uitgezet, verschillende bedragen in hetzelfde blad
    /// opgeteld (boekingen), een regel in een ander blad wordt uitgezet.
    static func removeDuplicates(_ input: [ImportRow]) -> [ImportRow] {
        var rows = input
        var keep: [String: Int] = [:]
        var merged: [Int: Int] = [:]
        var remove: Set<Int> = []

        for i in rows.indices where rows[i].category != .overslaan {
            let key = rows[i].category.rawValue + "|" + ImportText.normalize(rows[i].name)
            guard let first = keep[key] else {
                keep[key] = i
                continue
            }
            if rows[first].sheet != rows[i].sheet {
                rows[i].isIncluded = false
                rows[i].note = join(rows[i].note, "Staat ook in blad '\(rows[first].sheet)'; deze is uitgezet.")
            } else if CentsMath.int(rows[first].amount) == CentsMath.int(rows[i].amount) && rows[first].day == rows[i].day {
                rows[i].isIncluded = false
                rows[i].note = join(rows[i].note, "Staat er twee keer in; de tweede is uitgezet.")
            } else {
                rows[first].amount = (rows[first].amount + rows[i].amount).cents
                merged[first, default: 1] += 1
                remove.insert(i)
            }
        }
        for (index, count) in merged {
            let text = "\(count) regels met dezelfde naam samengevoegd."
            rows[index].note = join(rows[index].note, text)
        }
        return rows.enumerated().filter { !remove.contains($0.offset) }.map { $0.element }
    }

    private static func join(_ first: String, _ second: String) -> String {
        first.isEmpty ? second : first + " " + second
    }

    // MARK: Beleggingsgegevens uit namen

    /// Bekende tickers die we aan een naam herkennen. De achtervoegsels zijn die van Yahoo Finance.
    private static let knownTickers: [String: String] = [
        "vwce": "VWCE.DE", "iwda": "IWDA.AS", "vusa": "VUSA.AS", "sxr8": "SXR8.DE", "eunl": "EUNL.DE",
        "btc": "BTC-EUR", "bitcoin": "BTC-EUR", "eth": "ETH-EUR", "ethereum": "ETH-EUR"
    ]

    /// Een ticker uit een naam als "VWCE (wereld-ETF)", "IWDA.AS" of "Bitcoin".
    static func tickerFromName(_ name: String) -> String? {
        for piece in name.split(whereSeparator: { " ,;()[]/".contains($0) }).map(String.init) {
            if let explicit = explicitTicker(piece) { return explicit }
        }
        for token in ImportText.normalize(name).split(separator: " ").map(String.init) {
            if let known = knownTickers[token] { return known }
        }
        return nil
    }

    /// Een ticker met beurs ("VWCE.DE") of een cryptopaar ("BTC-EUR").
    static func explicitTicker(_ text: String) -> String? {
        let candidate = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard candidate.count >= 4, candidate.count <= 14 else { return nil }
        let scalars = Array(candidate.unicodeScalars)
        func isAlnum(_ s: Unicode.Scalar) -> Bool { (s.value >= 48 && s.value <= 57) || (s.value >= 65 && s.value <= 90) }
        // Een beursachtervoegsel (VWCE.DE) of een valuta bij een cryptomunt (BTC-EUR); "Wereld-ETF" is dus geen ticker.
        let exchanges: Set<String> = ["DE", "AS", "L", "PA", "MI", "SW", "F", "MC", "BR", "LS", "HE", "ST", "CO", "OL", "VI", "TO", "US", "AX", "HK", "MU", "SG"]
        let currencies: Set<String> = ["EUR", "USD", "USDT", "GBP", "BTC", "ETH"]
        let options: [(separator: Unicode.Scalar, allowed: Set<String>)] = [(".", exchanges), ("-", currencies)]
        for option in options {
            let parts = candidate.split(separator: Character(option.separator), omittingEmptySubsequences: false)
            guard parts.count == 2, (1...6).contains(parts[0].count), option.allowed.contains(String(parts[1])) else { continue }
            if scalars.allSatisfy({ isAlnum($0) || $0 == option.separator }),
               parts[0].unicodeScalars.contains(where: { $0.value >= 65 && $0.value <= 90 }) {
                return candidate
            }
        }
        return nil
    }

    /// Een ticker uit een tickerkolom: letters, cijfers, punt, streep en ^ of =.
    static func sanitizedTicker(_ text: String) -> String? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (1...14).contains(candidate.count) else { return nil }
        let allowed = candidate.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90) || $0 == "." || $0 == "-" || $0 == "^" || $0 == "="
        }
        guard allowed, candidate.unicodeScalars.contains(where: { $0.value >= 65 && $0.value <= 90 }) else { return nil }
        // "n.v.t." en dergelijke zijn geen ticker.
        let notATicker: Set<String> = ["N.V.T.", "NVT", "GEEN", "N/A", "NA", "ONBEKEND", "NVT."]
        guard !notATicker.contains(candidate) else { return nil }
        return candidate
    }

    /// Het soort belegging uit trefwoorden in naam en ticker.
    static func holdingKind(for name: String, ticker: String? = nil) -> HoldingKind {
        let text = ImportText.normalize(name + " " + (ticker ?? ""))
        let tokens = Set(text.split(separator: " ").map(String.init))
        func has(_ words: [String]) -> Bool {
            words.contains { word in word.count <= 3 ? tokens.contains(word) : text.contains(word) }
        }
        if has(["crypto", "bitcoin", "btc", "ethereum", "eth", "solana", "coin"]) || (ticker ?? "").uppercased().hasSuffix("-EUR") { return .crypto }
        if has(["obligaties", "obligatie", "bonds", "bond"]) { return .bonds }
        if has(["goud", "zilver", "grondstoffen", "grondstof", "gold"]) { return .commodities }
        if has(["vastgoed", "woning", "crowdfunding"]) { return .realEstate }
        if has(["spaarrekening", "deposito"]) { return .savings }
        if has(["etf", "etfs", "indexfonds", "index", "tracker", "fonds", "vwce", "iwda", "vusa", "sxr8", "eunl", "msci", "ftse", "sp500", "world", "wereld"]) { return .etf }
        if has(["aandelen", "aandeel", "stocks", "shares"]) { return .stocks }
        return .other
    }

    /// Een passend symbool voor een nieuwe spaarpot (uit de symbolen die de app kent).
    static func potSymbol(for name: String) -> String {
        let text = ImportText.normalize(name)
        let table: [(words: [String], symbol: String)] = [
            (["nood", "buffer", "reserve", "reservering"], "shield.lefthalf.filled"),
            (["vakantie", "reis", "trip"], "airplane"),
            (["laptop", "computer", "telefoon", "tech"], "laptopcomputer"),
            (["huis", "woning", "verbouwing", "tuin"], "house.fill"),
            (["auto", "scooter"], "car.fill"),
            (["cadeau", "kerst", "sinterklaas", "verjaardag"], "gift.fill"),
            (["studie", "school", "opleiding"], "graduationcap.fill"),
            (["fiets"], "bicycle"),
            (["camera"], "camera.fill")
        ]
        for entry in table where entry.words.contains(where: { text.contains($0) }) { return entry.symbol }
        return "banknote"
    }

    // MARK: Hulpjes voor het tafelwerk

    fileprivate static func headerInfo(for cell: CellValue) -> HeaderInfo? {
        if case .date(let date) = cell { return HeaderInfo(kind: .month(date.month)) }
        guard let raw = cell.trimmedText else { return nil }
        let h = ImportText.normalize(raw)
        guard !h.isEmpty else { return nil }
        if let month = ImportText.monthNumber(h) { return HeaderInfo(kind: .month(month)) }

        let words = Set(h.split(separator: " ").map(String.init))
        func exact(_ list: [String]) -> Bool { list.contains(h) }

        if exact(["af bij", "afbij", "af of bij", "debet credit", "credit debet", "d c"]) { return HeaderInfo(kind: .direction) }
        if h.contains("datum") || h == "date" { return HeaderInfo(kind: .date) }
        if exact(["dag", "betaaldag", "vervaldag", "incassodag", "dag van de maand", "dag v d maand", "dag vd maand", "dagnummer", "betaal dag"])
            || h.hasPrefix("dag ") { return HeaderInfo(kind: .day) }
        if !words.isDisjoint(with: ["ticker", "tickersymbool", "symbool", "symbol"]) { return HeaderInfo(kind: .ticker) }
        if h == "aantal" || h.hasPrefix("aantal ") || !words.isDisjoint(with: ["stuks", "units", "hoeveelheid"]) { return HeaderInfo(kind: .units) }
        if h.contains("ingelegd") || h.contains("geinvesteerd") || h.contains("aankoop") || h.contains("kostprijs")
            || exact(["inleg totaal", "totaal inleg", "totale inleg", "inleg tot nu"]) { return HeaderInfo(kind: .invested) }
        if h == "koers" || h.hasPrefix("koers ") || h.contains("slotkoers") || exact(["prijs per stuk", "prijs"]) { return HeaderInfo(kind: .price) }
        if h.contains("waarde") || h == "stand" || h.hasPrefix("stand ") || !words.isDisjoint(with: ["value", "balance"]) { return HeaderInfo(kind: .value) }
        if h.contains("saldo") { return HeaderInfo(kind: .balance) }
        // "Gespaard", "Tegoed" en "Huidig bedrag" zijn wat er nu in zit, geen inleg per maand ("Gespaard per maand" wel).
        if !h.contains("maand") && !h.contains("mnd")
            && (!words.isDisjoint(with: ["gespaard", "tegoed", "opgebouwd"])
                || exact(["huidig", "huidige", "huidig bedrag", "huidige bedrag", "huidige stand"])) {
            return HeaderInfo(kind: .balance)
        }
        if exact(["inleg", "maandinleg", "inleg per maand", "maandelijkse inleg", "storting", "maandelijkse storting", "stortingen"])
            || h.contains("maandinleg") { return HeaderInfo(kind: .amount, meaning: .perMaand) }

        // Bedragen per andere periode dan een maand.
        if h.contains("per jaar") || h.contains("jaarbedrag") || h.contains("jaarlijks") && h.contains("bedrag") {
            return HeaderInfo(kind: .amount, meaning: .perMaand, factor: 1.0 / 12.0, factorNote: "Jaarbedrag gedeeld door 12.")
        }
        if h.contains("per halfjaar") || h.contains("per half jaar") {
            return HeaderInfo(kind: .amount, meaning: .perMaand, factor: 1.0 / 6.0, factorNote: "Bedrag per halfjaar gedeeld door 6.")
        }
        if h.contains("per kwartaal") || h.contains("kwartaalbedrag") {
            return HeaderInfo(kind: .amount, meaning: .perMaand, factor: 1.0 / 3.0, factorNote: "Bedrag per kwartaal gedeeld door 3.")
        }
        if h.contains("per 4 weken") || h.contains("per vier weken") {
            return HeaderInfo(kind: .amount, meaning: .perMaand, factor: 13.0 / 12.0, factorNote: "Bedrag per 4 weken omgerekend naar een maand.")
        }
        if h.contains("per week") || h.contains("weekbedrag") {
            return HeaderInfo(kind: .amount, meaning: .perMaand, factor: 52.0 / 12.0, factorNote: "Bedrag per week omgerekend naar een maand.")
        }

        if h.contains("bedrag") || exact(["amount", "per maand", "maandbedrag", "maandelijks", "maandelijks bedrag", "mnd bedrag",
                                           "p m", "pm", "budget", "begroot", "begroting", "gepland", "norm", "kosten", "kosten per maand",
                                           "euro", "eur", "prijs per maand", "transactiebedrag", "mutatie", "bedrag eur"]) {
            let monthly = h.contains("maand") || h == "p m" || h == "pm" || h.contains("mnd")
            return HeaderInfo(kind: .amount, meaning: monthly ? .perMaand : nil)
        }
        if exact(["inkomsten", "inkomen", "bij", "credit", "ontvangen", "ontvangsten", "opbrengsten", "inkomsten per maand"]) {
            return HeaderInfo(kind: .income)
        }
        if exact(["uitgaven", "uitgave", "af", "debet", "betaald", "lasten", "uitgaven per maand"]) {
            return HeaderInfo(kind: .expense)
        }
        if exact(["categorie", "categorieen", "soort", "type", "groep", "rubriek", "hoofdgroep", "hoofdcategorie", "category",
                  "soort uitgave", "type uitgave", "kostensoort", "kostencategorie", "budgetgroep", "categorie uitgave"]) {
            return HeaderInfo(kind: .category)
        }
        if exact(["opmerking", "opmerkingen", "notitie", "notities", "toelichting", "mededelingen", "memo", "note", "notes", "commentaar", "extra"]) {
            return HeaderInfo(kind: .note)
        }
        if exact(["totaal", "som", "jaar", "jaartotaal", "totaal jaar", "gemiddeld", "gemiddelde", "gem", "gem per maand", "jaarlijks",
                  "totaal per jaar", "sum", "total", "gemiddelde per maand", "totalen"]) {
            return HeaderInfo(kind: .total)
        }
        if exact(["omschrijving", "naam", "post", "posten", "item", "onderdeel", "beschrijving", "description", "name", "tegenpartij",
                  "begunstigde", "naam omschrijving", "naam of omschrijving", "uitgavepost", "kostenpost", "budgetpost", "product",
                  "fonds", "fondsnaam", "belegging", "beleggingen", "instrument", "spaarpot", "pot", "onderwerp", "titel", "artikel", "wat",
                  "rekening", "rekeningnaam"])
            || h.contains("omschrijving") || h.hasPrefix("naam") { return HeaderInfo(kind: .name) }
        // "Vaste lasten" of "Sparen" boven een kolom met namen.
        if ImportLabels.exactCategory(of: raw) != nil || ImportLabels.isStrongHeading(raw) { return HeaderInfo(kind: .name) }
        return nil
    }
}

// MARK: - Eén werkblad

private struct TableMapper {
    let table: SpreadsheetTable
    let month: YearMonth

    private var grid: [[CellValue]] { table.rows }

    init(table: SpreadsheetTable, month: YearMonth) {
        self.table = table
        self.month = month
    }

    private func cell(_ row: Int, _ column: Int?) -> CellValue {
        guard let column else { return .empty }
        return table.cell(row, column)
    }

    private func text(_ row: Int, _ column: Int?) -> String? {
        let value = cell(row, column)
        switch value {
        case .text: return value.trimmedText
        case .number, .percent, .bool, .date:
            return value.displayText.isEmpty ? nil : value.displayText
        case .empty: return nil
        }
    }

    // MARK: Kopregels

    private typealias HeaderCell = (column: Int, value: CellValue, info: HeaderInfo)

    /// De tabellen die een kopregel aankondigt: meestal één, bij twee tabellen naast elkaar (Inkomsten links, Uitgaven
    /// rechts) twee. Leeg als de rij geen kopregel is.
    private func evaluateHeader(row: Int) -> [ColumnLayout] {
        let cells = grid[row]
        let nonBlank = cells.filter { !$0.isBlank }
        guard nonBlank.count >= 2 else { return [] }
        let textual = nonBlank.filter { value in
            switch value {
            case .text, .date: return true
            default: return false
            }
        }
        guard Double(textual.count) >= 0.7 * Double(nonBlank.count) else { return [] }
        // Gegevensregels hebben getallen; een kopregel (bijna) niet. Dit scheelt veel werk bij lange lijsten.
        let numericLooking = nonBlank.filter { looksNumeric($0) }.count
        guard Double(numericLooking) <= 0.3 * Double(nonBlank.count) else { return [] }

        var infos: [HeaderCell] = []
        for (column, value) in cells.enumerated() {
            if let info = ImportMapper.headerInfo(for: value) { infos.append((column, value, info)) }
        }
        guard !infos.isEmpty else { return [] }

        // Twee tabellen naast elkaar: na een bedragkolom begint er weer een naam- of categoriekolom.
        var segments: [[HeaderCell]] = [[]]
        var seenAmount = false
        for item in infos {
            var startsGroup = false
            switch item.info.kind {
            case .name, .category, .income, .expense: startsGroup = true
            default: break
            }
            if startsGroup && seenAmount && !segments[segments.count - 1].isEmpty {
                segments.append([])
                seenAmount = false
            }
            segments[segments.count - 1].append(item)
            switch item.info.kind {
            case .amount, .value, .invested, .balance, .price, .units, .month: seenAmount = true
            default: break
            }
        }
        if segments.count >= 2 {
            var built: [ColumnLayout] = []
            for (index, segment) in segments.enumerated() {
                var layout = buildLayout(segment, row: row)
                layout.firstColumn = index == 0 ? 0 : segment[0].column
                layout.endColumn = index + 1 < segments.count ? segments[index + 1][0].column : Int.max
                if qualifies(layout) { built.append(layout) }
            }
            // Alleen als elk deel een eigen kop is (naam en bedrag); anders is het gewoon één brede tabel.
            if built.count >= 2 { return built }
        }
        let single = buildLayout(infos, row: row)
        return qualifies(single) ? [single] : []
    }

    /// Is dit een bruikbare kop? Bedragen komen uit een bedrag-, maand- of waardekolom, of uit aparte kolommen voor
    /// inkomsten en uitgaven; daarnaast is er een kolom met namen (ook "Inkomsten" of "Vaste lasten" boven de namen telt).
    private func qualifies(_ layout: ColumnLayout) -> Bool {
        if layout.income != nil && layout.expense != nil { return true }
        let explicitAmount = layout.amount != nil || layout.months.count >= 2 || layout.value != nil
            || layout.invested != nil || layout.balance != nil || (layout.units != nil && layout.price != nil)
        let hasSide = layout.income != nil || layout.expense != nil
        let hasLeader = layout.name != nil || layout.category != nil || layout.months.count >= 2 || (explicitAmount && hasSide)
        return (explicitAmount || hasSide) && hasLeader
    }

    private func buildLayout(_ infos: [HeaderCell], row: Int) -> ColumnLayout {
        var layout = ColumnLayout()
        layout.headerRow = row
        for item in infos {
            let column = item.column
            let info = item.info
            switch info.kind {
            case .name:
                if layout.name == nil {
                    layout.name = column
                    // Staat er "Vaste lasten" boven de namen, dan zijn dat de vaste lasten.
                    if let label = ImportLabels.category(of: item.value.displayText) {
                        layout.headingCategory = label.category
                        layout.headingTitle = ImportText.cleanName(item.value.displayText)
                    }
                }
            case .category: if layout.category == nil { layout.category = column }
            case .amount:
                // Een kolom die als maandbedrag is gemerkt gaat voor.
                if layout.amount == nil || (layout.amountMeaning == nil && info.meaning == .perMaand && info.factor == 1) {
                    layout.amount = column
                    layout.amountMeaning = info.meaning
                    layout.amountFactor = info.factor
                    layout.factorNote = info.factorNote
                    layout.amountHeader = item.value.displayText
                }
            case .income: if layout.income == nil { layout.income = column }
            case .expense: if layout.expense == nil { layout.expense = column }
            case .day: if layout.day == nil { layout.day = column }
            case .date: if layout.date == nil { layout.date = column }
            case .ticker: if layout.ticker == nil { layout.ticker = column }
            case .units: if layout.units == nil { layout.units = column }
            case .price: if layout.price == nil { layout.price = column }
            case .value: if layout.value == nil { layout.value = column }
            case .invested: if layout.invested == nil { layout.invested = column }
            case .balance: if layout.balance == nil { layout.balance = column }
            case .direction: if layout.direction == nil { layout.direction = column }
            case .month(let number): if layout.months[number] == nil { layout.months[number] = column }
            case .note, .total: break
            }
        }
        return layout
    }

    /// De cellen van een rij die bij deze tabel horen (bij twee tabellen naast elkaar maar één kant).
    private func slice(_ row: Int, _ layout: ColumnLayout) -> [CellValue] {
        let cells = grid[row]
        guard layout.firstColumn < cells.count else { return [] }
        return Array(cells[layout.firstColumn..<min(cells.count, layout.endColumn)])
    }

    /// Lijkt de cel op een getal of bedrag? (Snelle controle op het eerste teken.)
    private func looksNumeric(_ value: CellValue) -> Bool {
        switch value {
        case .number, .percent: return true
        case .text(let raw):
            guard let first = raw.trimmingCharacters(in: .whitespaces).first else { return false }
            if first.isNumber || first == "€" { return true }
            if "-+(".contains(first) {
                let rest = raw.trimmingCharacters(in: .whitespaces).dropFirst().first
                return rest.map { $0.isNumber || $0 == "€" || $0 == " " } ?? false
            }
            return false
        default: return false
        }
    }

    /// Past een kopregel aan met wat de rijen eronder laten zien: welke kolommen zijn echt getallen, en waar staat de naam.
    private func resolve(_ input: ColumnLayout, rowsFrom start: Int, to end: Int) -> ColumnLayout {
        var layout = input
        let dataRows = (start..<end).filter { row in slice(row, input).contains { !$0.isBlank } }.prefix(40)

        func numericShare(_ column: Int) -> Double {
            var numeric = 0
            var filled = 0
            for row in dataRows {
                let value = cell(row, column)
                if value.isBlank { continue }
                filled += 1
                if amountValue(value) != nil { numeric += 1 }
            }
            return filled == 0 ? 0 : Double(numeric) / Double(filled)
        }

        // Kolommen "Inkomsten" en "Uitgaven" zijn bedragen als er getallen in staan; anders zijn het lijsten met namen.
        if let income = layout.income, numericShare(income) < 0.5 {
            if layout.name == nil {
                layout.name = income
                layout.headingTitle = cell(layout.headerRow, income).displayText
                layout.headingCategory = .inkomen
            }
            layout.income = nil
        }
        if let expense = layout.expense, numericShare(expense) < 0.5 {
            if layout.name == nil {
                layout.name = expense
                layout.headingTitle = cell(layout.headerRow, expense).displayText
            }
            layout.expense = nil
        }
        if layout.amount == nil && !(layout.income != nil && layout.expense != nil) && layout.months.count < 2 {
            if let income = layout.income {
                layout.amount = income
                layout.amountHeader = cell(layout.headerRow, income).displayText
                layout.forced = .income
                layout.income = nil
            } else if let expense = layout.expense {
                layout.amount = expense
                layout.amountHeader = cell(layout.headerRow, expense).displayText
                layout.forced = .expense
                layout.expense = nil
            }
        } else if layout.amount != nil {
            layout.income = nil
            layout.expense = nil
        }
        // Prijs zonder aantal of bedrag is het bedrag zelf.
        if layout.amount == nil && layout.value == nil && layout.invested == nil && layout.balance == nil
            && layout.income == nil && layout.months.count < 2, let price = layout.price, layout.units == nil {
            layout.amount = price
            layout.amountHeader = cell(layout.headerRow, price).displayText
            layout.price = nil
        }

        // Geen naamkolom in de kop: de meest tekstrijke kolom die niets anders is.
        if layout.name == nil {
            let used: Set<Int> = Set([layout.category, layout.amount, layout.income, layout.expense, layout.day, layout.date,
                                      layout.ticker, layout.units, layout.price, layout.value, layout.invested, layout.balance,
                                      layout.direction].compactMap { $0 }).union(layout.months.values)
            var bestColumn: Int?
            var bestCount = 0
            let upper = min(layout.endColumn, max(table.columnCount, layout.firstColumn + 1))
            for column in layout.firstColumn..<upper where !used.contains(column) {
                var count = 0
                for row in dataRows {
                    let value = cell(row, column)
                    if case .text = value, !value.isBlank, amountValue(value) == nil { count += 1 }
                }
                if count > bestCount {
                    bestCount = count
                    bestColumn = column
                }
            }
            layout.name = bestColumn
        }
        return layout
    }

    /// Zonder kopregel: de eerste tekstkolom is de naam, de eerste getalkolom het bedrag.
    private func inferHeaderless() -> ColumnLayout? {
        let rowsWithNumber = grid.indices.filter { row in grid[row].contains { amountValue($0) != nil } }
        guard !rowsWithNumber.isEmpty else { return nil }
        let width = table.columnCount
        guard width >= 2 else { return nil }

        func textShare(_ column: Int) -> Double {
            var hits = 0
            for row in rowsWithNumber {
                let value = cell(row, column)
                if case .text = value, !value.isBlank, amountValue(value) == nil { hits += 1 }
            }
            return Double(hits) / Double(rowsWithNumber.count)
        }
        func numberShare(_ column: Int) -> Double {
            var hits = 0
            for row in rowsWithNumber where amountValue(cell(row, column)) != nil { hits += 1 }
            return Double(hits) / Double(rowsWithNumber.count)
        }

        var textColumns = (0..<width).filter { textShare($0) >= 0.6 }
        if textColumns.isEmpty { textColumns = (0..<width).filter { textShare($0) > 0 } }
        guard let nameColumn = textColumns.first else { return nil }
        guard let amountColumn = (0..<width).first(where: { $0 != nameColumn && numberShare($0) >= 0.6 })
            ?? (0..<width).first(where: { $0 != nameColumn && numberShare($0) > 0 }) else { return nil }

        var layout = ColumnLayout()
        layout.name = nameColumn
        layout.amount = amountColumn
        // Een tekstkolom links van de naam met kopjes als "Vaste lasten" is de categorie.
        for candidate in textColumns where candidate < nameColumn {
            var labels = 0
            var filled = 0
            for row in rowsWithNumber {
                if let t = text(row, candidate) {
                    filled += 1
                    if ImportLabels.category(of: t) != nil { labels += 1 }
                }
            }
            if filled > 0, Double(labels) / Double(filled) >= 0.6 {
                layout.category = candidate
                break
            }
        }
        // Als de "naam" juist de categorie bleek te zijn en er rechts een tweede tekstkolom staat, schuif dan door.
        if layout.category == nil, let next = textColumns.first(where: { $0 > nameColumn && $0 < amountColumn }) {
            var labels = 0
            var filled = 0
            for row in rowsWithNumber {
                if let t = text(row, nameColumn) {
                    filled += 1
                    if ImportLabels.category(of: t) != nil { labels += 1 }
                }
            }
            if filled > 0, Double(labels) / Double(filled) >= 0.6 {
                layout.category = nameColumn
                layout.name = next
            }
        }
        return layout
    }

    // MARK: Bedragen

    /// Het bedrag in een cel, met teken. Getallen en tekst als "€ 1.234,56"; geen percentages, datums of tekst.
    private func amountValue(_ value: CellValue) -> Double? {
        switch value {
        case .number(let number): return number.isFinite ? number : nil
        case .text(let raw): return AmountText.parse(raw)
        default: return nil
        }
    }

    private struct Extracted {
        var signed: Double
        var notes: [String] = []
        var meaning: ImportAmountMeaning?
        var forced: ForcedKind = .unforced
        var invested: Double?
        var units: Double?
        var fromColumns = false
        /// Spaarpot of belegging: het saldo of de waarde die naast een bedrag per maand staat.
        var balance: Double?
        /// Stond er in het bestand echt een min-teken bij het bedrag (en is het ook als uitgave gelezen)?
        /// Een bedrag in een kolom Uitgaven of met "Af" erbij is wel negatief gemaakt, maar had geen min-teken.
        var hadMinusSign = false
    }

    private func monthName(_ number: Int) -> String {
        Fmt.monthNames[max(1, min(12, number)) - 1]
    }

    private func extractAmount(row: Int, layout: ColumnLayout) -> Extracted? {
        var result: Extracted?
        // Had het bedrag in de cel zelf een min-teken? (Voor de melding over negatieve bedragen.)
        var rawNegative = false

        // 1. Indeling per maand.
        if layout.months.count >= 2 {
            var filled: [(month: Int, value: Double)] = []
            for (number, column) in layout.months.sorted(by: { $0.key < $1.key }) {
                if let value = amountValue(cell(row, column)), value != 0 { filled.append((number, value)) }
            }
            if !filled.isEmpty {
                var notes: [String] = []
                let chosen: Double
                let values = filled.map { CentsMath.int($0.value) }
                if values.allSatisfy({ $0 == values[0] }) {
                    chosen = filled[0].value
                } else if let current = filled.first(where: { $0.month == month.month }) {
                    chosen = current.value
                    notes.append("Bedrag van \(monthName(month.month)).")
                } else {
                    let sum = values.reduce(0, +)
                    chosen = CentsMath.value(Int((Double(sum) / Double(values.count)).rounded()))
                    notes.append("Gemiddelde van \(values.count) gevulde maanden.")
                }
                result = Extracted(signed: chosen, notes: notes, meaning: .perMaand)
                rawNegative = chosen < 0
            }
        }

        // 2. Aparte kolommen voor inkomsten en uitgaven.
        if result == nil, layout.income != nil || layout.expense != nil {
            if let value = amountValue(cell(row, layout.income)), value != 0 {
                result = Extracted(signed: abs(value), forced: .income)
                rawNegative = value < 0
            } else if let value = amountValue(cell(row, layout.expense)), value != 0 {
                result = Extracted(signed: -abs(value), forced: .expense)
                rawNegative = value < 0
            }
        }

        // 3. Eén bedragkolom.
        if result == nil, let column = layout.amount, let value = amountValue(cell(row, column)), value != 0 {
            rawNegative = value < 0
            var extracted = Extracted(signed: value * layout.amountFactor, meaning: layout.amountMeaning, forced: layout.forced)
            if let factorNote = layout.factorNote { extracted.notes.append(factorNote) }
            if layout.forced == .expense { extracted.signed = -abs(extracted.signed) }
            if layout.forced == .income { extracted.signed = abs(extracted.signed) }
            result = extracted
        }

        // 4. Beleggingskolommen: waarde, ingelegd, aantal x koers, saldo.
        var invested: Double?
        if let value = amountValue(cell(row, layout.invested)), value > 0 { invested = value }
        var units: Double?
        if let value = amountValue(cell(row, layout.units)), value > 0 { units = value }
        if result == nil {
            if let value = amountValue(cell(row, layout.value)), value != 0 {
                result = Extracted(signed: value, meaning: .saldo, fromColumns: true)
                rawNegative = value < 0
            } else if let invested, layout.amount == nil {
                result = Extracted(signed: invested, meaning: .saldo, fromColumns: true)
            } else if let units, let price = amountValue(cell(row, layout.price)), price > 0 {
                result = Extracted(signed: units * price, notes: ["Aantal maal koers."], meaning: .saldo, fromColumns: true)
            } else if let value = amountValue(cell(row, layout.balance)), value != 0 {
                result = Extracted(signed: value, meaning: .saldo, fromColumns: true)
                rawNegative = value < 0
            }
        }
        guard var extracted = result else { return nil }
        extracted.invested = invested
        extracted.units = units

        // Staat er naast het bedrag per maand ook een saldo of een waarde (kolom Saldo, Waarde of Aantal x Koers)?
        // Dan is dat wat er nu in de spaarpot of belegging zit; dat nemen we mee als beginsaldo.
        if !extracted.fromColumns {
            var found: Double?
            for column in [layout.balance, layout.value] where found == nil {
                if let value = amountValue(cell(row, column)), value > 0 { found = value }
            }
            if found == nil, let units, let price = amountValue(cell(row, layout.price)), price > 0 {
                found = units * price
            }
            extracted.balance = found.map { $0.cents }
        }

        // Af/Bij.
        if let column = layout.direction, let flag = text(row, column) {
            let normalized = ImportText.normalize(flag)
            if ["af", "debet", "d", "db"].contains(normalized) {
                extracted.signed = -abs(extracted.signed)
            } else if ["bij", "credit", "c", "cr"].contains(normalized) {
                extracted.signed = abs(extracted.signed)
            }
        }
        extracted.hadMinusSign = rawNegative && extracted.signed < 0
        return extracted
    }

    // MARK: Boekingen over meerdere maanden

    /// Een lijst met boekingen (een bankexport) over meerdere maanden: tel niet alles op, maar kies één maand.
    /// Dat doen we alleen bij een echte boekingenlijst: minstens 12 regels met een datum, over minstens 2 maanden,
    /// waarin namen terugkomen. Een begroting met een paar vervaldatums blijft dus heel.
    private func transactionMonths(layouts: [Int: [ColumnLayout]], initial: [ColumnLayout]) -> (rowMonths: [Int: YearMonth], chosen: YearMonth?) {
        var current = initial
        var rowMonths: [Int: YearMonth] = [:]
        var names = Set<String>()
        var dated = 0
        for row in grid.indices {
            if let header = layouts[row] {
                current = header
                continue
            }
            guard let layout = current.first(where: { $0.date != nil }), let dateColumn = layout.date else { continue }
            let date: SheetDate?
            switch cell(row, dateColumn) {
            case .date(let value): date = value
            case .text(let raw): date = ImportText.parseDate(raw)
            case .number(let serial): date = serial > 31 ? SheetDate.fromExcelSerial(serial) : nil
            default: date = nil
            }
            guard let date else { continue }
            dated += 1
            rowMonths[row] = YearMonth(year: date.year, month: date.month)
            if let name = text(row, layout.name) { names.insert(ImportText.normalize(name)) }
        }
        let distinct = Set(rowMonths.values)
        guard dated >= 12, distinct.count >= 2, names.count < dated else { return ([:], nil) }
        let chosen = distinct.contains(month) ? month : distinct.max()
        return (rowMonths, chosen)
    }

    // MARK: Hoofdlus

    /// Het aantal rijen per blad dat we indelen; meer dan dit is geen begroting maar een lijst van betalingen.
    static let maxRowsPerTable = 5_000

    /// Een kopje als "Vaste lasten" (met categorie) of "Uitgaven" (zonder); nil als de tekst geen kopje van ons is.
    private func headingSection(for heading: String) -> HeadingSection? {
        if let label = ImportLabels.category(of: heading) {
            return HeadingSection(category: label.category, title: ImportText.cleanName(heading))
        }
        if ImportLabels.isGeneric(heading) {
            return HeadingSection(category: nil, title: ImportText.cleanName(heading))
        }
        return nil
    }

    func run() -> (rows: [ImportRow], warnings: [String]) {
        guard !grid.isEmpty else { return ([], []) }

        // Kopregels zoeken en per kopregel de kolommen vastleggen (meestal één tabel, soms twee naast elkaar).
        var headerRows: [Int] = []
        var candidates: [Int: [ColumnLayout]] = [:]
        for row in grid.indices {
            let found = evaluateHeader(row: row)
            if !found.isEmpty {
                headerRows.append(row)
                candidates[row] = found
            }
        }
        var layoutAtHeader: [Int: [ColumnLayout]] = [:]
        for (index, row) in headerRows.enumerated() {
            let end = index + 1 < headerRows.count ? headerRows[index + 1] : grid.count
            if let found = candidates[row] {
                layoutAtHeader[row] = found.map { resolve($0, rowsFrom: row + 1, to: end) }
            }
        }

        var current: [ColumnLayout] = []
        if headerRows.isEmpty, let guessed = inferHeaderless() { current = [guessed] }
        let transactions = transactionMonths(layouts: layoutAtHeader, initial: current)
        var otherMonthRows = 0

        let sheetLabel = ImportLabels.category(of: table.name)
        var sections: [HeadingSection?] = current.map { _ in nil }
        var preSection: HeadingSection?
        var rows: [ImportRow] = []
        var warnings: [String] = []
        var negativeSeen = false
        var negativeCount = 0
        var hugeSkipped = 0
        var cache: [String: ImportKeywordHit?] = [:]
        var pendingMeaning: [(index: Int, hasHoldingFigures: Bool)] = []
        var guessedPositive: [Int] = []
        var monthNameRows: [Int] = []
        var processed = 0
        var capped = false

        for row in grid.indices {
            if capped { break }
            if let headerLayouts = layoutAtHeader[row] {
                current = headerLayouts
                let previous = sections
                sections = headerLayouts.enumerated().map { index, layout in
                    // De kop zelf ("Inkomsten") gaat voor, dan het kopje dat er al was, dan het kopje vóór de kop.
                    if let category = layout.headingCategory {
                        return HeadingSection(category: category, title: layout.headingTitle ?? "")
                    }
                    // Een nieuwe tabel "Uitgaven" (of "Kosten") onder "Inkomsten" is zelf een kopje zonder vaste categorie:
                    // het kopje van de tabel ervoor geldt dan niet meer.
                    if let title = layout.headingTitle, ImportLabels.isGeneric(title) {
                        return HeadingSection(category: nil, title: ImportText.cleanName(title))
                    }
                    if index < previous.count, let existing = previous[index] { return existing }
                    return index == 0 ? preSection : nil
                }
                continue
            }
            let cells = grid[row]
            if cells.allSatisfy({ $0.isBlank }) { continue }

            // Een kopje voor de eerste kopregel ("Vaste lasten", daaronder de kolomnamen).
            if current.isEmpty {
                if let heading = pureHeading(cells), let found = headingSection(for: heading) { preSection = found }
                continue
            }

            for (index, layout) in current.enumerated() {
                let part = slice(row, layout)
                if part.allSatisfy({ $0.isBlank }) { continue }

                // Een rij met alleen (herhaalde) tekst is een kopje.
                if let heading = pureHeading(part) {
                    if let found = headingSection(for: heading) { sections[index] = found }
                    continue
                }

                if let chosen = transactions.chosen, let rowMonth = transactions.rowMonths[row], rowMonth != chosen {
                    otherMonthRows += 1
                    continue
                }

                processed += 1
                if processed > TableMapper.maxRowsPerTable {
                    warnings.append("Blad '\(table.name)' heeft meer dan \(TableMapper.maxRowsPerTable) regels; alleen de eerste zijn gebruikt.")
                    capped = true
                    break
                }

                guard let nameText = rowName(row: row, layout: layout) else { continue }
                let normalizedName = ImportText.normalize(nameText)
                guard !normalizedName.isEmpty else { continue }
                guard let extracted = extractAmount(row: row, layout: layout) else {
                    // Een rij als "Kosten | Bedrag" is een kopregel die we niet als kop herkennen, maar wel als kopje:
                    // de rijen eronder horen dan niet meer bij het vorige kopje (bijvoorbeeld "Inkomsten").
                    if part.allSatisfy({ amountValue($0) == nil }), let found = headingSection(for: nameText) {
                        sections[index] = found
                    }
                    continue
                }

                // Totaalregels tellen niet mee.
                if ImportText.isTotalName(normalizedName) {
                    rows.append(ImportRow(sheet: table.name, sourceRow: row + 1, name: ImportText.cleanName(nameText),
                                          amount: CentsMath.value(CentsMath.int(abs(extracted.signed))), category: .overslaan,
                                          confidence: .hoog, reason: "totaalregel", note: "", isIncluded: false))
                    continue
                }

                // Een kopje met het totaal erbij ("Vaste lasten  1.470") is geen regel.
                if let label = ImportLabels.category(of: nameText),
                   isSectionTotal(row: row, layout: layout, amount: abs(extracted.signed), name: nameText) {
                    sections[index] = HeadingSection(category: label.category, title: ImportText.cleanName(nameText))
                    continue
                }

                let amount = CentsMath.value(CentsMath.int(abs(extracted.signed)))
                guard amount > 0 else { continue }
                guard amount <= ImportMapper.maxAmount else {
                    hugeSkipped += 1
                    continue
                }
                if extracted.signed < 0 { negativeCount += 1 }
                // Alleen een echt min-teken in het bestand is de melding waard; een kolom Uitgaven is niet negatief.
                if extracted.hadMinusSign { negativeSeen = true }

                let keyword: ImportKeywordHit?
                if let cached = cache[normalizedName] {
                    keyword = cached
                } else {
                    keyword = ImportKeywords.best(in: nameText)
                    cache[normalizedName] = .some(keyword)
                }
                let made = makeRow(row: row, layout: layout, name: nameText, keyword: keyword, extracted: extracted,
                                   amount: amount, section: sections[index], sheetLabel: sheetLabel)
                rows.append(made.row)
                // De maanden onder elkaar (januari, februari, ...) worden niet ondersteund: onthoud die rijen, zie hieronder.
                if layout.months.count < 2, ImportText.monthNumber(normalizedName) != nil { monthNameRows.append(rows.count - 1) }
                if made.row.reason == ImportMapper.guessReason && extracted.signed > 0 { guessedPositive.append(rows.count - 1) }
                if let decided = made.meaning, made.row.category == .spaarpot || made.row.category == .belegging {
                    rows[rows.count - 1].meaning = decided
                } else if made.row.category == .spaarpot || made.row.category == .belegging {
                    pendingMeaning.append((index: rows.count - 1, hasHoldingFigures: layout.units != nil || layout.price != nil))
                }
            }
        }

        // Staat bij een derde of meer van de regels een min-teken (een bankexport), dan is een onbekende regel met een
        // plusteken een bijschrijving. Een enkele min in een begroting zegt daar niets over.
        let activeCount = rows.filter { $0.category != .overslaan }.count
        if negativeCount >= 1, negativeCount * 3 >= activeCount {
            for index in guessedPositive {
                rows[index].category = .inkomen
                rows[index].reason = "plusteken naast uitgaven met een min-teken: bijschrijving"
            }
        }

        // Een belegging zonder aanwijzing: staat het in een lijst met ook inkomsten en lasten, dan is het de inleg per maand.
        if !pendingMeaning.isEmpty {
            let budgetContext = rows.contains { $0.category == .inkomen || $0.category == .vasteLasten || $0.category == .variabeleLasten }
            for pending in pendingMeaning {
                let meaning: ImportAmountMeaning = (budgetContext && !pending.hasHoldingFigures) ? .perMaand : .saldo
                rows[pending.index].meaning = meaning
                let hint = meaning == .perMaand ? "Opgevat als inleg per maand." : "Opgevat als wat er nu in zit."
                rows[pending.index].note = rows[pending.index].note.isEmpty ? hint : rows[pending.index].note + " " + hint
            }
        }

        // Maandnamen als regels (januari 2800, februari 2800, ...): een tabel met de maanden onder elkaar. Dat lezen we niet;
        // die regels zijn geen uitgaven. Eén enkele regel die zo heet (een pot "Mei") laten we staan.
        if monthNameRows.count >= 2 {
            let removed = Set(monthNameRows)
            rows = rows.enumerated().filter { !removed.contains($0.offset) }.map { $0.element }
            warnings.append("In blad '\(table.name)' staan de maanden onder elkaar. Dat wordt niet ondersteund: zet de maanden naast elkaar (jan t/m dec).")
        }

        if let chosen = transactions.chosen, otherMonthRows > 0 {
            warnings.append("Blad '\(table.name)' bevat boekingen uit meerdere maanden. Alleen \(Fmt.month(chosen)) is gebruikt; \(otherMonthRows) regels uit andere maanden zijn overgeslagen.")
        }
        if negativeSeen {
            warnings.append("In blad '\(table.name)' staan negatieve bedragen; die zijn als uitgaven gelezen.")
        }
        if hugeSkipped > 0 {
            warnings.append("In blad '\(table.name)' zijn \(hugeSkipped) regels met een onwaarschijnlijk groot bedrag overgeslagen.")
        }
        if table.isTruncated {
            warnings.append("Blad '\(table.name)' heeft meer dan \(XLSXReader.maxRows) rijen; alleen de eerste zijn gelezen.")
        }
        return (rows, warnings)
    }

    /// De tekst als de rij alleen tekst heeft en elke gevulde cel dezelfde tekst is (ook samengevoegde cellen).
    private func pureHeading(_ cells: [CellValue]) -> String? {
        var heading: String?
        var normalizedHeading = ""
        for value in cells where !value.isBlank {
            guard case .text = value, let t = value.trimmedText else { return nil }
            if heading == nil {
                heading = t
                normalizedHeading = ImportText.normalize(t)
            } else if ImportText.normalize(t) != normalizedHeading {
                return nil
            }
        }
        return heading
    }

    /// De naam van een rij: de naamkolom, anders de categoriekolom.
    private func rowName(row: Int, layout: ColumnLayout) -> String? {
        if let name = text(row, layout.name) { return name }
        if layout.name == nil || cell(row, layout.name).isBlank {
            if let category = text(row, layout.category) { return category }
        }
        return nil
    }

    /// Klopt het bedrag naast een kopje met de som van de rijen eronder? Dan is het een totaal en geen regel.
    private func isSectionTotal(row: Int, layout: ColumnLayout, amount: Double, name: String) -> Bool {
        var sum = 0
        var next = row + 1
        var counted = 0
        while next < grid.count, counted < 80 {
            let cells = slice(next, layout)
            if cells.allSatisfy({ $0.isBlank }) { break }
            if !evaluateHeader(row: next).isEmpty { break }
            if pureHeading(cells) != nil { break }
            if let nextName = rowName(row: next, layout: layout) {
                if ImportText.isTotalName(ImportText.normalize(nextName)) { break }
                if ImportLabels.isStrongHeading(nextName), extractAmount(row: next, layout: layout) != nil { break }
                if let extracted = extractAmount(row: next, layout: layout) {
                    sum += CentsMath.int(abs(extracted.signed))
                }
            }
            next += 1
            counted += 1
        }
        if sum > 0 {
            let difference = abs(sum - CentsMath.int(amount))
            if difference <= max(1, Int(Double(sum) * 0.005)) { return true }
        }
        return ImportLabels.isStrongHeading(name)
    }

    // MARK: Een rij indelen

    private func forcedColumnName(_ layout: ColumnLayout, _ forced: ForcedKind) -> String {
        if !layout.amountHeader.isEmpty { return layout.amountHeader }
        let column = forced == .income ? layout.income : layout.expense
        if let column, layout.headerRow >= 0 { return cell(layout.headerRow, column).displayText }
        return forced == .income ? "Inkomsten" : "Uitgaven"
    }

    /// Geeft de rij en, voor spaarpotten en beleggingen, de betekenis van het bedrag als daar een aanwijzing voor is.
    private func makeRow(row: Int, layout: ColumnLayout, name rawName: String, keyword: ImportKeywordHit?,
                         extracted: Extracted, amount: Double, section: HeadingSection?,
                         sheetLabel: (category: ImportCategory, phrase: String)?) -> (row: ImportRow, meaning: ImportAmountMeaning?) {
        let name = ImportText.cleanName(rawName)
        var notes = extracted.notes

        let tickerCell = text(row, layout.ticker).flatMap { ImportMapper.sanitizedTicker($0) }
        let categoryText = text(row, layout.category)

        var category = ImportCategory.variabeleLasten
        var confidence = ImportConfidence.laag
        var reason = ""

        // Voorkeursvolgorde: categoriekolom, kopje, blad, ticker, vaste kolom, standaardpost, trefwoord, beleggingskolommen, gok.
        var decided = false
        var structural = false

        if let categoryText {
            if let label = ImportLabels.category(of: categoryText) {
                category = label.category
                confidence = .hoog
                reason = "categorie '\(ImportText.cleanName(categoryText))' in het bestand"
                decided = true
                structural = true
            } else if ImportLabels.isGeneric(categoryText) {
                // "Uitgaven" zegt niets over vast of variabel: de trefwoorden beslissen.
            } else if keyword == nil, let hit = ImportKeywords.best(in: categoryText) {
                category = hit.category
                confidence = .middel
                reason = "categorie '\(ImportText.cleanName(categoryText))': woord '\(hit.word)' herkend"
                decided = true
            }
        }
        if !decided, let own = ImportLabels.exactCategory(of: name) {
            // Een regel die zelf "Sparen" of "Beleggen" heet, hoort daar ook bij, wat het kopje erboven ook is.
            category = own
            confidence = .hoog
            reason = "de naam '\(name)' is een categorie"
            decided = true
        }
        if !decided, let section, let sectionCategory = section.category {
            category = sectionCategory
            confidence = .hoog
            reason = "onder het kopje '\(section.title)'"
            decided = true
            structural = true
        }
        if !decided, let sheetLabel {
            category = sheetLabel.category
            confidence = .hoog
            reason = "blad '\(table.name)'"
            decided = true
            structural = true
        }
        if !decided, let tickerCell {
            category = .belegging
            confidence = .hoog
            reason = "ticker '\(tickerCell)' ingevuld"
            decided = true
        }
        if !decided, extracted.forced == .income {
            category = .inkomen
            confidence = .hoog
            reason = "staat in de kolom '\(forcedColumnName(layout, .income))'"
            decided = true
            structural = true
        }
        if !decided, extracted.forced == .expense {
            if let keyword, keyword.category == .vasteLasten || keyword.category == .variabeleLasten {
                category = keyword.category
                confidence = keyword.confidence
                reason = "woord '\(keyword.word)' herkend"
            } else {
                category = .variabeleLasten
                confidence = .laag
                reason = "staat bij de uitgaven, soort onbekend"
            }
            decided = true
        }
        if !decided, extracted.fromColumns {
            // Een rij uit een saldo- of waardekolom is een spaarpot of belegging, tenzij het woord iets anders zegt.
            let savingKeyword = keyword.map { $0.strong && ($0.category == .spaarpot || $0.category == .belegging) } ?? false
            if !savingKeyword {
                let balanceOnly = layout.balance != nil && layout.value == nil && layout.invested == nil
                    && layout.units == nil && layout.price == nil
                category = balanceOnly ? .spaarpot : .belegging
                confidence = .middel
                reason = balanceOnly ? "staat in de kolom 'Saldo'" : "kolommen met aantal, waarde of koers"
                decided = true
            }
        }
        if !decided, let standard = ImportKeywords.standardExpense(named: name) {
            category = standard.kind == .fixed ? .vasteLasten : .variabeleLasten
            confidence = .hoog
            reason = "standaardpost '\(standard.name)'"
            decided = true
        }
        if !decided, let keyword {
            category = keyword.category
            confidence = keyword.confidence
            reason = "woord '\(keyword.word)' herkend"
            decided = true
        }
        if !decided, layout.units != nil {
            category = .belegging
            confidence = .middel
            reason = "kolom met aantal"
            decided = true
        }
        if !decided {
            if extracted.signed < 0 {
                category = .variabeleLasten
                reason = "negatief bedrag: uitgave, soort onbekend"
            } else if layout.direction != nil {
                category = .inkomen
                reason = "bijschrijving, soort onbekend"
            } else {
                category = .variabeleLasten
                reason = ImportMapper.guessReason
            }
            confidence = .laag
        }

        // Past de indeling uit de structuur bij het woord in de naam? Zo niet, dan minder zeker.
        // Alleen bij een sterk woord: een pot "Vakantie" onder het kopje Sparen is gewoon goed ingedeeld.
        if structural, let keyword, keyword.strong, keyword.category != category, keyword.word.count >= 6, confidence == .hoog {
            confidence = .middel
            reason += "; let op: '\(keyword.word)' wijst op \(keyword.category.title.lowercased())"
        }

        // Dag.
        var day: Int?
        if let column = layout.day { day = ImportText.dayNumber(from: cell(row, column)) }
        if day == nil, let column = layout.date {
            let value = cell(row, column)
            if case .number(let serial) = value, serial > 31, let date = SheetDate.fromExcelSerial(serial) {
                // Een datum die als gewoon getal is bewaard (kolom "Datum" zonder datumopmaak).
                day = date.day
            } else {
                day = ImportText.dayNumber(from: value)
            }
        }

        var made = ImportRow(sheet: table.name, sourceRow: row + 1, name: name, amount: amount, category: category,
                             day: day, confidence: confidence, reason: reason)

        var meaning: ImportAmountMeaning?
        if category == .spaarpot || category == .belegging {
            meaning = decideMeaning(category: category, name: name, extracted: extracted, layout: layout)
            if let meaning { made.meaning = meaning }
            // Het saldo naast een bedrag per maand wordt het beginsaldo; bij "huidig bedrag" is het bedrag zelf het saldo.
            if meaning != .saldo { made.balance = extracted.balance }
            if let meaning, let hint = meaningNote(meaning, extracted: extracted, layout: layout, name: name) { notes.append(hint) }
        }
        if category == .belegging {
            made.ticker = tickerCell ?? ImportMapper.tickerFromName(name)
            if tickerCell == nil, let found = made.ticker { notes.append("Ticker '\(found)' herkend aan de naam.") }
            made.units = extracted.units
            made.invested = extracted.invested
        }
        made.note = notes.joined(separator: " ")
        return (made, meaning)
    }

    /// Is het bedrag bij een spaarpot of belegging de inleg per maand of wat er nu in zit? nil = geen aanwijzing.
    private func decideMeaning(category: ImportCategory, name: String, extracted: Extracted, layout: ColumnLayout) -> ImportAmountMeaning? {
        if extracted.fromColumns { return .saldo }
        let normalized = ImportText.normalize(name)
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        if normalized.contains("per maand") || normalized.contains("maandelijks") || normalized.contains("maandinleg")
            || normalized.contains("inleg") || normalized.contains("storting") || tokens.contains("pm") { return .perMaand }
        if tokens.contains("saldo") || tokens.contains("stand") || normalized.contains("huidige waarde") { return .saldo }
        if let fromHeader = extracted.meaning ?? layout.amountMeaning { return fromHeader }
        let header = ImportText.normalize(layout.amountHeader)
        if header.contains("saldo") || header.contains("waarde") || header.contains("stand") || header.contains("ingelegd") { return .saldo }
        if layout.value != nil || layout.invested != nil || layout.balance != nil { return .saldo }
        // Zonder saldo-context is een bedrag naast een spaarpot de maandelijkse inleg.
        if category == .spaarpot { return .perMaand }
        return nil
    }

    private func meaningNote(_ meaning: ImportAmountMeaning, extracted: Extracted, layout: ColumnLayout, name: String) -> String? {
        if extracted.fromColumns { return nil }
        if extracted.meaning != nil || layout.amountMeaning != nil { return nil }
        let normalized = ImportText.normalize(name)
        if normalized.contains("per maand") || normalized.contains("saldo") || normalized.contains("inleg") { return nil }
        return meaning == .perMaand ? "Opgevat als inleg per maand." : "Opgevat als wat er nu in zit."
    }
}

// MARK: - Toepassen

extension FinanceData {
    /// Voegt de aangezette rijen van de conceptlijst toe aan `month`. Er wordt niets vervangen of gewist.
    /// Een item met dezelfde naam (hoofdletterongevoelig) wordt overgeslagen ("bestaat al"), of bijgewerkt bij `.update`.
    /// - inkomen: extra inkomsten van die maand (terugkerend)
    /// - vaste en variabele lasten: uitgaveregels (terugkerend)
    /// - spaarpot: een nieuwe pot, met het bedrag als beginsaldo of als maandinleg
    /// - belegging: een nieuwe belegging, met het bedrag als ingelegd/waarde of als maandinleg
    @discardableResult
    mutating func applyImport(_ draft: ImportDraft, month: YearMonth,
                              existing policy: ImportExistingPolicy = .skip, now: Date = Date()) -> ImportReport {
        // Een maand voor de startmaand telt nergens mee: dan de startmaand.
        let target = max(month, startMonth)
        var report = ImportReport(month: target)
        if target != month {
            report.notes.append("De gekozen maand ligt vóór je startmaand; het is \(Fmt.month(target)) geworden.")
        }

        func key(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        for row in draft.rows {
            guard row.isActive else {
                report.notSelected += 1
                continue
            }
            let name = ImportText.cleanName(row.name)
            guard !name.isEmpty, row.amount > 0 else {
                report.notSelected += 1
                continue
            }
            let amount = row.amount.cents
            let day = row.day.map { YearMonth.clampedDay($0) }

            func record(_ outcome: ImportOutcome) {
                report.lines.append(ImportReportLine(name: name, category: row.category, amount: amount, outcome: outcome))
            }

            switch row.category {
            case .inkomen:
                // Een regel uit het bestand is een terugkerende regel (een reeks): hij geldt vanaf deze maand, ook in
                // maanden erna die al zijn vastgelegd. Bijwerken geldt ook voor "deze en alle volgende maanden".
                if var line = plan(for: target).extraIncome.first(where: { key($0.name) == key(name) }) {
                    if policy == .update {
                        line.amount = amount
                        if let day { line.day = day }
                        upsertLine(line, kind: .income, in: target, scope: .thisAndFollowing)
                        record(.updated)
                    } else {
                        record(.skippedExisting)
                    }
                } else {
                    addOrResumeRecurringLine(MoneyLine(name: name, amount: amount, isRecurring: true, kind: .fixed, day: day),
                                             kind: .income, in: target)
                    record(.added)
                }

            case .vasteLasten, .variabeleLasten:
                let kind: ExpenseKind = row.category == .vasteLasten ? .fixed : .variable
                if var line = plan(for: target).expenses.first(where: { key($0.name) == key(name) }) {
                    if policy == .update {
                        line.amount = amount
                        if let day { line.day = day }
                        upsertLine(line, kind: .expense, in: target, scope: .thisAndFollowing)
                        record(.updated)
                    } else {
                        record(.skippedExisting)
                    }
                } else {
                    addOrResumeRecurringLine(MoneyLine(name: name, amount: amount, isRecurring: true, kind: kind, day: day),
                                             kind: .expense, in: target)
                    record(.added)
                }

            case .spaarpot:
                if let existingPot = pots.first(where: { key($0.name) == key(name) }) {
                    if policy == .update {
                        if row.meaning == .perMaand {
                            // Een inleg per maand uit het bestand is een vast bedrag: stond de pot op een percentage
                            // van je inkomen, dan wordt het dat bedrag (en geldt het meteen voor deze maand).
                            setContributionAmount(existingPot.id, amount: amount, current: target)
                        } else {
                            setPotBalance(existingPot.id, to: amount, current: target, note: "Import", date: now, asOf: now)
                        }
                        record(.updated)
                    } else {
                        record(.skippedExisting)
                    }
                } else {
                    let monthly = row.meaning == .perMaand
                    var pot = Pot(name: name, symbol: ImportMapper.potSymbol(for: name), colorIndex: pots.count % 8,
                                  monthlyContribution: monthly ? amount : 0, startMonth: target)
                    if monthly, let day { pot.transferDay = day }
                    // Bij een inleg per maand is het saldo uit het bestand (als dat er is) het beginsaldo.
                    let opening = monthly ? max(0, row.balance ?? 0).cents : amount
                    addPot(pot, openingBalance: opening, now: now)
                    record(.added)
                }

            case .belegging:
                if let existingHolding = holdings.first(where: { key($0.name) == key(name) }) {
                    if policy == .update {
                        if row.meaning == .perMaand {
                            setContributionAmount(existingHolding.id, amount: amount, current: target)
                        } else {
                            addSnapshot(holdingID: existingHolding.id, value: amount, invested: row.invested, date: now)
                        }
                        record(.updated)
                    } else {
                        record(.skippedExisting)
                    }
                } else {
                    let kind = ImportMapper.holdingKind(for: name, ticker: row.ticker)
                    let monthly = row.meaning == .perMaand
                    // Een inleg per maand met ook een waarde in het bestand: die waarde is wat er nu in zit.
                    let knownValue: Double? = monthly ? row.balance.flatMap { $0 > 0 ? $0.cents : nil } : amount
                    var holding = Holding(name: name, kind: kind, ticker: row.ticker,
                                          units: (monthly && knownValue == nil) ? nil : row.units,
                                          investedTotal: knownValue.map { ($0 > 0 ? (row.invested ?? $0) : 0).cents } ?? 0,
                                          expectedReturn: kind.defaultReturn, annualCost: kind.defaultCost,
                                          monthlyContribution: monthly ? amount : 0, startMonth: target)
                    if monthly, let day { holding.transferDay = day }
                    if let knownValue {
                        addHolding(holding, initialValue: knownValue, now: now)
                    } else {
                        // Alleen een inleg per maand: een beginpunt van 0 aan het eind van de vorige maand,
                        // zodat de inleg van deze maand meetelt.
                        let baseline = target.firstDay.addingTimeInterval(-12 * 3_600)
                        addHolding(holding, initialValue: 0, now: baseline)
                    }
                    record(.added)
                }

            case .overslaan:
                report.notSelected += 1
            }
        }

        return report
    }
}

// MARK: - Voorbeeldbestand

/// Het voorbeeldbestand dat je kunt downloaden: zo ziet een bestand eruit dat de app goed leest.
enum ImportTemplate {
    static let baseFileName = "MyBuddy-importvoorbeeld"

    /// De rijen van het voorbeeld (kop + regels).
    static var rows: [[XLSXWriteCell]] {
        func line(_ category: String, _ name: String, _ amount: Double, day: Double? = nil, ticker: String? = nil) -> [XLSXWriteCell] {
            [.text(category), .text(name), .amount(amount), day.map { XLSXWriteCell.number($0) } ?? .empty, ticker.map { XLSXWriteCell.text($0) } ?? .empty]
        }
        return [
            [.header("Categorie"), .header("Omschrijving"), .header("Bedrag per maand"), .header("Dag van de maand"), .header("Ticker (alleen beleggingen)")],
            line("Inkomsten", "Salaris", 2800, day: 25),
            line("Inkomsten", "Kinderbijslag", 250),
            line("Vaste lasten", "Huur", 1050, day: 1),
            line("Vaste lasten", "Zorgverzekering", 145, day: 1),
            line("Vaste lasten", "Internet en tv", 55),
            line("Vaste lasten", "Energie", 120),
            line("Variabele lasten", "Boodschappen", 380),
            line("Variabele lasten", "Uit eten", 90),
            line("Variabele lasten", "Kleding", 60),
            line("Sparen", "Noodfonds", 150),
            line("Sparen", "Vakantiepot", 100),
            line("Beleggingen", "Wereld-ETF", 250, ticker: "VWCE.DE")
        ]
    }

    static var explanation: [[XLSXWriteCell]] {
        [
            [.header("Zo maak je een bestand dat MyBuddy goed leest")],
            [.text("1. Zet in de bovenste rij kolomnamen, zoals in het blad Begroting: Categorie, Omschrijving, Bedrag per maand.")],
            [.text("2. Categorie is Inkomsten, Vaste lasten, Variabele lasten, Sparen of Beleggingen. Zonder categorie raadt MyBuddy het aan de hand van de omschrijving.")],
            [.text("3. De kolommen Dag van de maand en Ticker mag je weglaten. Een ticker (bijvoorbeeld VWCE.DE) laat de app de koers volgen.")],
            [.text("4. Bedragen mogen getallen zijn of tekst zoals € 1.234,56. Een min-teken telt als uitgave.")],
            [.text("5. Je kunt ook een indeling per maand gebruiken, met kolommen jan t/m dec. MyBuddy neemt dan de huidige maand of het gemiddelde.")],
            [.text("6. Voor je importeert zie je een overzicht waarin je alles nog kunt aanpassen. Wat al bestaat wordt niet dubbel toegevoegd.")]
        ]
    }

    /// Het voorbeeld als .xlsx.
    static func workbookData() -> Data {
        XLSXWriter.data(sheets: [
            XLSXWriteSheet(name: "Begroting", rows: rows, columnWidths: [20, 28, 18, 18, 28]),
            XLSXWriteSheet(name: "Uitleg", rows: explanation, columnWidths: [120])
        ])
    }

    /// Het voorbeeld als CSV (puntkomma, komma als decimaalteken).
    static func csvText() -> String {
        var out = ""
        for row in rows {
            let cells: [String] = row.map { cell in
                switch cell {
                case .empty: return ""
                case .text(let text), .header(let text): return CSVExport.text(text)
                case .number(let value): return CSVExport.decimal(value, maxDecimals: 2, minDecimals: 0)
                case .amount(let value): return CSVExport.number(value)
                }
            }
            out += cells.joined(separator: CSVExport.delimiter) + "\n"
        }
        return out
    }
}
