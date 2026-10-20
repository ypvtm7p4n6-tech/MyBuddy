import XCTest
@testable import MyBuddyCore

/// De as-logica van alle grafieken (`ChartAxis`, `ChartText`): het domein is altijd eindig en `lo < hi` (een omgekeerd bereik laat
/// Swift crashen), de y-labels zijn nooit twee keer gelijk naast elkaar, de uitdunning houdt het eerste en het laatste punt.
final class ChartAxisTests: XCTestCase {
    // MARK: Domein

    func testDomainIsAlwaysFiniteAndOrdered() {
        let cases: [[Double]] = [[], [0], [5, 5], [1_000, 1_000, 1_000], [.nan], [.infinity, -.infinity], [-250], [-250, -250],
                                 [1e300], [0.5, 0.51], [4.00, 4.33], [.nan, 3, 7]]
        for values in cases {
            for includeZero in [false, true] {
                for nonNegative in [false, true] {
                    let domain = ChartAxis.domain(values, includeZero: includeZero, nonNegative: nonNegative)
                    let label = "\(values) nul:\(includeZero) niet-negatief:\(nonNegative)"
                    XCTAssertTrue(domain.lowerBound.isFinite && domain.upperBound.isFinite, label)
                    XCTAssertLessThan(domain.lowerBound, domain.upperBound, label)
                }
            }
        }
    }

    func testDomainOfAFlatSeriesHasRoomAroundIt() {
        let flat = ChartAxis.domain([1_000, 1_000])
        XCTAssertEqual(flat.lowerBound, 950, accuracy: 0.001)
        XCTAssertEqual(flat.upperBound, 1_050, accuracy: 0.001)
        // Een vlakke reeks op 0 krijgt minstens 1 euro ruimte.
        let zero = ChartAxis.domain([0, 0])
        XCTAssertEqual(zero.lowerBound, -1, accuracy: 0.001)
        XCTAssertEqual(zero.upperBound, 1, accuracy: 0.001)
    }

