import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in
// RecentActivityTests.swift. `TilePalette.swift` (TileHue) en `NavigationModel.swift` (Destination) staan er ook als symlink.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

// MARK: - Eén regel van Recent

/// Eén recente boeking voor de groep Recent van de Bibliotheek: het onderwerp (de bankrekening of een spaarpot) als titel,
/// wat er gebeurde met de datum als ondertitel en het bedrag met teken vanuit dat onderwerp (positief = erbij, negatief = eraf).
/// Een overboeking staat er eenmaal, vanuit de spaarpot (bij pot naar pot vanuit de pot die het geld gaf).
struct RecentItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let date: Date
    let amount: Double
    let hue: TileHue
    /// Waar een tik heen gaat: de spaarpot of de bankrekening.
    let destination: Destination
}

// MARK: - De laatste handmatige boekingen

/// Recent (B18 van docs/design2/plan.md): de laatste handmatige boekingen op de bankrekening en in spaarpotten, de nieuwste
/// eerst. Er wordt niets bewaard en niets uitgerekend: de lijst komt uit `bankEntries` en `potEntries`. Een beginsaldo
/// (`.opening`) is geen boeking van jou en de rente die de app zelf bijschrijft (`.interest`) evenmin. Een boeking na `asOf`
/// (gepland) staat er nog niet in. Een overboeking bestaat uit twee helften met hetzelfde `pairID`; die staat er eenmaal.
enum RecentActivity {
    static let bankSymbol = "building.columns"

    /// De laatste `limit` boekingen tot en met het moment `asOf` (meestal `store.today`), de nieuwste eerst; bij dezelfde
    /// datum staat de boeking die later is toegevoegd bovenaan.
    static func items(in data: FinanceData, asOf: Date, limit: Int = 5) -> [RecentItem] {
        guard limit > 0 else { return [] }
        let context = RecentContext(data: data)
        var events: [RecentEvent] = []
        events.append(contentsOf: bankEvents(in: data, asOf: asOf, context: context))
        events.append(contentsOf: potEvents(in: data, asOf: asOf, context: context))
        events.sort { lhs, rhs in
            if lhs.item.date != rhs.item.date { return lhs.item.date > rhs.item.date }
            if lhs.order != rhs.order { return lhs.order > rhs.order }
            return lhs.item.id < rhs.item.id
        }
        var result: [RecentItem] = []
        for event in events.prefix(limit) {
            result.append(event.item)
        }
        return result
    }

    // MARK: Bankboekingen

    /// De boekingen op de bankrekening. Een overboeking met een spaarpot staat er niet: die komt van de potkant.
    private static func bankEvents(in data: FinanceData, asOf: Date, context: RecentContext) -> [RecentEvent] {
        var events: [RecentEvent] = []
        for (index, entry) in data.bankEntries.enumerated() {
            guard entry.date <= asOf else { continue }
            if let pair = entry.pairID, context.hasPotHalf(pair) { continue }
            let subtitle = joined([entry.kind.title, entry.note, Fmt.date(entry.date)])
            let item = RecentItem(id: "bank-" + entry.id.uuidString, title: "Bankrekening", subtitle: subtitle,
                                  symbol: bankSymbol, date: entry.date, amount: entry.amount, hue: .terracotta,
                                  destination: .bank)
            events.append(RecentEvent(item: item, order: index))
        }
        return events
    }

    // MARK: Potboekingen

    /// De boekingen in spaarpotten, zonder beginsaldo en rente. Van een overboeking telt één helft.
    private static func potEvents(in data: FinanceData, asOf: Date, context: RecentContext) -> [RecentEvent] {
        var events: [RecentEvent] = []
        for (index, entry) in data.potEntries.enumerated() {
            guard entry.date <= asOf, entry.kind != .opening, entry.kind != .interest else { continue }
            guard let pot = context.pots[entry.potID] else { continue }
            if let item = potItem(entry, pot: pot, context: context) {
                events.append(RecentEvent(item: item, order: index))
            }
        }
        return events
    }

