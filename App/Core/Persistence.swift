import Foundation

/// Slaat alle gegevens op als één JSON-bestand in Application Support.
struct FinanceStorage {
    let url: URL

    enum LoadResult {
        case empty
        case loaded(FinanceData)
        /// Het bestand bestond maar was onleesbaar. Het is veiliggesteld op `backup`.
        case corrupt(backup: URL?)
    }

    static func standard() -> FinanceStorage {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("MyBuddy", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return FinanceStorage(url: dir.appendingPathComponent("finance.json"))
    }

    /// De opgemaakte codering: leesbaar en met vaste volgorde van sleutels. Gebruikt voor de cloud (zie
    /// `FirebaseDatabaseClient`, `CloudSync`), de back-up (`Export`) en het vergelijken van gegevens. Die moeten
    /// precies hetzelfde blijven, dus pas deze uitvoer niet aan; het lokale bestand gebruikt `makeFileEncoder()`.
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    /// De codering van het lokale bestand: compact (zonder opmaak, veel sneller en kleiner), met vaste volgorde van
    /// sleutels. Elke wijziging schrijft het bestand opnieuw, dus de kosten tellen. Lezen kan beide vormen.
    static func makeFileEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Leest het bestand, compact of opgemaakt (oudere versies schreven het opgemaakt).
    func load() -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .empty }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try Self.makeDecoder().decode(FinanceData.self, from: data))
        } catch {
            // Nooit stilletjes overschrijven: bewaar het onleesbare bestand.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent().appendingPathComponent("finance.corrupt-\(stamp).json")
            do {
                try fm.moveItem(at: url, to: backup)
                return .corrupt(backup: backup)
            } catch {
                return .corrupt(backup: nil)
            }
        }
    }

    func save(_ data: FinanceData) throws {
        let encoded = try Self.makeFileEncoder().encode(data)
        try encoded.write(to: url, options: .atomic)
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
