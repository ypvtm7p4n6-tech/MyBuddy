import Foundation

// ZIP-lezer (en een eenvoudige schrijver) in zuiver Swift.
//
// Een .xlsx-bestand is een ZIP met XML-bestanden erin. We lezen de centrale directory en pakken de
// onderdelen uit (opgeslagen of ingepakt met DEFLATE). Bewust GEEN zlib of Compression: dan compileert
// dit ook op Linux (tests) en is er niets dat per platform verschilt.
//
// Veiligheid: elk onderdeel heeft een bovengrens, de uitkomst wordt gecontroleerd op lengte en
// controlesom (CRC-32) en een kapot bestand geeft een nette fout in plaats van een crash.

// MARK: - Fouten

enum ZipError: Error, Equatable, LocalizedError {
    /// Geen ZIP-bestand (geen eindrecord gevonden).
    case notAZip
    /// Wel een ZIP, maar de inhoud klopt niet.
    case corrupt(String)
    /// Een onderdeel is met een wachtwoord beveiligd.
    case encrypted
    /// Een inpakmethode die we niet kennen.
    case unsupportedMethod(Int)
    /// Een onderdeel is groter dan we willen uitpakken.
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .notAZip:
            return "Dit is geen geldig ZIP-bestand."
        case .corrupt(let detail):
            return "Het bestand is beschadigd (\(detail))."
        case .encrypted:
            return "Het bestand is met een wachtwoord beveiligd."
        case .unsupportedMethod(let method):
            return "Het bestand gebruikt een inpakmethode die niet wordt ondersteund (\(method))."
        case .tooLarge:
            return "Het bestand is te groot om te lezen."
        }
    }
}

// MARK: - CRC-32