    func testDomainWithNonNegativeNeverGoesBelowZeroAndIncludeZeroStartsAtZero() {
        XCTAssertEqual(ChartAxis.domain([10, 20], nonNegative: true).lowerBound, 9.2, accuracy: 0.001)
        XCTAssertEqual(ChartAxis.domain([0, 20], nonNegative: true).lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(ChartAxis.domain([50, 100], includeZero: true).lowerBound, 0, accuracy: 0.001)
        // Met negatieve waarden en `includeZero` loopt het domein onder 0.
        XCTAssertLessThan(ChartAxis.domain([-50, 100], includeZero: true).lowerBound, -50)
    }

    func testNonFiniteValuesDoNotCount() {
        let domain = ChartAxis.domain([.nan, 100, .infinity, 200])
        XCTAssertEqual(domain.lowerBound, 92, accuracy: 0.001)
        XCTAssertEqual(domain.upperBound, 208, accuracy: 0.001)
    }

    // MARK: Ticks en y-labels

    func testTicksStayInsideTheDomainAndAscend() {
        let domains: [ClosedRange<Double>] = [0...1, 950...1_050, 7_000...12_573, -300...300, 4.0...4.4, 0.495...0.515, 0...1_000_000]
        for domain in domains {
            for count in [3, 4, 5] {
                let ticks = ChartAxis.ticks(in: domain, count: count)
                XCTAssertFalse(ticks.isEmpty, "\(domain)")
                XCTAssertLessThanOrEqual(ticks.count, 12)
                for tick in ticks {
                    XCTAssertGreaterThanOrEqual(tick, domain.lowerBound - 1e-9, "\(domain)")
                    XCTAssertLessThanOrEqual(tick, domain.upperBound + 1e-9, "\(domain)")
                }
                XCTAssertEqual(ticks, ticks.sorted(), "\(domain)")
            }
        }
    }

    /// De acht gevallen uit charts.md 6.4: overal unieke labels en `lo < hi`.
    func testYLabelsAreUniqueForTheEightCases() {
        let cases: [(name: String, values: [Double])] = [
            ("b1b: 1.000 tot 1.050", [1_000, 1_050]),
            ("koers 4,00 tot 4,33", [4.00, 4.33]),
            ("koers 0,50 tot 0,51", [0.50, 0.51]),
            ("vlak 0", [0, 0]),
            ("vlak 1.000", [1_000, 1_000, 1_000]),
            ("negatief", [-300, -250, -250]),
            ("normaal", [7_350, 8_966, 12_573]),
            ("met NaN en oneindig", [.nan, 3_000, .infinity, 3_600])
        ]
        for item in cases {
            let domain = ChartAxis.domain(item.values)
            XCTAssertLessThan(domain.lowerBound, domain.upperBound, item.name)
            for count in [3, 4] {
                let ticks = ChartAxis.ticks(in: domain, count: count)
                let labels = ChartAxis.yLabels(ticks)
                XCTAssertEqual(labels.count, ticks.count, item.name)
                XCTAssertEqual(Set(labels).count, labels.count, "dubbele labels bij \(item.name): \(labels)")
            }
        }
    }

    func testYLabelsAreShortWhenTheyCanBeAndHaveCentsWhenNeeded() {
        XCTAssertEqual(ChartAxis.yLabels([8_000, 10_000, 12_000]), ["€8k", "€10k", "€12k"])
        XCTAssertEqual(ChartAxis.yLabels([0, 500, 1_000]).first, "€0")
        // Onder 10.000 liever hele euro's dan "€1k, €1k".
        XCTAssertEqual(ChartAxis.yLabels([1_000, 1_020, 1_040, 1_060]), ["€1.000", "€1.020", "€1.040", "€1.060"])
        // Onder 1 euro tickafstand komen er centen bij.
        let cents = ChartAxis.yLabels([4.0, 4.1, 4.2, 4.3])
        XCTAssertEqual(Set(cents).count, 4)
        XCTAssertTrue(cents.allSatisfy { $0.contains(",") }, "\(cents)")
        XCTAssertEqual(ChartAxis.yLabels([-2_000, 0, 2_000]), ["-€2k", "€0", "€2k"])
    }

    // MARK: X-as

    func testMonthStride() {
        XCTAssertEqual([0, 1, 7].map { ChartAxis.monthStride(span: $0) }, [1, 1, 1])
        XCTAssertEqual([8, 14].map { ChartAxis.monthStride(span: $0) }, [2, 2])
        XCTAssertEqual([15, 26].map { ChartAxis.monthStride(span: $0) }, [3, 3])
        XCTAssertEqual([27, 50].map { ChartAxis.monthStride(span: $0) }, [6, 6])
        XCTAssertEqual([51, 120].map { ChartAxis.monthStride(span: $0) }, [12, 12])
    }

    func testMonthLabelShowsTheYearInJanuary() {
        XCTAssertEqual(ChartAxis.monthLabel(oct2026.firstDay), "okt")
        XCTAssertEqual(ChartAxis.monthLabel(YearMonth(year: 2027, month: 1).firstDay), "jan '27")
    }

    func testMonthTicksAreAlignedOnTheCalendarAndNeverEmpty() {
        // 13 maanden: om de 2 maanden, vast op januari, maart, mei, ...
        let ticks = ChartAxis.monthTicks(from: oct2026.firstDay, to: oct2026.adding(12).firstDay)
        XCTAssertFalse(ticks.isEmpty)
        for tick in ticks { XCTAssertEqual((YearMonth(date: tick).month - 1) % 2, 0) }
        // Kort venster: elke maand.
        let short = ChartAxis.monthTicks(from: oct2026.firstDay, to: oct2026.adding(3).firstDay)
        XCTAssertEqual(short.count, 4)
        // Een enkel punt geeft toch een label.
        XCTAssertEqual(ChartAxis.monthTicks(from: oct2026.firstDay, to: oct2026.firstDay), [oct2026.firstDay])
        // Drie jaar: januari en juli. Vijf jaar: alleen januari.
        let long = ChartAxis.monthTicks(from: oct2026.firstDay, to: oct2026.adding(36).firstDay)
        XCTAssertTrue(long.allSatisfy { [1, 7].contains(YearMonth(date: $0).month) })
        let veryLong = ChartAxis.monthTicks(from: oct2026.firstDay, to: oct2026.adding(60).firstDay)
        XCTAssertTrue(veryLong.allSatisfy { YearMonth(date: $0).month == 1 })
    }

    func testDayTicksStartOnTheFirstDay() {
        let from = day(oct2026, 15)
        let to = day(oct2026, 15).addingTimeInterval(29 * 86_400)
        let ticks = ChartAxis.dayTicks(from: from, to: to)
        XCTAssertEqual(ticks.first, YearMonth.calendar.startOfDay(for: from))
        XCTAssertLessThanOrEqual(ticks.count, 12)
        XCTAssertGreaterThanOrEqual(ticks.count, 4)
        XCTAssertEqual(ChartAxis.dayTicks(from: from, to: from).count, 1)
    }

    func testElapsedDateRoundTrip() {
        for x in [0.0, 0.5, 10, 36.25, 1_200] {
            XCTAssertEqual(ChartAxis.elapsedValue(ChartAxis.elapsedDate(x)), x, accuracy: 1e-6)
        }
        XCTAssertEqual(ChartAxis.elapsedValue(ChartAxis.elapsedDate(.nan)), 0, accuracy: 1e-9)
    }

    // MARK: Uitdunnen

    func testDownsampleKeepsTheFirstAndTheLastPoint() {
        for count in [0, 1, 2, 3, 50, 100, 101, 120, 121, 405, 406, 501, 1_201] {
            let items = Array(0..<count)
            let thinned = ChartAxis.downsample(items, limit: 100)
            XCTAssertLessThanOrEqual(thinned.count, count <= 100 ? count : 101, "\(count)")
            if count > 0 {
                XCTAssertEqual(thinned.first, 0, "\(count)")
                XCTAssertEqual(thinned.last, count - 1, "\(count)")
            }
            XCTAssertEqual(thinned, thinned.sorted(), "\(count)")
            XCTAssertEqual(Set(thinned).count, thinned.count, "\(count)")
        }
        XCTAssertEqual(ChartAxis.downsample([1, 2, 3], limit: 100), [1, 2, 3])
    }

    // MARK: Teksten

    func testChartTextForVoiceOver() {
        XCTAssertEqual(ChartText.euro(8_966), "8.966 euro")
        XCTAssertEqual(ChartText.euro(0), "0 euro")
        XCTAssertEqual(ChartText.euro(-0.0), "0 euro")
        XCTAssertEqual(ChartText.euro(12.5), "12,5 euro")
        XCTAssertEqual(ChartText.price(105.36), "105,36 euro")
        XCTAssertEqual(ChartText.signedEuro(1_616), "plus 1.616 euro")
        XCTAssertEqual(ChartText.signedEuro(-120), "min 120 euro")
        XCTAssertEqual(ChartText.number(10_830), "10.830")
        XCTAssertEqual(ChartText.monthTitle(oct2026), "Oktober 2026")
        XCTAssertEqual(ChartText.capitalized(""), "")
        XCTAssertEqual(ChartText.lowercasedFirst("Doel bereikt"), "doel bereikt")
        XCTAssertTrue(ChartText.signedWhole(1_616).hasPrefix("+"))
        XCTAssertTrue(ChartText.signedWhole(-120).hasPrefix("−"))
    }

    func testChartSizesAreTheThreeFixedHeights() {
        XCTAssertEqual([ChartSize.compact, .regular, .tall].map { $0.height }, [96, 180, 240])
    }
}
