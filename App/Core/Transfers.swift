import Foundation

// MARK: - Extra overschrijfdata (D2)
//
// De inleg van een spaarpot of belegging in een maand is één bedrag (`allocationCents`: een vast bedrag, of een percentage plus
// een extra bedrag). Standaard gaat dat bedrag in één keer over op de overschrijfdag (`transferDay(for:in:)`). Met extra
// overschrijfdata gaan DELEN van dat bedrag op een eigen dag over:
//
//   - een deel is een dag (1...31; in een korte maand de laatste dag) en een vast bedrag;
//   - wat na de delen overblijft gaat op de overschrijfdag (nooit negatief: zijn de delen samen meer dan de inleg, dan worden de
//     laatste delen afgekapt, het totaal van de maand blijft de inleg);
//   - delen op dezelfde dag (ook op de overschrijfdag zelf) vallen samen in één overschrijving;
//   - delen horen bij de standaard van de pot of belegging (`extraTransfers`) of bij één maand (`MonthPlan.transferParts`, dat de
//     standaard vervangt, ook met een lege lijst);
//   - een deel telt pas vanaf het begin van zijn dag: voor die dag is er niets overgeschreven (net als de overschrijfdag zelf);
//   - met een startdatum telt een deel dat vóór de startdag valt niet mee (`counts(day:in:)`), de rest wel.
//
// Eén bron: `TransferMath.slices` levert de stukken; de gebeurtenissen van de dagen (`planEvents`), de saldi en de geschiedenis van
// de spaarpotten (`potLedgers`, `potTimeline`), de waarde van beleggingen (`Invest.swift`) en het bedrag dat meetelt in de startmaand
// (`countedTransferCents`) lezen allemaal daaruit.

/// Een deel van de maandinleg dat op een eigen dag wordt overgeschreven.
struct TransferPart: Codable, Equatable, Hashable, Identifiable {
    /// Dag van de maand (1...31; een korte maand gebruikt zijn laatste dag).
    var day: Int
    /// Bedrag in euro's.
    var amount: Double

    var id: Int { day }

    init(day: Int, amount: Double) {
        self.day = day
        self.amount = amount
    }

    enum CodingKeys: String, CodingKey { case day, amount }

    /// Een ontbrekende dag is de 1e en een ontbrekend bedrag 0 (dat valt bij het bewaren weg). Een dag of bedrag dat er wel staat maar
    /// geen getal is, maakt het deel onleesbaar: een lijst met zo'n deel slaat het over (`KeyedDecodingContainer.decodeTransferParts`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = YearMonth.clampedDay(try c.decodeIfPresent(Int.self, forKey: .day) ?? 1)
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(day, forKey: .day)
        try c.encode(AllocationMath.cleanExtra(amount), forKey: .amount)
    }
}

/// Een deel dat bij het lezen mag mislukken: een lijst met een onleesbaar deel houdt de andere delen.
struct LossyTransferPart: Decodable {
    let value: TransferPart?

    init(from decoder: Decoder) throws {
        value = try? TransferPart(from: decoder)
    }
}

/// De lijst delen van één pot of belegging in een maand, mild gelezen: `parts` is nil als de waarde geen lijst is.
struct LossyTransferParts: Decodable {
    let parts: [TransferPart]?

    init(from decoder: Decoder) throws {
        if let boxes = try? [LossyTransferPart](from: decoder) {
            parts = boxes.compactMap { $0.value }
        } else {
            parts = nil
        }
    }
}

extension KeyedDecodingContainer {
    /// Een lijst delen, mild gelezen: ontbreekt ze of is ze geen lijst, dan is ze leeg; een deel dat niet te lezen is wordt
    /// overgeslagen, de rest blijft (`Pot`, `Holding`).
    func decodeTransferParts(forKey key: Key) -> [TransferPart] {
        let boxes = (try? decodeIfPresent([LossyTransferPart].self, forKey: key)) ?? nil
        return (boxes ?? []).compactMap { $0.value }
    }

    /// De delen per pot of belegging van een maand, mild gelezen (`MonthPlan.transferParts`): per lijst als hierboven; een sleutel waarvan
    /// de waarde geen lijst is wordt overgeslagen (de maand volgt dan de standaard van die pot), de andere sleutels blijven.
    func decodeTransferPartsByID(forKey key: Key) -> [String: [TransferPart]] {
        let boxes = (try? decodeIfPresent([String: LossyTransferParts].self, forKey: key)) ?? nil
        var result: [String: [TransferPart]] = [:]
        for (id, box) in boxes ?? [:] {
            if let parts = box.parts { result[id] = parts }
        }
        return result
    }
}

/// Eén overschrijving op één dag: een deel van de inleg, of de rest.
struct TransferSlice: Equatable {
    /// Dag van de maand (1...dagen in de maand).
    var day: Int
    var cents: Int
    /// Dit is de overschrijving op de overschrijfdag zelf (de rest, met eventuele delen op diezelfde dag). Haar gebeurtenis houdt
    /// het id van altijd; de andere krijgen de dag erachter.
    var isStandard: Bool
}