    /// De regel voor een potboeking; nil als de boeking de tweede helft van een overboeking is die er al staat.
    private static func potItem(_ entry: PotEntry, pot: Pot, context: RecentContext) -> RecentItem? {
        var id = "pot-" + entry.id.uuidString
        var subtitle = joined([entry.kind.title, entry.note, Fmt.date(entry.date)])
        if let pair = entry.pairID {
            let halves: [PotEntry] = context.potHalves[pair] ?? []
            if halves.count > 1 && context.shownHalf(of: halves).id != entry.id { return nil }
            if let other = context.otherHalf(of: entry, pair: pair) {
                id = "transfer-" + pair.uuidString
                subtitle = joined([transferText(entry, partner: other), Fmt.date(entry.date)])
            } else if context.bankHalves[pair] != nil {
                id = "transfer-" + pair.uuidString
                let text = entry.amount < 0 ? "Naar bankrekening" : "Van bankrekening"
                subtitle = joined([text, Fmt.date(entry.date)])
            }
        }
        let symbol = pot.symbol.isEmpty ? "banknote" : pot.symbol
        return RecentItem(id: id, title: pot.name, subtitle: subtitle, symbol: symbol, date: entry.date,
                          amount: entry.amount, hue: TileHue.forIndex(pot.colorIndex), destination: .pot(pot.id))
    }

    /// "Naar Buffer" of "Van Vakantie": de andere pot bij een overboeking tussen twee potten.
    private static func transferText(_ entry: PotEntry, partner: RecentPartner) -> String {
        entry.amount < 0 ? "Naar " + partner.name : "Van " + partner.name
    }

    // MARK: Tekst

    /// De delen achter elkaar, gescheiden door een middenpunt; lege delen vallen weg.
    private static func joined(_ parts: [String]) -> String {
        var texts: [String] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { texts.append(trimmed) }
        }
        return texts.joined(separator: " · ")
    }
}

// MARK: - Hulptypen

/// Een regel met zijn plek in de lijst waar hij uit komt: bij dezelfde datum staat wat later is toegevoegd bovenaan.
private struct RecentEvent {
    let item: RecentItem
    let order: Int
}

/// De andere kant van een overboeking tussen twee potten.
private struct RecentPartner {
    let name: String
}

/// De potten en de helften van overboekingen (per `pairID`), eenmaal opgebouwd voor een hele lijst.
private struct RecentContext {
    var pots: [UUID: Pot] = [:]
    /// De potkant van elke overboeking (zonder beginsaldo), met een bekende pot.
    var potHalves: [UUID: [PotEntry]] = [:]
    /// De bankkant van elke overboeking.
    var bankHalves: [UUID: BankEntry] = [:]

    init(data: FinanceData) {
        for pot in data.pots {
            pots[pot.id] = pot
        }
        for entry in data.potEntries where entry.kind != .opening {
            guard let pair = entry.pairID, pots[entry.potID] != nil else { continue }
            var halves: [PotEntry] = potHalves[pair] ?? []
            halves.append(entry)
            potHalves[pair] = halves
        }
        for entry in data.bankEntries {
            if let pair = entry.pairID {
                bankHalves[pair] = entry
            }
        }
    }

    /// Heeft de overboeking een potkant? Dan toont de lijst haar vanuit de pot.
    func hasPotHalf(_ pair: UUID) -> Bool {
        guard let halves = potHalves[pair] else { return false }
        return !halves.isEmpty
    }

    /// De helft die de overboeking toont: de pot die het geld gaf (negatief bedrag), anders de eerste.
    func shownHalf(of halves: [PotEntry]) -> PotEntry {
        for half in halves where half.amount < 0 {
            return half
        }
        return halves[0]
    }

    /// De andere pot bij een overboeking tussen twee potten; nil bij een overboeking met de bank of zonder partner.
    func otherHalf(of entry: PotEntry, pair: UUID) -> RecentPartner? {
        guard let halves = potHalves[pair] else { return nil }
        for half in halves where half.id != entry.id {
            let name: String = pots[half.potID]?.name ?? "andere pot"
            return RecentPartner(name: name)
        }
        return nil
    }
}
