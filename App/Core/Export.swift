import Foundation

// MARK: - Keuze van bestandstype
//
// JSON is de volledige back-up. Het bestand bevat alles wat de app weet (spaarpotten, boekingen,
// beleggingen, doelen, instellingen), is leesbaar voor mensen, heeft een versienummer en kan
// zonder verlies weer worden ingelezen. Het is bovendien precies hoe de app zelf opslaat.
//
// CSV is alleen voor analyse in Numbers of Excel (alleen exporteren, niet terugzetten). Het is
// platte tabellen zonder structuur, dus niet geschikt als back-up. Puntkomma als scheiding en komma als
// decimaalteken, omdat Nederlandse spreadsheets dat verwachten.
//
// Afgewezen: plist of de opslag van Core Data/SwiftData (niet draagbaar, alleen leesbaar voor Apple-tools)
// en PDF (mooi om te lezen, maar niet terug te zetten).

// MARK: - Back-up (JSON)

/// De verpakking om een back-up: laat zien wat voor bestand het is en welke versie.
struct BackupEnvelope: Codable {
    static let formatName = "mybuddy-backup"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var appVersion: String
    var data: FinanceData
}

/// Wat er in een ingelezen bestand zat. `exportedAt` is nil bij een kaal `finance.json`.
struct BackupContents {
    var data: FinanceData
    var exportedAt: Date?
    var appVersion: String?

    var potCount: Int { data.pots.count }
    var holdingCount: Int { data.holdings.count }
    var goalCount: Int { data.goals.count }

    /// "3 spaarpotten, 1 belegging"
    var summaryText: String {
        BackupContents.countText(potCount, one: "spaarpot", many: "spaarpotten")
            + ", "
            + BackupContents.countText(holdingCount, one: "belegging", many: "beleggingen")
    }

    static func countText(_ count: Int, one: String, many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }
}

enum BackupError: LocalizedError, Equatable {
    /// Geen JSON, of JSON van iets anders dan MyBuddy.
    case notAMyBuddyFile
    /// Gemaakt met een nieuwere versie van het bestandsformaat.
    case newerVersion(Int)
    /// Wel een MyBuddy-bestand, maar de inhoud klopt niet of het bestand is te groot.
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notAMyBuddyFile:
            return "Dit is geen MyBuddy-back-up. Kies een JSON-bestand dat je met 'Back-up exporteren' hebt gemaakt."
        case .newerVersion(let version):
            return "Deze back-up is gemaakt met een nieuwere versie van MyBuddy (bestandsversie \(version)). Werk de app bij en probeer het opnieuw."
        case .unreadable(let detail):
            return "De back-up kon niet worden gelezen. \(detail)"
        }
    }
}

enum BackupService {
    /// Versie van de app die in de back-up wordt vermeld.
    static let appVersion = "1.0"
    /// Grootste bestand dat we willen inlezen. Een echte back-up is hooguit een paar MB.
    static let maxImportBytes = 50 * 1024 * 1024

    // MARK: Exporteren

    /// Alle gegevens als JSON: opgemaakt, vaste volgorde van sleutels, datums als ISO 8601.
    static func export(_ data: FinanceData, now: Date = Date()) throws -> Data {
        let envelope = BackupEnvelope(format: BackupEnvelope.formatName,
                                      version: BackupEnvelope.currentVersion,
                                      exportedAt: now,
                                      appVersion: appVersion,
                                      data: data)
        return try FinanceStorage.makeEncoder().encode(envelope)
    }

    // MARK: Importeren

    /// Leest een back-up of een kaal `finance.json` en geeft de gegevens terug.
    static func importBackup(_ raw: Data) throws -> FinanceData {
        try inspect(raw).data
    }