enum TransferMath {
    /// Zoveel extra overschrijfdata per pot of belegging (genoeg voor elke week, en nooit een onbegrensde lijst).
    static let maxParts = 12

    /// De delen zoals ze worden bewaard: dagen op 1...31, bedragen op hele centen, delen van nul of minder weg, op dag gesorteerd,
    /// dezelfde dag samengevoegd, hoogstens `maxParts`.
    static func normalized(_ parts: [TransferPart]) -> [TransferPart] {
        var byDay: [Int: Int] = [:]
        for part in parts {
            let cents = AllocationMath.extraCents(part.amount)
            guard cents > 0 else { continue }
            let day = YearMonth.clampedDay(part.day)
            byDay[day] = CentsMath.add(byDay[day] ?? 0, cents)
        }
        return byDay.keys.sorted().prefix(maxParts).map { TransferPart(day: $0, amount: CentsMath.value(byDay[$0] ?? 0)) }
    }

    /// De overschrijvingen van een inleg van `totalCents` in `month`, oplopend op dag, samen precies `totalCents`.
    /// - Een inleg van nul of minder (minder: geld terug naar de rekening) heeft geen delen: alles op `standardDay`.
    /// - De delen worden op volgorde van dag afgekapt zodat ze samen niet meer zijn dan de inleg; de rest gaat op `standardDay`.
    /// - Een dag na het einde van de maand is de laatste dag; stukken op dezelfde dag vallen samen.
    static func slices(totalCents: Int, parts: [TransferPart], standardDay: Int, month: YearMonth) -> [TransferSlice] {
        let standard = min(max(standardDay, 1), month.dayCount)
        if totalCents == 0 { return [] }
        if totalCents < 0 || parts.isEmpty { return [TransferSlice(day: standard, cents: totalCents, isStandard: true)] }
        var left = totalCents
        var byDay: [Int: Int] = [:]
        for part in normalized(parts) {
            let wanted = AllocationMath.extraCents(part.amount)
            let take = min(wanted, left)
            guard take > 0 else { continue }
            let day = min(part.day, month.dayCount)
            byDay[day] = CentsMath.add(byDay[day] ?? 0, take)
            left -= take
        }
        byDay[standard] = CentsMath.add(byDay[standard] ?? 0, left)
        return byDay.keys.sorted().compactMap { day in
            let cents = byDay[day] ?? 0
            return cents == 0 ? nil : TransferSlice(day: day, cents: cents, isStandard: day == standard)
        }
    }

    /// Hoeveel van de delen wordt afgekapt omdat ze samen meer zijn dan de inleg (0 als alles past). Voor de waarschuwing in de UI.
    static func overflowCents(totalCents: Int, parts: [TransferPart]) -> Int {
        guard totalCents > 0 else { return CentsMath.sum(normalized(parts).map { AllocationMath.extraCents($0.amount) }) }
        let wanted = CentsMath.sum(normalized(parts).map { AllocationMath.extraCents($0.amount) })
        return max(0, wanted - totalCents)
    }
}

extension FinanceData {
    // MARK: Welke delen gelden

    /// De standaarddelen van een pot of belegging (leeg als het id onbekend is).
    func standardTransferParts(of id: UUID) -> [TransferPart] {
        if let pot = pots.first(where: { $0.id == id }) { return pot.extraTransfers }
        return holdings.first(where: { $0.id == id })?.extraTransfers ?? []
    }

    /// De delen die voor `id` in `month` gelden: die van de maand als de maand ze heeft (ook een lege lijst), anders de standaard.
    func transferParts(for id: UUID, in month: YearMonth) -> [TransferPart] {
        months[month.key]?.transferParts[id.uuidString] ?? standardTransferParts(of: id)
    }

    /// Heeft de maand eigen delen voor `id` die van de standaard verschillen? Een lege lijst terwijl de standaard delen heeft is een
    /// afwijking (deze maand alles op de overschrijfdag). Een bewaarde lijst die gelijk is aan de standaard (een maand die de oude
    /// standaard kreeg vastgelegd, `freezePastTransferParts`) is geen afwijking.
    func hasTransferPartsOverride(_ id: UUID, in month: YearMonth) -> Bool {
        guard let own = months[month.key]?.transferParts[id.uuidString] else { return false }
        return TransferMath.normalized(own) != TransferMath.normalized(standardTransferParts(of: id))
    }

    /// De overschrijvingen van de inleg van `id` in `month` voor een inleg van `totalCents` (zie `TransferMath.slices`), zonder
    /// rekening te houden met de startdatum.
    func transferSlices(for id: UUID, in month: YearMonth, totalCents: Int) -> [TransferSlice] {
        TransferMath.slices(totalCents: totalCents, parts: transferParts(for: id, in: month),
                            standardDay: transferDay(for: id, in: month), month: month)
    }

