import XCTest
import Foundation
@testable import MyBuddyCore

// Tests voor de ZIP-lezer en de eigen DEFLATE-decoder (Zip.swift).
//
// De ingepakte voorbeelden zijn gemaakt met Python (zlib en zipfile), dus onafhankelijk van onze code:
// - vaste Huffman-codes (Z_FIXED), dynamische Huffman-codes, opgeslagen blokken en een stroom met een
//   synchronisatiepunt (opgeslagen blok midden in een ingepakte stroom);
// - een handgebouwde stroom met codes van 11...15 bits (de trage route in de decoder), die zlib zelf ook uitpakt;
// - ZIP-bestanden met opgeslagen en ingepakte onderdelen, een map, een leeg bestand, een naam met een accent
//   en een bestand met een 'data descriptor' (de groottes staan dan alleen in de centrale directory).
// De verwachte tekst wordt hier opnieuw opgebouwd met dezelfde eenvoudige formule als in het script.

/// Zet base64 uit een voorbeeld (met regeleinden) om naar bytes.
func b64Fixture(_ text: String) -> [UInt8] {
    let cleaned = text.filter { !$0.isWhitespace }
    guard let data = Data(base64Encoded: cleaned) else {
        XCTFail("Ongeldige base64 in testvoorbeeld")
        return []
    }
    return [UInt8](data)
}

/// Willekeurige maar vaste tekst: een LCG kiest woorden. Zelfde formule als in het Python-script.
func zipSampleText(words count: Int) -> [UInt8] {
    let words = ["huur", "boodschappen", "salaris", "energie", "verzekering", "internet", "vakantie", "sparen",
                 "belegging", "abonnement", "telefoon", "belasting", "kleding", "benzine", "cadeau", "hobby",
                 "noodfonds", "hypotheek", "water", "licht"]
    var seed: UInt64 = 12_345
    var out: [UInt8] = []
    for i in 0..<count {
        seed = (seed &* 1_103_515_245 &+ 12_345) & 0x7fff_ffff
        out += Array(words[Int((seed >> 16) % UInt64(words.count))].utf8)
        out.append(i % 9 == 8 ? 10 : 32)
    }
    return out
}

private let rawFixedBase64 = """
S0rNSU1Pz8xLV0iCszIqC/JLMlJTsxXKE0tSixSKCxKLUvMUMvOAnLzUEoWk/PyU4uSMxIICoGhxYk5iUWaxQglQe1p+fh4Ximx2
TmoKyMiczOSMElTjMvKTkiqRbE1KzavKzEuFaUE1Jw/IScvPSykGaUgsLgFpQLgHLoSkDLtumOFlqUVVqdmpRWCLkZUmJ6akJpYq
pOalFqVnpsJ9hdUBULXQEOCC6YHRZYnZiXklQAbE87CggPkT7nxYCMKDnQumFBJE6BpR3IviEXSTE5Py8/JSc1PzSriggQ73DyQq
4Fw4A2IlsqkIQ2AWcCESCER5RmlpEVJMQsMFoQohhQhGcKBw4XIG1LmIsIYHJpJzMKMVYSU8DCA2oHgCZibY2RB5tMQIjwHU4MVw
DNSnSKaDzUQ4DCkGoGqREjy2bAQ3GmEGNCwgqQhiCtx9UEMx3YHEhGhEuB6ZBYlPmOUwGhImMDsgPAiJFAaoIQMNN6hD4L6A5QWY
yRC3wKXBoQVP30jhgZJBYYYgMgLMEfD0gqwc2b1I4lywVArVCzMVLUnCUy9INZiA5W9Y9oKmeTCJNTWiWYSQgEYeNEIRoQBPtTAf
wlMvnIFQA48ssClcyGkPknex5BT0aMDIoSAnc2FJezCNyGUtNPkiBzkk5GCmwxQjZUeUtI61UIWELUIEI/4QNQyqs3HlKGiyx5bJ
cMUIRqaBxQeSBGregJVTyEkXuUSBqYN7GQA=
"""