    /// Zelfde als `importBackup`, maar met de datum van de back-up erbij (voor de bevestiging).
    static func inspect(_ raw: Data) throws -> BackupContents {
        guard raw.count <= maxImportBytes else {
            throw BackupError.unreadable("Het bestand is te groot (meer dan 50 MB).")
        }
        let bytes = withoutBOM(raw)
        let decoder = FinanceStorage.makeDecoder()

        // Eerst alleen de kop bekijken: wat voor bestand is dit?
        let probe: Probe
        do {
            probe = try decoder.decode(Probe.self, from: bytes)
        } catch {
            throw BackupError.notAMyBuddyFile
        }

        if let format = probe.format {
            guard format == BackupEnvelope.formatName, let version = probe.version, version >= 1 else {
                throw BackupError.notAMyBuddyFile
            }
            guard version <= BackupEnvelope.currentVersion else {
                throw BackupError.newerVersion(version)
            }
            do {
                let envelope = try decoder.decode(BackupEnvelope.self, from: bytes)
                return BackupContents(data: envelope.data,
                                      exportedAt: envelope.exportedAt,
                                      appVersion: envelope.appVersion)
            } catch {
                throw BackupError.unreadable(describe(error))
            }
        }

        // Geen back-up-kop: misschien het kale opslagbestand. FinanceData leest ook `{}` zonder fout,
        // dus eis minstens de startmaand, anders kan elk willekeurig JSON-object je gegevens wissen.
        guard probe.startMonth != nil else {
            throw BackupError.notAMyBuddyFile
        }
        if let version = probe.version, version > BackupEnvelope.currentVersion {
            throw BackupError.newerVersion(version)
        }
        do {
            let finance = try decoder.decode(FinanceData.self, from: bytes)
            return BackupContents(data: finance, exportedAt: nil, appVersion: nil)
        } catch {
            throw BackupError.unreadable(describe(error))
        }
    }

    // MARK: Bestandsnaam

    /// "MyBuddy-back-up-2026-10-08.json"
    static func suggestedFileName(now: Date, timeZone: TimeZone = TimeZone.current) -> String {
        suggestedBaseName(now: now, timeZone: timeZone) + ".json"
    }

    /// Zonder extensie, voor `fileExporter` (die de extensie zelf uit het type haalt).
    static func suggestedBaseName(now: Date, timeZone: TimeZone = TimeZone.current) -> String {
        "MyBuddy-back-up-" + dateStamp(now, timeZone: timeZone)
    }

    /// "2026-10-08", met een vaste gregoriaanse kalender (geen invloed van taal of regio).
    static func dateStamp(_ date: Date, timeZone: TimeZone = TimeZone.current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return zeroPad(parts.year ?? 1970, width: 4) + "-"
            + zeroPad(parts.month ?? 1, width: 2) + "-"
            + zeroPad(parts.day ?? 1, width: 2)
    }

    // MARK: Hulpjes

    private static func zeroPad(_ value: Int, width: Int) -> String {
        var text = String(value)
        while text.count < width { text = "0" + text }
        return text
    }

    private struct Probe: Decodable {
        var format: String?
        var version: Int?
        var startMonth: String?
    }

    /// Sommige programma's zetten een UTF-8 BOM voor een tekstbestand.
    private static func withoutBOM(_ raw: Data) -> Data {
        if raw.count >= 3, raw[raw.startIndex] == 0xEF, raw[raw.startIndex + 1] == 0xBB, raw[raw.startIndex + 2] == 0xBF {
            return Data(raw.dropFirst(3))
        }
        return raw
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        let context: DecodingError.Context
        switch decoding {
        case .typeMismatch(_, let found), .valueNotFound(_, let found), .keyNotFound(_, let found), .dataCorrupted(let found):
            context = found
        @unknown default:
            return "Het bestand is beschadigd."
        }
        let path = context.codingPath.map { $0.stringValue }.joined(separator: " > ")
        return path.isEmpty ? "Het bestand is beschadigd of onvolledig." : "Er klopt iets niet bij: \(path)."
    }
}

// MARK: - Cijfers voor spreadsheets (CSV)