    /// De overschrijvingen van de inleg van `id` in `month` zoals de verdeling van die maand ze nu geeft (de regel van de maand,
    /// zonder rekening te houden met de startdatum). Voor de weergave op Verdelen en in de bladen.
    func transferSlices(for id: UUID, in month: YearMonth) -> [TransferSlice] {
        transferSlices(for: id, in: month, totalCents: rawCents(of: allocationRule(id, in: month), in: month))
    }

    /// De overschrijvingen van `id` in `month` die vóór de startdag vallen en dus niet meetellen. Leeg in een gewone maand.
    func uncountedTransferSlices(for id: UUID, in month: YearMonth) -> [TransferSlice] {
        let first = firstCountedDay(in: month)
        guard first > 1, month >= startMonth, id != BankShare.id else { return [] }
        return transferSlices(for: id, in: month).filter { $0.day < first }
    }

    /// Het deel van `totalCents` dat meetelt: in een gewone maand alles; in de startmaand alleen de overschrijvingen op of na de
    /// startdag. `parts` zijn de delen die voor deze maand gelden.
    func countedTransferCents(_ totalCents: Int, id: UUID, in month: YearMonth, parts: [TransferPart]) -> Int {
        let first = firstCountedDay(in: month)
        // De bankrekening is een toewijzing zonder overschrijving en dus zonder dag: ze telt in elke maand vanaf de startmaand.
        if first <= 1 || totalCents == 0 || id == BankShare.id { return totalCents }
        let slices = TransferMath.slices(totalCents: totalCents, parts: parts, standardDay: transferDay(for: id, in: month), month: month)
        return CentsMath.sum(slices.filter { $0.day >= first }.map { $0.cents })
    }

    /// De id van de gebeurtenis van een overschrijving: die van de overschrijfdag houdt het id van altijd, een deel krijgt de dag erachter.
    static func transferEventID(prefix: String, id: UUID, month: YearMonth, slice: TransferSlice) -> String {
        let base = "\(prefix)-\(id.uuidString)-\(month.key)"
        return slice.isStandard ? base : base + "-" + (slice.day < 10 ? "0" : "") + "\(slice.day)"
    }

    // MARK: Wijzigen

    /// Zet de extra overschrijfdata van ÉÉN maand voor een pot of belegging (vervangt de standaard voor die maand; een lege lijst
    /// betekent: deze maand alles op de overschrijfdag). Is de lijst gelijk aan de standaard, dan wordt er geen afwijking bewaard:
    /// de maand volgt de standaard, ook als die later verandert.
    mutating func setTransferParts(_ id: UUID, in month: YearMonth, parts: [TransferPart]) {
        let clean = TransferMath.normalized(parts)
        if clean == TransferMath.normalized(standardTransferParts(of: id)) {
            clearTransferParts(id, in: month)
            return
        }
        editPlan(month) { $0.transferParts[id.uuidString] = clean }
    }

    /// Haalt de eigen delen van een maand weg (ook een bewaarde lijst die gelijk is aan de standaard): de standaard van de pot of
    /// belegging geldt weer.
    mutating func clearTransferParts(_ id: UUID, in month: YearMonth) {
        guard months[month.key]?.transferParts[id.uuidString] != nil else { return }
        editPlan(month) { _ = $0.transferParts.removeValue(forKey: id.uuidString) }
    }

    /// Zet de standaarddelen van een pot of belegging. De maanden vóór `current` houden hun delen: wat de standaard tot nu toe
    /// was wordt in die maanden vastgelegd (alleen in al opgeslagen maanden zonder eigen delen), zodat het verleden niet
    /// verandert. De lopende en de komende maanden volgen de nieuwe standaard (behalve maanden met eigen delen).
    mutating func setStandardTransferParts(_ id: UUID, parts: [TransferPart], current: YearMonth) {
        let clean = TransferMath.normalized(parts)
        let old = TransferMath.normalized(standardTransferParts(of: id))
        guard old != clean else { return }
        let start = pot(id)?.startMonth ?? holding(id)?.startMonth ?? startMonth
        freezePastTransferParts(id, parts: old, start: start, before: current)
        if let i = pots.firstIndex(where: { $0.id == id }) {
            pots[i].extraTransfers = clean
        } else if let i = holdings.firstIndex(where: { $0.id == id }) {
            holdings[i].extraTransfers = clean
        }
    }

    /// Legt in al opgeslagen maanden van `start` tot `current` zonder eigen delen de delen `parts` vast.
    mutating func freezePastTransferParts(_ id: UUID, parts: [TransferPart], start: YearMonth, before current: YearMonth) {
        let key = id.uuidString
        for monthKey in Array(months.keys) {
            guard let m = YearMonth(key: monthKey), m < current, m >= start, months[monthKey]?.transferParts[key] == nil else { continue }
            months[monthKey]?.transferParts[key] = parts
        }
    }
}