private let rawDynamicBase64 = """
dVXbloMgDHznK/w1qKl6dMGjtHu6X79Krih9sSjJMJlMaIAFhmGKQxdkNX7WlEeAufv1GbZuX/0GsZvi8RIhdyGlfn+Mfl2Pr7tf
/DbtXT7SnylFV+3OC/Qn5DI9xlzDjSmEjzk1QPybInBKjROPl2eK/X4m+D2fCcpHPpmwdjaDv2H7gxm2crANffge/KuDCNswgVTV
JECxpIDjHP59+9nHfCyweJaC6xT6rKDI7jgUJbomVnyrQq7IPqQY4QdidiS61IOtkFdZ4JEWVUH4AKcGwfDx9dpMJ0kXjdItlbGI
4r7RILqqtYhp6NzbqkeKBnhCVQRjFtq4fzGjdKCW90aGKjXoBVOJmQ5QrDF8a4wEWjFIC3QRogg/Ar3zMEtMVPZ2hf3kw/kXNeEz
8A2fRoNaGdKNiEgVPAuMjFxku6gl/jZ6VAPKIDoITEL8YsMtX/PdsUspl1EvlhT3ntHlwfPN40WeL8+mGy8H6QY1jxqqKohruUJx
ryw0RppVUJz1Hs5uY1KubbhN6EnZNbzHifauJftayVE5RudgM46V15uXKmqrX27903+Ymva3iSLbt4bsW0duQ8P9MBv1bPA9Za1r
bxSOk5L/AQ==
"""

private let rawSyncBase64 = """
bFHREoMgDHv3K/i1olE4WOsBc6dfP5zCxPOJFpo0CRoe02R5UrpWZp0lGcCpDyUEFWcKYGU5N4yktMgQe0PznG8jeQo2qpThowh3
zavzGHZKb3uTWjojWq+XrRq8WUaBtDycm1F4iDuAYtoBfz316jL2jC7kC8IGh/BbfB3taQC9FRhhsqiuHgWcs2cCXcGUcyFHnHJx
mC9RFJ9Vfkmwxt6V0SOiO7DR2xi5M5MWZrzAqTtDr36Or6htLY6VXwAAAP//bVFbDoQgDPznFFwNpALRAIGuGz39VpdHSfyiQGc6
M5Wn1tHdplf6wFFkQPVl75BVKgKfISFqRUSBeoKnFPwVQEsbfCaBV4aD2lNSbikmRs0bDOxbHVlvYgNwGNPpZPGZAiqvzA8Q3eJ3
CR4DBX5QYckptFM0/EeBUcuNQkqc8MWEuJq63L+fhq29k15mRLTRjIK3jucxrct/FcDQnZz5tBZuQN3KE3pdxd98g0w83VVLYNLY
9Ux0I/YxtVc/
"""

private let rawLongCodesBase64 = """
BeDbkiRJkizLfisSi5pHVs/a5//fDgBAVVW1bdu23d3d3d1777333vd93/d9v9/v9/v9/f39/f379+/ff//997///d//+//+f/+/
/5927/v9/fvvf//3//6//9//9//+73///fv7fe+W/9//7//3/wc=
"""

private let rawBombBase64 = """
7cExAQAAAMKgrOtfwhoeQAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACvBg==
"""