/// Welke tabel je als CSV kunt exporteren.
enum CSVReport: String, CaseIterable, Identifiable {
    case monthly, transactions, holdings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: return "Maandcijfers"
        case .transactions: return "Transacties"
        case .holdings: return "Beleggingen"
        }
    }

    /// Bestandsnaam zonder extensie, bijv. "MyBuddy-maandcijfers-2026-10-08".
    func baseFileName(now: Date, timeZone: TimeZone = TimeZone.current) -> String {
        let stem: String
        switch self {
        case .monthly: stem = "maandcijfers"
        case .transactions: stem = "transacties"
        case .holdings: stem = "beleggingen"
        }
        return "MyBuddy-" + stem + "-" + BackupService.dateStamp(now, timeZone: timeZone)
    }

    func csv(for data: FinanceData, current: YearMonth) -> String {
        switch self {
        case .monthly:
            let range = CSVExport.defaultMonthRange(data, current: current)
            return CSVExport.monthlyCSV(data, from: range.from, count: range.count, current: current)
        case .transactions:
            return CSVExport.transactionsCSV(data)
        case .holdings:
            return CSVExport.holdingsCSV(data, current: current)
        }
    }
}

/// Maakt CSV met ';' als scheiding en ',' als decimaalteken (Nederlandse spreadsheets).
/// Getallen en datums worden zelf opgemaakt, zodat het resultaat niet van taal of regio afhangt.
enum CSVExport {
    static let delimiter = ";"

    // MARK: Cellen