enum CRC32 {
    private static let table: [UInt32] = {
        var result = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            result[i] = c
        }
        return result
    }()

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        // Met wijzers en een lokale tabel: ook in een debugbouw (de tests) snel genoeg voor tientallen megabytes.
        bytes.withUnsafeBufferPointer { data in
            table.withUnsafeBufferPointer { lookup in
                var i = 0
                let count = data.count
                while i < count {
                    crc = lookup[Int((crc ^ UInt32(data[i])) & 0xFF)] ^ (crc >> 8)
                    i += 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - DEFLATE (RFC 1951)

/// Pakt een ruwe DEFLATE-stroom uit: opgeslagen blokken, vaste en dynamische Huffman-codes.
enum Inflate {
    /// Standaard bovengrens voor één uitgepakt onderdeel.
    static let defaultLimit = 120 * 1024 * 1024

    private static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                                            35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                                             3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                                              257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                                              8193, 12289, 16385, 24577]
    private static let distanceExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                                               7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    /// Volgorde waarin de lengtes van de codelengte-code staan in een dynamisch blok.
    private static let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    /// Pakt `input[start..<end]` uit. `expectedSize` is een hint voor de uitvoerbuffer (mag 0 zijn);
    /// `limit` is de grootste toegestane uitvoer.
    static func inflate(_ input: [UInt8], start: Int = 0, end: Int? = nil,
                        expectedSize: Int = 0, limit: Int = defaultLimit) throws -> [UInt8] {
        let last = min(end ?? input.count, input.count)
        guard start >= 0, start <= last else { throw ZipError.corrupt("ongeldig bereik") }

        var reader = BitReader(input: input, pos: start, end: last)
        var out = OutputBuffer(limit: limit, hint: min(max(expectedSize, 0), (last - start) * 16 + 65_536))

        var isFinal = false
        while !isFinal {
            isFinal = try reader.bits(1) == 1
            let type = try reader.bits(2)
            switch type {
            case 0:
                try storedBlock(&reader, &out)
            case 1:
                try codedBlock(&reader, &out, literals: FixedTables.literals, distances: FixedTables.distances)
            case 2:
                let tables = try dynamicTables(&reader)
                try codedBlock(&reader, &out, literals: tables.literals, distances: tables.distances)
            default:
                throw ZipError.corrupt("ongeldig blok")
            }
        }
        return out.finish()
    }

    // MARK: Bits lezen

    private struct BitReader {
        let input: [UInt8]
        var pos: Int
        let end: Int
        var buffer: UInt64 = 0
        var count = 0

        init(input: [UInt8], pos: Int, end: Int) {
            self.input = input
            self.pos = pos
            self.end = end
        }

        mutating func refill() {
            while count <= 56 && pos < end {
                buffer |= UInt64(input[pos]) << UInt64(count)
                pos += 1
                count += 8
            }
        }

        mutating func bits(_ n: Int) throws -> Int {
            if n == 0 { return 0 }
            if count < n {
                refill()
                if count < n { throw ZipError.corrupt("onverwacht einde van de gegevens") }
            }
            let value = Int(buffer & ((UInt64(1) << UInt64(n)) - 1))
            buffer >>= UInt64(n)
            count -= n
            return value
        }
    }

    // MARK: Uitvoer

    private struct OutputBuffer {
        var bytes: [UInt8]
        var count = 0
        let limit: Int

        init(limit: Int, hint: Int) {
            self.limit = limit
            bytes = [UInt8](repeating: 0, count: min(limit, max(hint, 1_024)))
        }

        mutating func reserve(_ extra: Int) throws {
            let needed = count + extra
            if needed > limit { throw ZipError.tooLarge }
            if needed > bytes.count {
                let grown = min(limit, max(needed, bytes.count * 2))
                bytes.append(contentsOf: repeatElement(0, count: grown - bytes.count))
            }
        }

        mutating func put(_ byte: UInt8) throws {
            if count >= bytes.count { try reserve(1) }
            bytes[count] = byte
            count += 1
        }

        mutating func copy(distance: Int, length: Int) throws {
            guard distance >= 1, distance <= count else { throw ZipError.corrupt("ongeldige afstand") }
            if count + length > bytes.count { try reserve(length) }
            var source = count - distance
            var target = count
            for _ in 0..<length {
                bytes[target] = bytes[source]
                target += 1
                source += 1
            }
            count = target
        }

        mutating func finish() -> [UInt8] {
            if count < bytes.count { bytes.removeLast(bytes.count - count) }
            return bytes
        }
    }

    // MARK: Huffman

    private struct Huffman {
        static let fastBits = 10
        static let fastMask = UInt64((1 << fastBits) - 1)

        /// Aantal codes per lengte (index 0 is ongebruikt).
        var counts = [UInt16](repeating: 0, count: 16)
        /// Symbolen gesorteerd op (lengte, symbool).
        var symbols: [UInt16]
        /// Opzoektabel voor korte codes: (lengte << 9) | symbool. 0 = niet gevonden.
        var fast = [UInt16](repeating: 0, count: 1 << fastBits)

        init(lengths: [UInt8]) throws {
            symbols = [UInt16](repeating: 0, count: lengths.count)
            for length in lengths { counts[Int(length)] += 1 }
            counts[0] = 0

            // Te veel codes voor de beschikbare ruimte kan niet.
            var left = 1
            for length in 1...15 {
                left <<= 1
                left -= Int(counts[length])
                if left < 0 { throw ZipError.corrupt("ongeldige Huffman-codes") }
            }

            var offsets = [Int](repeating: 0, count: 17)
            for length in 1...15 { offsets[length + 1] = offsets[length] + Int(counts[length]) }
            for (symbol, length) in lengths.enumerated() where length != 0 {
                symbols[offsets[Int(length)]] = UInt16(symbol)
                offsets[Int(length)] += 1
            }

            // Snelle tabel: codes zijn kanoniek (MSB eerst), bits worden LSB eerst gelezen, dus omkeren.
            var code = 0
            var index = 0
            for length in 1...Huffman.fastBits {
                for _ in 0..<Int(counts[length]) {
                    let symbol = symbols[index]
                    index += 1
                    var reversed = 0
                    var rest = code
                    for _ in 0..<length {
                        reversed = (reversed << 1) | (rest & 1)
                        rest >>= 1
                    }
                    let entry = UInt16(length << 9) | symbol
                    var slot = reversed
                    while slot < (1 << Huffman.fastBits) {
                        fast[slot] = entry
                        slot += 1 << length
                    }
                    code += 1
                }
                code <<= 1
            }
        }

        func decode(_ reader: inout BitReader) throws -> Int {
            if reader.count < 15 { reader.refill() }
            let entry = fast[Int(reader.buffer & Huffman.fastMask)]
            if entry != 0 {
                let length = Int(entry >> 9)
                if length > reader.count { throw ZipError.corrupt("onverwacht einde van de gegevens") }
                reader.buffer >>= UInt64(length)
                reader.count -= length
                return Int(entry & 0x1FF)
            }
            // Lange codes: bit voor bit door de kanonieke tabel.
            var code = 0
            var first = 0
            var index = 0
            var bits = reader.buffer
            for length in 1...15 {
                if length > reader.count { throw ZipError.corrupt("onverwacht einde van de gegevens") }
                code |= Int(bits & 1)
                bits >>= 1
                let count = Int(counts[length])
                if code - count < first {
                    reader.buffer >>= UInt64(length)
                    reader.count -= length
                    return Int(symbols[index + (code - first)])
                }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw ZipError.corrupt("ongeldige Huffman-code")
        }
    }

    private enum FixedTables {
        static let literals: Huffman = {
            var lengths = [UInt8](repeating: 8, count: 288)
            for i in 144..<256 { lengths[i] = 9 }
            for i in 256..<280 { lengths[i] = 7 }
            // De lengtes zijn vast en kloppen altijd.
            return try! Huffman(lengths: lengths)
        }()
        static let distances: Huffman = {
            try! Huffman(lengths: [UInt8](repeating: 5, count: 30))
        }()
    }

    // MARK: Blokken

    private static func storedBlock(_ reader: inout BitReader, _ out: inout OutputBuffer) throws {
        // Naar de volgende bytegrens en de ongebruikte bytes uit de bitbuffer teruggeven.
        let drop = reader.count % 8
        reader.buffer >>= UInt64(drop)
        reader.count -= drop
        reader.pos -= reader.count / 8
        reader.buffer = 0
        reader.count = 0

        guard reader.pos + 4 <= reader.end else { throw ZipError.corrupt("onverwacht einde van de gegevens") }
        let length = Int(reader.input[reader.pos]) | (Int(reader.input[reader.pos + 1]) << 8)
        let complement = Int(reader.input[reader.pos + 2]) | (Int(reader.input[reader.pos + 3]) << 8)
        guard length == (~complement & 0xFFFF) else { throw ZipError.corrupt("ongeldig opgeslagen blok") }
        reader.pos += 4
        guard reader.pos + length <= reader.end else { throw ZipError.corrupt("onverwacht einde van de gegevens") }
        try out.reserve(length)
        var target = out.count
        for i in 0..<length {
            out.bytes[target] = reader.input[reader.pos + i]
            target += 1
        }
        out.count = target
        reader.pos += length
    }

    private static func dynamicTables(_ reader: inout BitReader) throws -> (literals: Huffman, distances: Huffman) {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeLengthCount = try reader.bits(4) + 4
        guard literalCount <= 286, distanceCount <= 30 else { throw ZipError.corrupt("ongeldig dynamisch blok") }

        var codeLengths = [UInt8](repeating: 0, count: 19)
        for i in 0..<codeLengthCount {
            codeLengths[codeLengthOrder[i]] = UInt8(try reader.bits(3))
        }
        let codeLengthTable = try Huffman(lengths: codeLengths)

        var lengths = [UInt8](repeating: 0, count: literalCount + distanceCount)
        var index = 0
        while index < lengths.count {
            let symbol = try codeLengthTable.decode(&reader)
            if symbol < 16 {
                lengths[index] = UInt8(symbol)
                index += 1
            } else {
                var repeatValue: UInt8 = 0
                var repeatCount = 0
                switch symbol {
                case 16:
                    guard index > 0 else { throw ZipError.corrupt("ongeldig dynamisch blok") }
                    repeatValue = lengths[index - 1]
                    repeatCount = 3 + (try reader.bits(2))
                case 17:
                    repeatCount = 3 + (try reader.bits(3))
                default:
                    repeatCount = 11 + (try reader.bits(7))
                }
                guard index + repeatCount <= lengths.count else { throw ZipError.corrupt("ongeldig dynamisch blok") }
                for _ in 0..<repeatCount {
                    lengths[index] = repeatValue
                    index += 1
                }
            }
        }
        guard lengths[256] != 0 else { throw ZipError.corrupt("ongeldig dynamisch blok") }

        let literals = try Huffman(lengths: Array(lengths[0..<literalCount]))
        let distances = try Huffman(lengths: Array(lengths[literalCount..<(literalCount + distanceCount)]))
        return (literals, distances)
    }

    private static func codedBlock(_ reader: inout BitReader, _ out: inout OutputBuffer,
                                   literals: Huffman, distances: Huffman) throws {
        while true {
            let symbol = try literals.decode(&reader)
            if symbol < 256 {
                try out.put(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let lengthIndex = symbol - 257
                guard lengthIndex < 29 else { throw ZipError.corrupt("ongeldige lengtecode") }
                let length = lengthBase[lengthIndex] + (try reader.bits(lengthExtra[lengthIndex]))
                let distanceSymbol = try distances.decode(&reader)
                guard distanceSymbol < 30 else { throw ZipError.corrupt("ongeldige afstandscode") }
                let distance = distanceBase[distanceSymbol] + (try reader.bits(distanceExtra[distanceSymbol]))
                try out.copy(distance: distance, length: length)
            }
        }
    }
}

// MARK: - Lezen

/// Een bestand in een ZIP, zoals de centrale directory het beschrijft.
struct ZipEntry: Equatable {
    var name: String
    /// 0 = opgeslagen, 8 = DEFLATE.
    var method: Int
    var flags: Int
    var crc32: UInt32
    var compressedSize: Int
    var uncompressedSize: Int
    var localHeaderOffset: Int

    var isDirectory: Bool { name.hasSuffix("/") }
    var isEncrypted: Bool { flags & 1 != 0 }
}

struct ZipArchive {
    /// Grootste onderdeel dat we uitpakken.
    static let maxEntrySize = Inflate.defaultLimit

    private let bytes: [UInt8]
    let entries: [ZipEntry]

    init(data: Data) throws {
        let bytes = [UInt8](data)
        self.bytes = bytes
        guard bytes.count >= 22 else { throw ZipError.notAZip }

        // Het eindrecord staat achteraan, na een commentaar van hooguit 64 KB.
        let lowest = max(0, bytes.count - 22 - 65_535)
        var eocd = -1
        var position = bytes.count - 22
        while position >= lowest {
            if bytes[position] == 0x50, bytes[position + 1] == 0x4B, bytes[position + 2] == 0x05, bytes[position + 3] == 0x06 {
                eocd = position
                break
            }
            position -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }

        let total = ZipArchive.u16(bytes, eocd + 10)
        let directorySize = ZipArchive.u32(bytes, eocd + 12)
        var directoryOffset = ZipArchive.u32(bytes, eocd + 16)
        if total == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            throw ZipError.corrupt("ZIP64-bestanden worden niet ondersteund")
        }
        // Soms klopt de afstand niet (bestand met iets ervoor): reken dan terug vanaf het eindrecord.
        if !ZipArchive.hasSignature(bytes, directoryOffset, 0x0201_4B50), total > 0 {
            let alternative = eocd - directorySize
            if alternative >= 0, ZipArchive.hasSignature(bytes, alternative, 0x0201_4B50) {
                directoryOffset = alternative
            } else {
                throw ZipError.corrupt("centrale directory niet gevonden")
            }
        }

        var found: [ZipEntry] = []
        var cursor = directoryOffset
        for _ in 0..<total {
            guard ZipArchive.hasSignature(bytes, cursor, 0x0201_4B50), cursor + 46 <= bytes.count else {
                throw ZipError.corrupt("centrale directory is onvolledig")
            }
            let flags = ZipArchive.u16(bytes, cursor + 8)
            let method = ZipArchive.u16(bytes, cursor + 10)
            let crc = UInt32(truncatingIfNeeded: ZipArchive.u32(bytes, cursor + 16))
            let compressed = ZipArchive.u32(bytes, cursor + 20)
            let uncompressed = ZipArchive.u32(bytes, cursor + 24)
            let nameLength = ZipArchive.u16(bytes, cursor + 28)
            let extraLength = ZipArchive.u16(bytes, cursor + 30)
            let commentLength = ZipArchive.u16(bytes, cursor + 32)
            let offset = ZipArchive.u32(bytes, cursor + 42)
            let nameStart = cursor + 46
            guard nameStart + nameLength + extraLength + commentLength <= bytes.count else {
                throw ZipError.corrupt("centrale directory is onvolledig")
            }
            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || offset == 0xFFFF_FFFF {
                throw ZipError.corrupt("ZIP64-bestanden worden niet ondersteund")
            }
            let name = ZipArchive.decodeName(Array(bytes[nameStart..<(nameStart + nameLength)]))
            found.append(ZipEntry(name: name, method: method, flags: flags, crc32: crc,
                                  compressedSize: compressed, uncompressedSize: uncompressed,
                                  localHeaderOffset: offset))
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        entries = found
    }

    /// Zoekt een onderdeel op naam: hoofdletterongevoelig, `\` telt als `/`.
    func entry(named name: String) -> ZipEntry? {
        let wanted = ZipArchive.normalized(name)
        return entries.first { ZipArchive.normalized($0.name) == wanted }
    }

    func contains(_ name: String) -> Bool { entry(named: name) != nil }

    /// De inhoud van een onderdeel, gecontroleerd op lengte en controlesom.
    func data(for entry: ZipEntry) throws -> Data {
        if entry.isEncrypted { throw ZipError.encrypted }
        guard entry.uncompressedSize <= ZipArchive.maxEntrySize else { throw ZipError.tooLarge }

        let offset = entry.localHeaderOffset
        guard ZipArchive.hasSignature(bytes, offset, 0x0403_4B50), offset + 30 <= bytes.count else {
            throw ZipError.corrupt("onderdeel '\(entry.name)' ontbreekt")
        }
        let nameLength = ZipArchive.u16(bytes, offset + 26)
        let extraLength = ZipArchive.u16(bytes, offset + 28)
        let start = offset + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start <= end, end <= bytes.count else { throw ZipError.corrupt("onderdeel '\(entry.name)' is afgekapt") }

        let output: [UInt8]
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.uncompressedSize else {
                throw ZipError.corrupt("onderdeel '\(entry.name)' heeft een verkeerde lengte")
            }
            output = Array(bytes[start..<end])
        case 8:
            output = try Inflate.inflate(bytes, start: start, end: end,
                                         expectedSize: entry.uncompressedSize, limit: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
        guard output.count == entry.uncompressedSize else {
            throw ZipError.corrupt("onderdeel '\(entry.name)' heeft een verkeerde lengte")
        }
        guard CRC32.checksum(output) == entry.crc32 else {
            throw ZipError.corrupt("onderdeel '\(entry.name)' heeft een verkeerde controlesom")
        }
        return Data(output)
    }

    /// De inhoud van het onderdeel met deze naam, of nil als het niet bestaat.
    func data(named name: String) throws -> Data? {
        guard let found = entry(named: name) else { return nil }
        return try data(for: found)
    }

    // MARK: Hulpjes

    private static func normalized(_ name: String) -> String {
        var result = name.replacingOccurrences(of: "\\", with: "/").lowercased()
        while result.hasPrefix("/") { result.removeFirst() }
        return result
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> Int {
        guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
        return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> Int {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            | (Int(bytes[offset + 2]) << 16) | (Int(bytes[offset + 3]) << 24)
    }

    private static func hasSignature(_ bytes: [UInt8], _ offset: Int, _ signature: Int) -> Bool {
        guard offset >= 0, offset + 4 <= bytes.count else { return false }
        return u32(bytes, offset) == signature
    }

    /// Namen zijn UTF-8 of ouderwets CP437; we lezen ze als UTF-8 en anders als Latin-1.
    private static func decodeName(_ raw: [UInt8]) -> String {
        if let text = String(bytes: raw, encoding: .utf8) { return text }
        return String(raw.map { Character(Unicode.Scalar($0)) })
    }
}

// MARK: - Schrijven

/// Schrijft een ZIP met onderdelen die alleen zijn opgeslagen (niet ingepakt). Dat is geldig voor Excel en
/// Numbers en houdt de code klein. Wordt gebruikt voor het voorbeeldbestand.
enum ZipWriter {
    /// 1 januari 2026 als DOS-datum; een vaste waarde, zodat het bestand altijd hetzelfde is.
    private static let dosDate: UInt16 = UInt16(((2026 - 1980) << 9) | (1 << 5) | 1)

    static func archive(_ files: [(name: String, data: Data)]) -> Data {
        var out = [UInt8]()
        var central = [UInt8]()
        var count = 0

        for file in files {
            let name = Array(file.name.utf8)
            let payload = [UInt8](file.data)
            let crc = CRC32.checksum(payload)
            let offset = out.count

            out += le32(0x0403_4B50)
            out += le16(20)                 // versie
            out += le16(0x0800)             // vlaggen: UTF-8 namen
            out += le16(0)                  // methode: opgeslagen
            out += le16(0)                  // tijd
            out += le16(dosDate)
            out += le32(crc)
            out += le32(UInt32(payload.count))
            out += le32(UInt32(payload.count))
            out += le16(UInt16(name.count))
            out += le16(0)
            out += name
            out += payload

            central += le32(0x0201_4B50)
            central += le16(20)             // gemaakt met
            central += le16(20)             // nodig
            central += le16(0x0800)
            central += le16(0)
            central += le16(0)
            central += le16(dosDate)
            central += le32(crc)
            central += le32(UInt32(payload.count))
            central += le32(UInt32(payload.count))
            central += le16(UInt16(name.count))
            central += le16(0)              // extra
            central += le16(0)              // commentaar
            central += le16(0)              // schijf
            central += le16(0)              // interne kenmerken
            central += le32(0)              // externe kenmerken
            central += le32(UInt32(offset))
            central += name
            count += 1
        }

        let directoryOffset = out.count
        out += central
        out += le32(0x0605_4B50)
        out += le16(0)
        out += le16(0)
        out += le16(UInt16(count))
        out += le16(UInt16(count))
        out += le32(UInt32(central.count))
        out += le32(UInt32(directoryOffset))
        out += le16(0)
        return Data(out)
    }

    private static func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    private static func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }
}
