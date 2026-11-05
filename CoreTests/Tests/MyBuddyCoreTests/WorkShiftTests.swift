import XCTest
import Foundation
@testable import MyBuddyCore

/// Tests van een dienst uit de agenda (App/Core/WorkShift.swift): alleen begin en einde op de minuut, opgeslagen als `[begin, einde]`,
/// samengevoegd bij overlap en gesneden per kalenderdag (ook de dag van 23 en 25 uur), met de pauze evenredig verdeeld.
final class WorkShiftTests: XCTestCase {
    private let base = 1_800_000_000.0   // een veelvoud van 60 seconden: minuut 30 000 000

    private func shift(_ start: Int, _ end: Int) -> WorkShift { WorkShift(startMinute: start, endMinute: end)! }

    // MARK: Begin en einde

    func testAShiftIsTruncatedToTheMinute() throws {
        let begin = Date(timeIntervalSince1970: base + 59.9)
        let end = Date(timeIntervalSince1970: base + 3_600.5)
        let made = try XCTUnwrap(WorkShift(start: begin, end: end))
        XCTAssertEqual(made.startMinute, 30_000_000)
        XCTAssertEqual(made.endMinute, 30_000_060)
        XCTAssertEqual(made.durationMinutes, 60)
        XCTAssertEqual(made.start, Date(timeIntervalSince1970: base))
        XCTAssertEqual(made.end, Date(timeIntervalSince1970: base + 3_600))
    }

    func testAShiftMustEndAfterItBegins() {
        let begin = Date(timeIntervalSince1970: base + 10)
        XCTAssertNil(WorkShift(start: begin, end: begin), "even lang is geen dienst")
        XCTAssertNil(WorkShift(start: begin, end: begin.addingTimeInterval(-600)), "het einde ligt voor het begin")
        XCTAssertNil(WorkShift(start: begin, end: begin.addingTimeInterval(30)), "binnen dezelfde minuut: nul minuten")
        XCTAssertNotNil(WorkShift(start: begin, end: begin.addingTimeInterval(60)))
        XCTAssertNil(WorkShift(startMinute: 5, endMinute: 5))
        XCTAssertNil(WorkShift(startMinute: 9, endMinute: 4))
    }

    func testTheMinuteRoundsDownAlsoBefore1970AndTolerantOfNonsense() {
        XCTAssertEqual(WorkShift.minute(of: Date(timeIntervalSince1970: 0)), 0)
        XCTAssertEqual(WorkShift.minute(of: Date(timeIntervalSince1970: 59)), 0)
        XCTAssertEqual(WorkShift.minute(of: Date(timeIntervalSince1970: -1)), -1, "naar beneden, niet naar nul")
        XCTAssertEqual(WorkShift.minute(of: Date(timeIntervalSince1970: -60)), -1)
        XCTAssertEqual(WorkShift.minute(of: Date(timeIntervalSince1970: .infinity)), 0, "geen crash bij onzin")
        XCTAssertEqual(WorkShift.minute(of: Date(timeIntervalSince1970: 1e20)), 1_000_000_000_000, "begrensd")
    }

    func testShiftsSortByBeginThenEnd() {
        let list = [shift(200, 300), shift(100, 500), shift(100, 200)]
        XCTAssertEqual(list.sorted().map { [$0.startMinute, $0.endMinute] }, [[100, 200], [100, 500], [200, 300]])
        XCTAssertTrue(shift(1, 2) < shift(1, 3))
    }

    // MARK: Opslag

    func testAShiftIsStoredAsTwoNumbersAndNothingElse() throws {
        let made = shift(30_000_000, 30_000_480)
        let data = try JSONEncoder().encode(made)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[30000000,30000480]")
        XCTAssertEqual(try JSONDecoder().decode(WorkShift.self, from: data), made)
        // Een lijst blijft compact: ± 20 bytes per dienst.
        let list = try JSONEncoder().encode([made, shift(30_001_000, 30_001_480)])
        XCTAssertEqual(String(decoding: list, as: UTF8.self), "[[30000000,30000480],[30001000,30001480]]")
    }

