import Foundation

// MARK: - Een dienst uit de agenda
//
// Een dienst is alleen een begin en een einde, op de minuut. Nooit een titel, notitie, plaats of deelnemer: de agenda is privé en
// de afgeleide diensten gaan mee in de back-up en de synchronisatie (docs/work/plan.md B10). Foundation-only: de agenda zelf wordt
// gelezen door `EventKitWorkCalendar` (App/Calendar), dat alleen begin en einde doorgeeft.

struct WorkShift: Hashable, Comparable, Codable, Sendable {
    /// Minuten sinds 1970-01-01 00:00 UTC (een moment, onafhankelijk van tijdzone).
    let startMinute: Int
    let endMinute: Int

    /// nil als het einde niet na het begin ligt.
    init?(startMinute: Int, endMinute: Int) {
        guard endMinute > startMinute else { return nil }
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    /// Op de minuut naar beneden afgekapt; nil als het einde niet na het begin ligt.
    init?(start: Date, end: Date) {
        self.init(startMinute: WorkShift.minute(of: start), endMinute: WorkShift.minute(of: end))
    }

    /// De minuut (sinds 1970) waarin `date` valt, naar beneden afgekapt. Een datum buiten het bereik van een `Int` wordt begrensd.
    static func minute(of date: Date) -> Int {
        let minutes = (date.timeIntervalSince1970 / 60).rounded(.down)
        guard minutes.isFinite else { return 0 }
        return Int(min(max(minutes, -1e12), 1e12))
    }

    var start: Date { Date(timeIntervalSince1970: Double(startMinute) * 60) }
    var end: Date { Date(timeIntervalSince1970: Double(endMinute) * 60) }
    var durationMinutes: Int { endMinute - startMinute }

    static func < (a: WorkShift, b: WorkShift) -> Bool {
        a.startMinute != b.startMinute ? a.startMinute < b.startMinute : a.endMinute < b.endMinute
    }

    // Opgeslagen als [begin, einde]: compact (een jaar diensten is een paar tientallen kB) en zonder tekst.
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let s = try c.decode(Int.self)
        let e = try c.decode(Int.self)
        guard let shift = WorkShift(startMinute: s, endMinute: e) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Een dienst eindigt niet na zijn begin")
        }
        self = shift
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(startMinute)
        try c.encode(endMinute)
    }
}

extension WorkShift {
    /// Gesorteerd, zonder dubbelen en zonder overlap: overlappende diensten worden één dienst (je werkt niet dubbel). Diensten die
    /// elkaar alleen raken (het einde van de ene is het begin van de volgende) blijven twee diensten.
    static func normalized(_ shifts: [WorkShift]) -> [WorkShift] {
        var result: [WorkShift] = []
        for shift in shifts.sorted() {
            if let last = result.last, shift.startMinute < last.endMinute {
                if shift.endMinute > last.endMinute, let merged = WorkShift(startMinute: last.startMinute, endMinute: shift.endMinute) {
                    result[result.count - 1] = merged
                }
            } else {
                result.append(shift)
            }
        }
        return result
    }

    /// Het deel van een dienst op één kalenderdag.
    struct Piece: Equatable {
        var day: CalendarDay
        var minutes: Int
    }

    /// De stukken per kalenderdag van `calendar`. Een dag kan door de zomertijd 23 of 25 uur duren: de grenzen komen uit `Calendar`
    /// (`startOfDay`, `date(byAdding: .day)`), nooit uit 86 400 seconden, en er tellen verstreken minuten. Za 22:00 tot zo 06:00 bij
    /// het einde van de zomertijd is zo 9 uur (120 + 420 minuten). De minuten tellen op tot `durationMinutes`.
    func pieces(calendar: Calendar) -> [Piece] {
        var result: [Piece] = []
        var cursor = start
        let finish = end
        var guardCount = 0
        while cursor < finish && guardCount < 40 {
            let dayStart = calendar.startOfDay(for: cursor)
            let next = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
            let pieceEnd = min(finish, next)
            let minutes = Int((pieceEnd.timeIntervalSince(cursor) / 60).rounded())
            if minutes > 0 { result.append(Piece(day: CalendarDay(date: cursor, calendar: calendar), minutes: minutes)) }
            cursor = pieceEnd
            guardCount += 1
        }
        return result
    }
}

enum WorkMath {
    /// Verdeelt `total` (hele minuten) evenredig over `parts` (grootste rest; bij gelijke rest eerst het vroegste deel). De delen
    /// tellen altijd precies op tot `total` (of zijn allemaal 0 als er niets te verdelen valt).
    static func distribute(_ total: Int, over parts: [Int]) -> [Int] {
        let sum = parts.reduce(0, +)
        guard total > 0, sum > 0 else { return parts.map { _ in 0 } }
        var shares = parts.map { total * $0 / sum }
        var left = total - shares.reduce(0, +)
        let order = parts.indices.sorted { a, b in
            let ra = total * parts[a] % sum, rb = total * parts[b] % sum
            return ra != rb ? ra > rb : a < b
        }
        for index in order where left > 0 {
            shares[index] += 1
            left -= 1
        }
        return shares
    }
}

/// Een array die onleesbare elementen overslaat in plaats van het hele bestand te laten mislukken.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var list: [Element] = []
        while !c.isAtEnd {
            if let element = try? c.decode(Element.self) {
                list.append(element)
            } else {
                _ = try? c.decode(Skip.self)
            }
        }
        elements = list
    }
}