private let zipBasicBase64 = """
UEsDBBQAAAAAAAAAIVwqZ3dTIQAAACEAAAAKAAAAc3RvcmVkLnR4dE9wZ2VzbGFnZW4gdGVrc3QsIG5pZXQgaW5nZXBha3QuClBL
AwQUAAAACAAAACFchYrqoMkBAABwBwAAEAAAAE1hcC9pbmdlcGFrdC50eHR1VduWgyAMfOcr/DWoqXp0waO0e7pfv0quKH2xKMkw
mUxogAWGYYpDF2Q1ftaUR4C5+/UZtm5f/Qaxm+LxEiF3IaV+f4x+XY+vu1/8Nu1dPtKfKUVX7c4L9CfkMj3GXMONKYSPOTVA/Jsi
cEqNE4+XZ4r9fib4PZ8Jykc+mbB2NoO/YfuDGbZysA19+B78q4MI2zCBVNUkQLGkgOMc/n372cd8LLB4loLrFPqsoMjuOBQluiZW
fKtCrsg+pBjhB2J2JLrUg62QV1ngkRZVQfgApwbB8PH12kwnSReN0i2VsYjivtEguqq1iGno3NuqR4oGeEJVBGMW2rh/MaN0oJb3
RoYqNegFU4mZDlCsMXxrjARaMUgLdBGiCD8CvfMwS0xU9naF/eTD+Rc14TPwDZ9Gg1oZ0o2ISBU8C4yMXGS7qCX+NnpUA8ogOghM
Qvxiwy1f892xSymXUS+WFPee0eXB883jRZ4vz6YbLwfpBjWPGqoqiGu5QnGvLDRGmlVQnPUezm5jUq5tuE3oSdk1vMeJ9q4l+1rJ
UTlG52AzjpXXm5cqaqtfbv3Tf5ia9reJItu3huxbR25Dw/0wG/Vs8D1lrWtvFI6Tkv8BUEsDBBQAAAAAAAAAIVwAAAAAAAAAAAAA
AAAEAAAATWFwL1BLAwQUAAAACAAAACFcAAAAAAIAAAAAAAAACAAAAGxlZWcudHh0AwBQSwMEFAAACAgAAAAhXHxhDB0XAAAAFQAA
AAkAAABjYWbDqS50eHTLzi/ISlXIzk9Ly0xVeNS0RsFIx9QAAFBLAQIUAxQAAAAAAAAAIVwqZ3dTIQAAACEAAAAKAAAAAAAAAAAA
AACAAQAAAABzdG9yZWQudHh0UEsBAhQDFAAAAAgAAAAhXIWK6qDJAQAAcAcAABAAAAAAAAAAAAAAAIABSQAAAE1hcC9pbmdlcGFr
dC50eHRQSwECFAMUAAAAAAAAACFcAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAgAFAAgAATWFwL1BLAQIUAxQAAAAIAAAAIVwAAAAA
AgAAAAAAAAAIAAAAAAAAAAAAAACAAWICAABsZWVnLnR4dFBLAQIUAxQAAAgIAAAAIVx8YQwdFwAAABUAAAAJAAAAAAAAAAAAAACA
AYoCAABjYWbDqS50eHRQSwUGAAAAAAUABQAVAQAAyAIAAAAA
"""

private let zipDescriptorBase64 = """
UEsDBBQACAAIAGOLSF0AAAAAAAAAAAAAAAAKAAAAc3Ryb29tLnR4dHVV25aDIAx85yv8NaipenTBo7R7ul+/Sq4ofbEoyTCZTGiA
BYZhikMXZDV+1pRHgLn79Rm2bl/9BrGb4vESIXchpX5/jH5dj6+7X/w27V0+0p8pRVftzgv0J+QyPcZcw40phI85NUD8myJwSo0T
j5dniv1+Jvg9nwnKRz6ZsHY2g79h+4MZtnKwDX34HvyrgwjbMIFU1SRAsaSA4xz+ffvZx3wssHiWgusU+qygyO44FCW6JlZ8q0Ku
yD6kGOEHYnYkutSDrZBXWeCRFlVB+ACnBsHw8fXaTCdJF43SLZWxiOK+0SC6qrWIaejc26pHigZ4QlUEYxbauH8xo3SglvdGhio1
6AVTiZkOUKwxfGuMBFoxSAt0EaIIPwK98zBLTFT2doX95MP5FzXhM/ANn0aDWhnSjYhIFTwLjIxcZLuoJf42elQDyiA6CExC/GLD
LV/z3bFLKZdRL5YU957R5cHzzeNFni/PphsvB+kGNY8aqiqIa7lCca8sNEaaVVCc9R7ObmNSrm24TehJ2TW8x4n2riX7WslROUbn
YDOOldeblypqq19u/dN/mJr2t4ki27eG7FtHbkPD/TAb9WzwPWWta28UjpOS/wFQSwcIhYrqoMkBAABwBwAAUEsBAhQDFAAIAAgA
Y4tIXYWK6qDJAQAAcAcAAAoAAAAAAAAAAAAAAIABAAAAAHN0cm9vbS50eHRQSwUGAAAAAAEAAQA4AAAAAQIAAAAA
"""

