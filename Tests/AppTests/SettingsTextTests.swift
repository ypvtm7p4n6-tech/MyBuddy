import XCTest
import UniformTypeIdentifiers
@testable import MyBuddy

/// De teksten en hulpmiddelen van Instellingen en Account die zonder scherm te testen zijn: de status onder de Account-rij,
/// de waarden onder de rijen, de versie, de importmaanden, de `ImportCoordinator` en de typen van `ExportDocument`.
@MainActor
final class SettingsTextTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// 15 januari 2027, 08:00 UTC.
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Tijd

    func testTimeHasNoLeadingZeroForTheHour() {
        XCTAssertEqual(SettingsText.time(base, timeZone: utc), "8:00")
        let afternoon = base.addingTimeInterval(6 * 3600 + 2 * 60)
        XCTAssertEqual(SettingsText.time(afternoon, timeZone: utc), "14:02")
    }

    func testMomentOfTheSameDayIsOnlyTheTime() {
        let later = base.addingTimeInterval(3600)
        XCTAssertEqual(SettingsText.moment(base, now: later, timeZone: utc), "om 8:00")
    }

    // MARK: Synchronisatie

    func testWithoutFirebaseKeyTheAccountIsOnlyOnThisDevice() {
        let summary = SettingsText.syncSummary(isConfigured: false, status: nil, needsAttention: false)
        XCTAssertEqual(summary.text, "Alleen op dit apparaat")
        XCTAssertFalse(summary.needsAttention)
        XCTAssertNil(summary.symbol)
    }

    func testAttentionIsActionNeededWithWarningSymbol() {
        let summary = SettingsText.syncSummary(isConfigured: true, status: .offline, needsAttention: true)
        XCTAssertEqual(summary.text, "Actie nodig")
        XCTAssertTrue(summary.needsAttention)
        XCTAssertEqual(summary.symbol, "exclamationmark.triangle.fill")
    }

    func testConflictStatusNeedsAttentionEvenWithoutTheFlag() {
        let summary = SettingsText.syncSummary(isConfigured: true, status: .conflict, needsAttention: false)
        XCTAssertEqual(summary.text, "Actie nodig")
        XCTAssertTrue(summary.needsAttention)
    }

    func testSyncedStatusNamesTheTimeOfTheSameDay() {
        let summary = SettingsText.syncSummary(isConfigured: true, status: .synced(at: base), needsAttention: false,
                                               now: base.addingTimeInterval(60), timeZone: utc)
        XCTAssertEqual(summary.text, "Gesynchroniseerd om 8:00")
        XCTAssertFalse(summary.needsAttention)
    }

    func testOtherStatuses() {
        func text(_ status: SyncStatus?) -> String {
            SettingsText.syncSummary(isConfigured: true, status: status, needsAttention: false).text
        }
        XCTAssertEqual(text(nil), "Synchronisatie niet actief")
        XCTAssertEqual(text(.disabled), "Synchronisatie staat uit")
        XCTAssertEqual(text(.connecting), "Verbinden…")
        XCTAssertEqual(text(.busy), "Bezig met synchroniseren…")
        XCTAssertEqual(text(.offline), "Offline")
        XCTAssertEqual(text(.failed("geen verbinding")), "Synchroniseren mislukt")
    }

    // MARK: Waarden onder de rijen

    func testCalculationsSummary() {
        XCTAssertEqual(SettingsText.calculationsSummary(inflation: 0.02, savingsRate: 0.025), "Inflatie 2%, spaarrente 2,5%")
    }

    func testPricesSummary() {
        XCTAssertEqual(SettingsText.pricesSummary(automatic: false, lastRefresh: nil, now: base, timeZone: utc), "Handmatig")
        XCTAssertEqual(SettingsText.pricesSummary(automatic: true, lastRefresh: nil, now: base, timeZone: utc), "Automatisch")
        XCTAssertEqual(SettingsText.pricesSummary(automatic: true, lastRefresh: base, now: base, timeZone: utc),
                       "Automatisch, laatst bijgewerkt 8:00")
    }

    // MARK: Versie

    func testVersionText() {
        XCTAssertEqual(SettingsText.versionText(short: "2.1"), "Versie 2.1")
        XCTAssertEqual(SettingsText.versionText(short: nil), "Versie 1.0")
        XCTAssertEqual(SettingsText.versionText(short: ""), "Versie 1.0")
        XCTAssertEqual(SettingsText.detailedVersionText(short: "1.0", build: "7"), "Versie 1.0 (7)")
        XCTAssertEqual(SettingsText.detailedVersionText(short: "1.0", build: "1.0"), "Versie 1.0")
        XCTAssertEqual(SettingsText.detailedVersionText(short: "1.0", build: nil), "Versie 1.0")
    }

    // MARK: Importeren en exporteren

    func testImportMonthsRunFromTheStartMonthToAYearAhead() {
        let current = YearMonth(year: 2026, month: 10)
        let options = ImportMonths.options(start: current.adding(-2), current: current)
        XCTAssertEqual(options.count, 15)
        XCTAssertEqual(options.first, current.adding(-2))
        XCTAssertEqual(options.last, current.adding(12))
    }

    func testImportMonthsGoBackAtMostThreeYears() {
        let current = YearMonth(year: 2026, month: 10)
        XCTAssertEqual(ImportMonths.options(start: current.adding(-100), current: current).first, current.adding(-36))
        XCTAssertEqual(ImportMonths.options(start: current.adding(5), current: current).first, current)
    }

    func testImportCoordinatorHoldsAndClearsTheDraft() {
        let coordinator = ImportCoordinator()
        XCTAssertFalse(coordinator.hasDraft)
        let current = YearMonth(year: 2026, month: 10)
        coordinator.prepare(draft: ImportDraft(fileName: "begroting.xlsx"), initialMonth: current, monthOptions: [current])
        XCTAssertTrue(coordinator.hasDraft)
        XCTAssertEqual(coordinator.draft?.fileName, "begroting.xlsx")
        XCTAssertEqual(coordinator.initialMonth, current)
        coordinator.reset()
        XCTAssertFalse(coordinator.hasDraft)
        XCTAssertTrue(coordinator.monthOptions.isEmpty)
    }

    func testExportDocumentWritesJSONCSVAndExcel() {
        let types = ExportDocument.writableContentTypes
        XCTAssertTrue(types.contains(UTType.json))
        XCTAssertTrue(types.contains(UTType.commaSeparatedText))
        XCTAssertTrue(types.contains(BackupFileTypes.xlsx))
        XCTAssertEqual(ExportDocument.readableContentTypes, types)
    }

    func testCSVReportsHaveAnExplanationAndSymbol() {
        for report in CSVReport.allCases {
            XCTAssertFalse(report.detail.isEmpty)
            XCTAssertFalse(report.symbol.isEmpty)
        }
    }

    // MARK: Pagina's

    func testEverySettingsPageHasATitleAndSymbol() {
        for page in SettingsPage.allCases {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.symbol.isEmpty)
        }
    }
}