    func testADamagedShiftIsRefusedAlone() {
        XCTAssertThrowsError(try JSONDecoder().decode(WorkShift.self, from: Data("[300,250]".utf8)), "einde voor begin")
        XCTAssertThrowsError(try JSONDecoder().decode(WorkShift.self, from: Data("[5]".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(WorkShift.self, from: Data("\"x\"".utf8)))
    }

    func testAnUnreadableShiftIsSkippedAndTheRestStays() throws {
        let json = #"[[100,200],[5],"x",[300,250],[400,500],{"a":1},[600,700]]"#
        let list = try JSONDecoder().decode(LossyArray<WorkShift>.self, from: Data(json.utf8))
        XCTAssertEqual(list.elements.map { [$0.startMinute, $0.endMinute] }, [[100, 200], [400, 500], [600, 700]])
        let empty = try JSONDecoder().decode(LossyArray<WorkShift>.self, from: Data("[]".utf8))
        XCTAssertTrue(empty.elements.isEmpty)
    }

    // MARK: Samenvoegen

    func testNormalizedSortsRemovesDuplicatesAndMergesOverlap() {
        let messy = [shift(500, 600), shift(100, 300), shift(200, 400), shift(100, 300), shift(550, 580), shift(900, 1000)]
        let merged = WorkShift.normalized(messy)
        XCTAssertEqual(merged.map { [$0.startMinute, $0.endMinute] }, [[100, 400], [500, 600], [900, 1000]])
        XCTAssertEqual(WorkShift.normalized([]), [])
        XCTAssertEqual(WorkShift.normalized([shift(1, 2)]), [shift(1, 2)])
    }

    func testShiftsThatOnlyTouchStayTwoShifts() {
        let list = WorkShift.normalized([shift(100, 200), shift(200, 300)])
        XCTAssertEqual(list.count, 2, "het einde van de ene is het begin van de volgende: geen overlap")
        XCTAssertEqual(WorkShift.normalized([shift(100, 200), shift(199, 300)]).count, 1, "een minuut overlap is overlap")
        XCTAssertEqual(WorkShift.normalized([shift(100, 500), shift(200, 300)]).map { $0.endMinute }, [500], "een dienst binnen een andere")
    }

    func testNormalizedIsIdempotentNeverOverlapsAndKeepsTheCoveredMinutes() {
        var r = EngRandom(seed: 5_150)
        for round in 0..<200 {
            let shifts = (0..<r.int(0...12)).compactMap { _ -> WorkShift? in
                let start = r.int(0...2_000)
                return WorkShift(startMinute: start, endMinute: start + r.int(1...400))
            }
            let once = WorkShift.normalized(shifts)
            XCTAssertEqual(WorkShift.normalized(once), once, "ronde \(round)")
            for (a, b) in zip(once, once.dropFirst()) { XCTAssertLessThanOrEqual(a.endMinute, b.startMinute, "geen overlap, ronde \(round)") }
            // Dezelfde minuten blijven bedekt.
            var covered = Set<Int>()
            for s in shifts { for m in s.startMinute..<s.endMinute { covered.insert(m) } }
            var after = Set<Int>()
            for s in once { for m in s.startMinute..<s.endMinute { after.insert(m) } }
            XCTAssertEqual(covered, after, "ronde \(round)")
        }
    }

    // MARK: Per kalenderdag

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testPiecesSplitAtMidnight() {
        let cal = utcCalendar()
        let night = engShift(engDate(cal, 2026, 11, 1, 22), engDate(cal, 2026, 11, 2, 6))
        let pieces = night.pieces(calendar: cal)
        XCTAssertEqual(pieces.map { $0.minutes }, [120, 360])
        XCTAssertEqual(pieces.map { $0.day }, [CalendarDay(year: 2026, month: 11, day: 1), CalendarDay(year: 2026, month: 11, day: 2)])
        let day = engShift(engDate(cal, 2026, 11, 3, 9), engDate(cal, 2026, 11, 3, 17))
        XCTAssertEqual(day.pieces(calendar: cal).map { $0.minutes }, [480])
        let long = engShift(engDate(cal, 2026, 11, 3, 23, 30), engDate(cal, 2026, 11, 5, 0, 30))
        XCTAssertEqual(long.pieces(calendar: cal).map { $0.minutes }, [30, 1_440, 30], "drie dagen, de middelste hele")
        let endsAtMidnight = engShift(engDate(cal, 2026, 11, 3, 20), engDate(cal, 2026, 11, 4, 0))
        XCTAssertEqual(endsAtMidnight.pieces(calendar: cal).map { $0.minutes }, [240], "een dienst tot middernacht heeft geen stuk op de volgende dag")
    }

    func testTheTwentyFiveHourDayAtTheEndOfDaylightSaving() throws {
        let cal = try XCTUnwrap(engAmsterdamCalendar(), "tijdzone Europe/Amsterdam ontbreekt")
        // Za 25 oktober 2025 22:00 tot zo 26 oktober 06:00: de klok gaat die nacht een uur terug, dus 9 uur verstreken.
        let night = engShift(engDate(cal, 2025, 10, 25, 22), engDate(cal, 2025, 10, 26, 6))
        XCTAssertEqual(night.durationMinutes, 540)
        XCTAssertEqual(night.pieces(calendar: cal).map { $0.minutes }, [120, 420])
        XCTAssertEqual(night.pieces(calendar: cal).map { $0.day.weekday }, [7, 1], "zaterdag en zondag")
        // De hele dag van 25 uur.
        let whole = engShift(engDate(cal, 2025, 10, 26, 0), engDate(cal, 2025, 10, 27, 0))
        XCTAssertEqual(whole.durationMinutes, 1_500)
        XCTAssertEqual(whole.pieces(calendar: cal).map { $0.minutes }, [1_500])
    }

    func testTheTwentyThreeHourDayAtTheStartOfDaylightSaving() throws {
        let cal = try XCTUnwrap(engAmsterdamCalendar(), "tijdzone Europe/Amsterdam ontbreekt")
        let night = engShift(engDate(cal, 2026, 3, 28, 22), engDate(cal, 2026, 3, 29, 6))
        XCTAssertEqual(night.durationMinutes, 420, "de klok gaat een uur vooruit")
        XCTAssertEqual(night.pieces(calendar: cal).map { $0.minutes }, [120, 300])
        let whole = engShift(engDate(cal, 2026, 3, 29, 0), engDate(cal, 2026, 3, 30, 0))
        XCTAssertEqual(whole.pieces(calendar: cal).map { $0.minutes }, [1_380])
    }

    func testPiecesAlwaysAddUpToTheDurationAroundDaylightSaving() throws {
        let cal = try XCTUnwrap(engAmsterdamCalendar(), "tijdzone Europe/Amsterdam ontbreekt")
        var r = EngRandom(seed: 25_231)
        let anchors = [engDate(cal, 2025, 10, 24), engDate(cal, 2026, 3, 27), engDate(cal, 2026, 10, 24), engDate(cal, 2027, 3, 26)]
        for round in 0..<400 {
            let begin = anchors[round % anchors.count].addingTimeInterval(Double(r.int(0...(5 * 24 * 60))) * 60)
            let made = engShift(begin, begin.addingTimeInterval(Double(r.int(1...(30 * 60))) * 60))
            let pieces = made.pieces(calendar: cal)
            XCTAssertEqual(pieces.reduce(0) { $0 + $1.minutes }, made.durationMinutes, "ronde \(round)")
            XCTAssertTrue(pieces.allSatisfy { $0.minutes > 0 && $0.minutes <= 1_500 })
            let days = pieces.map { $0.day.dayNumber }
            XCTAssertEqual(days, Array(days.first!...days.last!), "opeenvolgende dagen, ronde \(round)")
        }
    }

    // MARK: Verdelen

    func testDistributeGivesTheLargestRemainderTheExtraMinuteAndTheEarliestOnATie() {
        XCTAssertEqual(WorkMath.distribute(30, over: [120, 420]), [7, 23], "30 minuten pauze over 2 en 7 uur")
        XCTAssertEqual(WorkMath.distribute(1, over: [1, 1, 1]), [1, 0, 0], "gelijke rest: eerst het vroegste deel")
        XCTAssertEqual(WorkMath.distribute(2, over: [1, 1, 1]), [1, 1, 0])
        XCTAssertEqual(WorkMath.distribute(10, over: [10]), [10])
        XCTAssertEqual(WorkMath.distribute(30, over: [300, 300]), [15, 15])
    }

    func testDistributeWithNothingToDistributeGivesZeros() {
        XCTAssertEqual(WorkMath.distribute(0, over: [5, 5]), [0, 0])
        XCTAssertEqual(WorkMath.distribute(10, over: [0, 0]), [0, 0])
        XCTAssertEqual(WorkMath.distribute(-3, over: [4, 4]), [0, 0])
        XCTAssertEqual(WorkMath.distribute(5, over: []), [])
    }

    func testDistributeAlwaysAddsUpAndFollowsTheProportions() {
        var r = EngRandom(seed: 777)
        for round in 0..<500 {
            let parts = (0..<r.int(1...4)).map { _ in r.int(1...1_500) }
            let total = r.int(0...600)
            let shares = WorkMath.distribute(total, over: parts)
            XCTAssertEqual(shares.reduce(0, +), total, "ronde \(round)")
            XCTAssertEqual(shares.count, parts.count)
            let sum = parts.reduce(0, +)
            for (index, share) in shares.enumerated() {
                let exact = Double(total) * Double(parts[index]) / Double(sum)
                XCTAssertTrue(abs(Double(share) - exact) < 1, "ronde \(round): \(share) tegenover \(exact)")
            }
        }
    }
}