final class ZipTests: XCTestCase {

    // MARK: CRC-32

    func testCRC32KnownValues() {
        // Standaardtestwaarde van CRC-32: "123456789" geeft 0xCBF43926.
        XCTAssertEqual(CRC32.checksum(Array("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum([]), 0)
        XCTAssertEqual(CRC32.checksum([0x00]), 0xD202_EF8D)
    }

    // MARK: DEFLATE: blokken

    func testStoredBlocksIncludingMultipleBlocks() throws {
        // Twee opgeslagen blokken: eerst een blok dat niet het laatste is, daarna het laatste.
        let first: [UInt8] = Array("Eerste deel, ".utf8)
        let second: [UInt8] = Array("tweede deel.".utf8)
        var stream: [UInt8] = [0x00, UInt8(first.count), 0x00, UInt8(~first.count & 0xFF), 0xFF] + first
        stream += [0x01, UInt8(second.count), 0x00, UInt8(~second.count & 0xFF), 0xFF] + second
        let out = try Inflate.inflate(stream)
        XCTAssertEqual(String(decoding: out, as: UTF8.self), "Eerste deel, tweede deel.")
    }

    func testStoredBlockWithWrongComplementThrows() {
        let stream: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x61, 0x62, 0x63]
        XCTAssertThrowsError(try Inflate.inflate(stream))
    }

    func testStoredBlockLargerThanOneBlockOfData() throws {
        // 70.000 bytes in twee opgeslagen blokken (65.535 + 4.465).
        let data = (0..<70_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        let firstLength = 65_535
        let secondLength = data.count - firstLength
        var stream: [UInt8] = [0x00, 0xFF, 0xFF, 0x00, 0x00]
        stream += data[0..<firstLength]
        stream += [0x01, UInt8(secondLength & 0xFF), UInt8(secondLength >> 8),
                   UInt8(~secondLength & 0xFF), UInt8((~secondLength >> 8) & 0xFF)]
        stream += data[firstLength...]
        let out = try Inflate.inflate(stream)
        XCTAssertEqual(out, data)
    }

    func testFixedHuffmanBlock() throws {
        let out = try Inflate.inflate(b64Fixture(rawFixedBase64))
        XCTAssertEqual(out, zipSampleText(words: 220))
    }

    func testDynamicHuffmanBlock() throws {
        let out = try Inflate.inflate(b64Fixture(rawDynamicBase64))
        XCTAssertEqual(out, zipSampleText(words: 220))
    }

    func testStreamWithSyncFlushMixesBlockTypes() throws {
        // Ingepakt, dan een leeg opgeslagen blok (synchronisatiepunt, op een bytegrens), dan weer ingepakt.
        let part1 = zipSampleText(words: 60)
        let part2 = Array(zipSampleText(words: 60).reversed())
        let out = try Inflate.inflate(b64Fixture(rawSyncBase64))
        XCTAssertEqual(out, part1 + part2)
    }

    func testLongHuffmanCodesOfElevenToFifteenBits() throws {
        // Handgebouwd dynamisch blok: de letters a...n hebben codes van 1...14 bits, 'o' en het einde 15 bits.
        var expected: [UInt8] = []
        for (i, letter) in Array(97...110).enumerated() {
            expected += [UInt8](repeating: UInt8(letter), count: max(1, 12 - i))
        }
        expected += Array("ooo".utf8) + Array("abcdefghijklmno".utf8) + Array("nmlkjihgfedcba".utf8) + Array("ooo".utf8)
        let out = try Inflate.inflate(b64Fixture(rawLongCodesBase64))
        XCTAssertEqual(out, expected)
    }

    func testOverlappingMatchRepeatsLastByte() throws {
        // "a" gevolgd door een verwijzing met afstand 1 en lengte 49: zo ontstaan 50 keer "a".
        let stream: [UInt8] = [0x4B, 0x4C, 0x24, 0x15, 0x00, 0x00]
        let out = try Inflate.inflate(stream)
        XCTAssertEqual(out, [UInt8](repeating: 0x61, count: 50))
    }

    func testEmptyFixedBlockGivesNothing() throws {
        // Alleen "laatste blok, vaste codes, einde".
        XCTAssertEqual(try Inflate.inflate([0x03, 0x00]), [])
    }

    // MARK: DEFLATE: fouten en grenzen

    func testTruncatedStreamThrows() {
        let stream = b64Fixture(rawDynamicBase64)
        XCTAssertThrowsError(try Inflate.inflate(Array(stream.prefix(stream.count / 2))))
        XCTAssertThrowsError(try Inflate.inflate([]))
    }

    func testInvalidBlockTypeThrows() {
        // 0x07 = laatste blok met type 3, dat bestaat niet.
        XCTAssertThrowsError(try Inflate.inflate([0x07, 0x00, 0x00]))
    }

    func testDistanceBeyondStartThrows() {
        // Vaste codes: lengtecode 257 met afstand 1 terwijl er nog niets is uitgepakt.
        // Bits: 1 (laatste), 01 (vast), dan symbool 257 (7 bits 0000001), afstandscode 0 (5 bits 00000).
        let stream: [UInt8] = [0x03, 0x02, 0x00]
        XCTAssertThrowsError(try Inflate.inflate(stream))
    }

    func testOutputLimitStopsDecompressionBombs() {
        // 100.000 keer "a" past in 115 bytes. Met een limiet van 5.000 moet het stoppen.
        let stream = b64Fixture(rawBombBase64)
        XCTAssertLessThan(stream.count, 200)
        XCTAssertThrowsError(try Inflate.inflate(stream, expectedSize: 0, limit: 5_000)) { error in
            XCTAssertEqual(error as? ZipError, .tooLarge)
        }
        // Zonder die limiet pakt het gewoon uit.
        XCTAssertEqual(try Inflate.inflate(stream).count, 100_000)
    }

    // MARK: ZIP

    func testBasicArchiveListsAndExtractsEntries() throws {
        let archive = try ZipArchive(data: Data(b64Fixture(zipBasicBase64)))
        XCTAssertEqual(archive.entries.map(\.name), ["stored.txt", "Map/ingepakt.txt", "Map/", "leeg.txt", "caf\u{00E9}.txt"])

        let stored = try XCTUnwrap(archive.entry(named: "stored.txt"))
        XCTAssertEqual(stored.method, 0)
        XCTAssertEqual(String(decoding: try archive.data(for: stored), as: UTF8.self), "Opgeslagen tekst, niet ingepakt.\n")

        let packed = try XCTUnwrap(archive.entry(named: "Map/ingepakt.txt"))
        XCTAssertEqual(packed.method, 8)
        XCTAssertLessThan(packed.compressedSize, packed.uncompressedSize)
        XCTAssertEqual([UInt8](try archive.data(for: packed)), zipSampleText(words: 220))

        let folder = try XCTUnwrap(archive.entry(named: "Map/"))
        XCTAssertTrue(folder.isDirectory)

        let empty = try XCTUnwrap(archive.entry(named: "leeg.txt"))
        XCTAssertEqual(try archive.data(for: empty).count, 0)

        let accent = try XCTUnwrap(archive.entry(named: "caf\u{00E9}.txt"))
        XCTAssertEqual(String(decoding: try archive.data(for: accent), as: UTF8.self), "kopje koffie \u{20AC} 2,50")
    }

    func testLookupIsCaseInsensitiveAndAcceptsBackslashes() throws {
        let archive = try ZipArchive(data: Data(b64Fixture(zipBasicBase64)))
        XCTAssertNotNil(archive.entry(named: "STORED.TXT"))
        XCTAssertNotNil(archive.entry(named: "map\\ingepakt.txt"))
        XCTAssertNotNil(archive.entry(named: "/Map/ingepakt.txt"))
        XCTAssertNil(archive.entry(named: "bestaatniet.txt"))
        XCTAssertNil(try archive.data(named: "bestaatniet.txt"))
        XCTAssertEqual(try archive.data(named: "stored.txt")?.count, 33)
    }

    func testArchiveWithDataDescriptorUsesCentralDirectorySizes() throws {
        let bytes = b64Fixture(zipDescriptorBase64)
        // Bit 3 van de vlaggen: groottes staan achter de gegevens, niet in de lokale kop.
        XCTAssertNotEqual(Int(bytes[6]) & 0x08, 0)
        let archive = try ZipArchive(data: Data(bytes))
        XCTAssertEqual(archive.entries.count, 1)
        XCTAssertEqual([UInt8](try XCTUnwrap(try archive.data(named: "stroom.txt"))), zipSampleText(words: 220))
    }

    func testFlippedByteInStoredDataFailsChecksum() throws {
        var bytes = b64Fixture(zipBasicBase64)
        // De gegevens van "stored.txt" beginnen na de lokale kop (30 bytes + naam van 10 bytes + extra veld).
        let extra = Int(bytes[28]) | (Int(bytes[29]) << 8)
        bytes[30 + 10 + extra + 3] ^= 0x01
        let archive = try ZipArchive(data: Data(bytes))
        let entry = try XCTUnwrap(archive.entry(named: "stored.txt"))
        XCTAssertThrowsError(try archive.data(for: entry)) { error in
            guard case ZipError.corrupt = error else { return XCTFail("Verwachtte .corrupt, kreeg \(error)") }
        }
    }

    func testBrokenCompressedDataThrowsInsteadOfCrashing() throws {
        var bytes = b64Fixture(zipBasicBase64)
        let archive = try ZipArchive(data: Data(bytes))
        let entry = try XCTUnwrap(archive.entry(named: "Map/ingepakt.txt"))
        let extra = Int(bytes[entry.localHeaderOffset + 28]) | (Int(bytes[entry.localHeaderOffset + 29]) << 8)
        let start = entry.localHeaderOffset + 30 + entry.name.utf8.count + extra
        for i in 0..<40 { bytes[start + 10 + i] = 0xFF }
        let broken = try ZipArchive(data: Data(bytes))
        XCTAssertThrowsError(try broken.data(for: try XCTUnwrap(broken.entry(named: "Map/ingepakt.txt"))))
    }

    func testNotAZipThrows() {
        XCTAssertThrowsError(try ZipArchive(data: Data())) { XCTAssertEqual($0 as? ZipError, .notAZip) }
        XCTAssertThrowsError(try ZipArchive(data: Data("Dit is gewoon tekst, geen zipbestand.".utf8))) {
            XCTAssertEqual($0 as? ZipError, .notAZip)
        }
        let bytes = b64Fixture(zipBasicBase64)
        // Zonder het eindrecord is het geen ZIP meer.
        XCTAssertThrowsError(try ZipArchive(data: Data(bytes.dropLast(22)))) { XCTAssertEqual($0 as? ZipError, .notAZip) }
    }

    func testTruncatedCentralDirectoryThrows() {
        var bytes = b64Fixture(zipBasicBase64)
        // Het eindrecord blijft staan, maar de centrale directory ervoor is ingekort.
        let tail = Array(bytes.suffix(22))
        bytes = Array(bytes.dropLast(22 + 60)) + tail
        XCTAssertThrowsError(try ZipArchive(data: Data(bytes)))
    }

    func testEncryptedEntryIsRefused() throws {
        var bytes = b64Fixture(zipBasicBase64)
        guard let central = findSignature(bytes, [0x50, 0x4B, 0x01, 0x02]) else { return XCTFail("Geen centrale directory") }
        bytes[central + 8] |= 0x01
        let archive = try ZipArchive(data: Data(bytes))
        let entry = try XCTUnwrap(archive.entries.first)
        XCTAssertTrue(entry.isEncrypted)
        XCTAssertThrowsError(try archive.data(for: entry)) { XCTAssertEqual($0 as? ZipError, .encrypted) }
    }

    func testUnsupportedCompressionMethodIsReported() throws {
        var bytes = b64Fixture(zipBasicBase64)
        guard let central = findSignature(bytes, [0x50, 0x4B, 0x01, 0x02]) else { return XCTFail("Geen centrale directory") }
        bytes[central + 10] = 12   // bzip2
        let archive = try ZipArchive(data: Data(bytes))
        let entry = try XCTUnwrap(archive.entries.first)
        XCTAssertThrowsError(try archive.data(for: entry)) { XCTAssertEqual($0 as? ZipError, .unsupportedMethod(12)) }
    }

    func testEntryClaimingHugeSizeIsRefused() throws {
        var bytes = b64Fixture(zipBasicBase64)
        guard let central = findSignature(bytes, [0x50, 0x4B, 0x01, 0x02]) else { return XCTFail("Geen centrale directory") }
        // Ongecomprimeerde grootte 0x7FFFFFFF (2 GB): meer dan we willen uitpakken.
        bytes[central + 24] = 0xFF; bytes[central + 25] = 0xFF; bytes[central + 26] = 0xFF; bytes[central + 27] = 0x7F
        let archive = try ZipArchive(data: Data(bytes))
        let entry = try XCTUnwrap(archive.entries.first)
        XCTAssertThrowsError(try archive.data(for: entry)) { XCTAssertEqual($0 as? ZipError, .tooLarge) }
    }

    // MARK: Schrijver

    func testWriterProducesArchiveThatReadsBack() throws {
        let files: [(name: String, data: Data)] = [
            (name: "a.txt", data: Data("123456789".utf8)),
            (name: "map/b.xml", data: Data("<x>\u{20AC}</x>".utf8)),
            (name: "leeg.bin", data: Data())
        ]
        let bytes = [UInt8](ZipWriter.archive(files))
        // Opbouw volgens de ZIP-specificatie: lokale kop aan het begin, eindrecord achteraan.
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertEqual(Array(bytes.suffix(22).prefix(4)), [0x50, 0x4B, 0x05, 0x06])
        XCTAssertEqual(Int(bytes[bytes.count - 22 + 10]), 3)   // aantal onderdelen

        let archive = try ZipArchive(data: Data(bytes))
        XCTAssertEqual(archive.entries.map(\.name), ["a.txt", "map/b.xml", "leeg.bin"])
        // De controlesom van "123456789" is een bekende waarde.
        XCTAssertEqual(archive.entries[0].crc32, 0xCBF4_3926)
        XCTAssertEqual(String(decoding: try XCTUnwrap(try archive.data(named: "a.txt")), as: UTF8.self), "123456789")
        XCTAssertEqual(String(decoding: try XCTUnwrap(try archive.data(named: "map/b.xml")), as: UTF8.self), "<x>\u{20AC}</x>")
        XCTAssertEqual(try archive.data(named: "leeg.bin")?.count, 0)
    }

    func testWriterOutputIsDeterministic() {
        let files: [(name: String, data: Data)] = [(name: "a.txt", data: Data("abc".utf8))]
        XCTAssertEqual(ZipWriter.archive(files), ZipWriter.archive(files))
    }

    // MARK: Hulp

    private func findSignature(_ bytes: [UInt8], _ signature: [UInt8]) -> Int? {
        guard bytes.count >= signature.count else { return nil }
        for i in 0...(bytes.count - signature.count) where Array(bytes[i..<(i + signature.count)]) == signature {
            return i
        }
        return nil
    }
}