    /// Een tekstcel: voorkomt formules (=, +, -, @) en zet tekst met ; " of een regeleinde tussen aanhalingstekens.
    static func text(_ value: String) -> String {
        var cell = value
        if let first = cell.unicodeScalars.first, formulaStarters.contains(first) {
            cell = "'" + cell
        }
        let needsQuotes = cell.unicodeScalars.contains { quoteTriggers.contains($0) }
        if needsQuotes {
            cell = "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return cell
    }

    private static let formulaStarters: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
    private static let quoteTriggers: Set<Unicode.Scalar> = [";", "\"", "\n", "\r"]

    /// Bedrag met twee decimalen en een komma: 1234.5 wordt "1234,50". Geen duizendtallen.
    static func number(_ value: Double) -> String {
        decimal(value, maxDecimals: 2, minDecimals: 2)
    }

    /// Percentage uit een breuk: 0.205 wordt "20,50%".
    static func percent(_ fraction: Double) -> String {
        let body = number(fraction * 100)
        return body.isEmpty ? "" : body + "%"
    }

    /// Getal met een komma als decimaalteken. Rondt af op `maxDecimals` en laat overbodige nullen
    /// weg tot `minDecimals` over zijn. Leeg bij een ongeldig getal.
    static func decimal(_ value: Double, maxDecimals: Int, minDecimals: Int) -> String {
        guard value.isFinite else { return "" }
        let digits = min(max(maxDecimals, 0), 9)
        let minimum = min(max(minDecimals, 0), digits)
        var factor: UInt64 = 1
        for _ in 0..<digits { factor *= 10 }

        let scaled = (value.magnitude * Double(factor)).rounded()
        guard scaled < 9.0e18 else { return "" }
        let whole = UInt64(scaled)
        let integerPart = whole / factor

        var fraction = ""
        if digits > 0 {
            fraction = String(whole % factor)
            while fraction.count < digits { fraction = "0" + fraction }
            while fraction.count > minimum && fraction.hasSuffix("0") { fraction.removeLast() }
        }
        let sign = (value < 0 && whole > 0) ? "-" : ""
        return fraction.isEmpty ? sign + String(integerPart) : sign + String(integerPart) + "," + fraction
    }

    /// "2026-10-08"
    static func dateText(_ date: Date, timeZone: TimeZone = TimeZone.current) -> String {
        BackupService.dateStamp(date, timeZone: timeZone)
    }

    private static func row(_ cells: [String]) -> String {
        cells.joined(separator: delimiter) + "\n"
    }

    // MARK: Maandcijfers

    /// Eén regel per maand. Maanden na `current` zijn verwacht (Verwacht = ja).
    static func monthlyCSV(_ data: FinanceData, from start: YearMonth, count: Int, current: YearMonth) -> String {
        var out = row(["Maand", "Inkomen", "Uitgaven vast", "Uitgaven variabel", "Gespaard", "Belegd", "Over", "Verwacht ja/nee"])
        for month in start.range(count: count) {
            let overview = data.expenseOverview(in: month)
            let left = data.remaining(in: month)
            let expected = month > current ? "ja" : "nee"
            let cells: [String] = [
                month.key,
                number(overview.income),
                number(overview.fixed),
                number(overview.variable),
                number(overview.toPots),
                number(overview.toInvestments),
                number(left),
                expected
            ]
            out += row(cells)
        }
        return out
    }

    /// Standaardbereik voor de export: vanaf de startmaand tot een jaar vooruit (maximaal 50 jaar).
    static func defaultMonthRange(_ data: FinanceData, current: YearMonth) -> (from: YearMonth, count: Int) {
        let end = current.adding(12)
        var start = data.startMonth < current ? data.startMonth : current
        var count = start.months(to: end) + 1
        if count > 600 {
            start = end.adding(-599)
            count = 600
        }
        return (from: start, count: count)
    }

    // MARK: Transacties

    /// Alle boekingen op spaarpotten en op de bankrekening, oudste eerst. Een overboeking tussen bank en
    /// spaarpot staat er twee keer in: één keer bij elke kant.
    static func transactionsCSV(_ data: FinanceData, timeZone: TimeZone = TimeZone.current) -> String {
        struct Line {
            var date: Date
            var order: Int
            var cells: [String]
        }
        var lines: [Line] = []
        var order = 0

        for entry in data.potEntries {
            let potName = data.pot(entry.potID)?.name ?? "Onbekende spaarpot"
            let cells: [String] = [
                dateText(entry.date, timeZone: timeZone),
                text(entry.kind.title),
                text(potName),
                text(entry.note),
                number(entry.amount)
            ]
            lines.append(Line(date: entry.date, order: order, cells: cells))
            order += 1
        }
        for entry in data.bankEntries {
            let cells: [String] = [
                dateText(entry.date, timeZone: timeZone),
                text(entry.kind.title),
                text("Bankrekening"),
                text(entry.note),
                number(entry.amount)
            ]
            lines.append(Line(date: entry.date, order: order, cells: cells))
            order += 1
        }

        lines.sort { first, second in
            if first.date != second.date { return first.date < second.date }
            return first.order < second.order
        }

        var out = row(["Datum", "Soort", "Rekening of pot", "Omschrijving", "Bedrag"])
        for line in lines { out += row(line.cells) }
        return out
    }

    // MARK: Beleggingen

    /// Eén regel per belegging met de waarde van nu. Rendement als percentage; leeg zolang er niets is ingelegd.
    static func holdingsCSV(_ data: FinanceData, current: YearMonth) -> String {
        var out = row(["Naam", "Soort", "Ticker", "Aantal", "Koers", "Waarde", "Ingelegd", "Rendement"])
        for holding in data.holdings {
            let state = data.holdingStateNow(holding, current: current)
            let value = state?.value ?? 0
            let invested = state?.invested ?? holding.investedTotal

            var gain = ""
            if let fraction = state?.gainFraction { gain = percent(fraction) }

            var unitsText = ""
            if let units = holding.units { unitsText = decimal(units, maxDecimals: 8, minDecimals: 0) }
            var priceText = ""
            if let price = holding.lastPrice { priceText = decimal(price, maxDecimals: 4, minDecimals: 2) }
            let ticker = (holding.ticker ?? "").trimmingCharacters(in: .whitespaces)

            let cells: [String] = [
                text(holding.name),
                text(holding.kind.title),
                text(ticker),
                unitsText,
                priceText,
                number(value),
                number(invested),
                gain
            ]
            out += row(cells)
        }
        return out
    }

    // MARK: Bestand

    /// De CSV als bytes met een UTF-8 BOM voorop, zodat Excel de tekens (zoals €) goed leest.
    static func csvData(_ csv: String) -> Data {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))
        return data
    }
}
