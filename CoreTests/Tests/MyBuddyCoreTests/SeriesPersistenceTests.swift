import XCTest
import Foundation
@testable import MyBuddyCore

// Opslaan en inlezen van de nieuwe velden (terugkerende reeksen en percentage-inleg): oude bestanden zonder die velden
// laden exact gelijk en worden niet anders weggeschreven; de nieuwe velden overleven het bestand (compact en opgemaakt),
// de back-up en de cloud-envelop; en een kapot of onvolledig nieuw veld breekt het laden niet.

/// Alle sleutels die er met deze functies bij zijn gekomen.
private let newKeys: Set<String> = ["seriesID", "isException", "percentAllocations", "skippedSeries", "endedSeries",
                                    "contributionMode", "contributionPercent", "contributionBasis"]

private func allKeys(in object: Any) -> Set<String> {
    var keys = Set<String>()
    if let dict = object as? [String: Any] {
        for (key, value) in dict {
            keys.insert(key)
            keys.formUnion(allKeys(in: value))
        }
    } else if let list = object as? [Any] {
        for item in list { keys.formUnion(allKeys(in: item)) }
    }
    return keys
}

/// Een bestand zoals de app het schreef voordat er reeksen en percentages waren: vaste id's, geen enkel nieuw veld.
private let oldFileJSON = """
{
  "version": 1,
  "startMonth": "2026-08",
  "salary": {"mode": "fixed", "fixedMonthly": 3000, "hourlyRate": 0, "hoursPerWeek": 0, "payDay": 25},
  "pots": [
    {"id": "5F2A8B0C-1111-4C4C-9999-000000000001", "name": "Buffer", "symbol": "banknote", "colorIndex": 0,
     "monthlyContribution": 200, "startMonth": "2026-08", "createdAt": "2026-08-01T10:00:00Z",
     "interestRate": 0, "interestPayout": "yearly", "interestPayoutDay": 1, "interestPayoutMonth": 1}
  ],
  "holdings": [
    {"id": "5F2A8B0C-2222-4C4C-9999-000000000002", "name": "ETF", "kind": "etf", "investedTotal": 0, "expectedReturn": 0.06,
     "annualCost": 0.002, "monthlyContribution": 100, "startMonth": "2026-08", "snapshots": []}
  ],
  "months": {
    "2026-08": {
      "extraIncome": [{"id": "5F2A8B0C-3333-4C4C-9999-000000000003", "name": "Toeslag", "amount": 120, "isRecurring": true,
                       "kind": "fixed", "day": 20, "potShares": []}],
      "expenses": [{"id": "5F2A8B0C-4444-4C4C-9999-000000000004", "name": "Huur", "amount": 1000, "isRecurring": true,
                    "kind": "fixed", "day": 1, "potShares": []}],
      "allocations": {"5F2A8B0C-1111-4C4C-9999-000000000001": 200, "5F2A8B0C-2222-4C4C-9999-000000000002": 100}
    },
    "2026-09": {
      "extraIncome": [], "expenses": [], "salaryOverride": 3200,
      "allocations": {"5F2A8B0C-1111-4C4C-9999-000000000001": 250}
    }
  },
  "bankSnapshots": [], "bankEntries": [], "potEntries": [], "goals": [],
  "settings": {"inflation": 0.02, "defaultWithdrawalRate": 0.04, "bankBufferMonths": 2, "autoRefreshPrices": true, "savingsRate": 0.02}
}
"""

final class SeriesPersistenceTests: XCTestCase {
    private func decode(_ json: String) throws -> FinanceData {
        try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(json.utf8))
    }

    // MARK: Oude bestanden

    func testOldFileLoadsWithDefaultsForEveryNewField() throws {
        let d = try decode(oldFileJSON)
        XCTAssertEqual(d.pots[0].contributionMode, .fixed)
        XCTAssertEqual(d.pots[0].contributionPercent, 0)
        XCTAssertEqual(d.pots[0].contributionBasis, .salary)
        XCTAssertEqual(d.holdings[0].contributionMode, .fixed)
        XCTAssertEqual(d.holdings[0].contributionPercent, 0)
        XCTAssertEqual(d.holdings[0].contributionBasis, .salary)
        let august = try XCTUnwrap(d.months[aug2026.key])
        XCTAssertTrue(august.percentAllocations.isEmpty)
        XCTAssertTrue(august.skippedSeries.isEmpty)
        XCTAssertTrue(august.endedSeries.isEmpty)
        XCTAssertNil(august.expenses[0].seriesID)
        XCTAssertFalse(august.expenses[0].isException)
        XCTAssertTrue(august.expenses[0].isRecurring)
        // En het rekent zoals vroeger: 3000 + 120 - 1000 - 200 - 100.
        XCTAssertEqual(d.remaining(in: aug2026), 1_820, accuracy: 1e-9)
        XCTAssertEqual(d.remaining(in: sep2026), 3_200 + 120 - 1_000 - 250 - 100, accuracy: 1e-9)
        // De terugkerende regels komen in elke volgende maand terug (ook in de vastgelegde september, waar ze ontbreken).
        XCTAssertEqual(d.plan(for: sep2026).expenses.map(\.name), ["Huur"])
        XCTAssertEqual(d.expensesTotal(in: oct2026), 1_000, accuracy: 1e-9)
        XCTAssertEqual(d.income(in: YearMonth(year: 2030, month: 4)), 3_120, accuracy: 1e-9)
        XCTAssertEqual(d.allocation(d.pots[0].id, in: oct2026), 200)
        XCTAssertTrue(d.allocationWarnings(in: oct2026).isEmpty)
    }

    func testOldFileIsWrittenBackWithoutAnyNewKey() throws {
        let d = try decode(oldFileJSON)
        for encoder in [FinanceStorage.makeEncoder(), FinanceStorage.makeFileEncoder()] {
            let bytes = try encoder.encode(d)
            let object = try JSONSerialization.jsonObject(with: bytes)
            XCTAssertTrue(allKeys(in: object).isDisjoint(with: newKeys), "nieuwe sleutels: \(allKeys(in: object).intersection(newKeys))")
            XCTAssertEqual(try FinanceStorage.makeDecoder().decode(FinanceData.self, from: bytes), d)
        }
        // Ook na `materialize` (dat de reeks-id's wegschrijft) en een gewone bewerking blijft er geen percentage in staan.
        var worked = d
        worked.setAllocation(worked.pots[0].id, in: oct2026, amount: 300)
        let object = try JSONSerialization.jsonObject(with: FinanceStorage.makeFileEncoder().encode(worked))
        XCTAssertTrue(allKeys(in: object).isDisjoint(with: ["percentAllocations", "skippedSeries", "endedSeries", "contributionMode",
                                                            "contributionPercent", "contributionBasis", "isException"]))
    }

    func testOldFileEncodesToTheSameBytesAsBeforeTheNewFields() throws {
        // Dezelfde gegevens opgebouwd zonder nieuwe velden en met: de uitvoer is byte voor byte gelijk.
        let d = try decode(oldFileJSON)
        let once = try FinanceStorage.makeFileEncoder().encode(d)
        let twice = try FinanceStorage.makeFileEncoder().encode(try decode(String(decoding: once, as: UTF8.self)))
        XCTAssertEqual(once, twice)
        let pretty = try FinanceStorage.makeEncoder().encode(d)
        XCTAssertEqual(pretty, try FinanceStorage.makeEncoder().encode(try decode(String(decoding: pretty, as: UTF8.self))))
    }

    func testPartlyFilledNewFieldsAreLenient() throws {
        let json = """
        {"startMonth":"2026-08","pots":[{"id":"5F2A8B0C-1111-4C4C-9999-000000000001","name":"Spaar","startMonth":"2026-08",
          "monthlyContribution":0,"contributionMode":"percentage","contributionPercent":12.5}],
         "months":{"2026-08":{"extraIncome":[],"expenses":[
           {"id":"5F2A8B0C-4444-4C4C-9999-000000000004","name":"Huur","amount":1000,"isRecurring":true,
            "seriesID":"5F2A8B0C-4444-4C4C-9999-000000000004"}],
           "allocations":{},"percentAllocations":{"5F2A8B0C-1111-4C4C-9999-000000000001":{"percent":20}}}}}
        """
        let d = try decode(json)
        XCTAssertEqual(d.pots[0].contributionMode, .percentage)
        XCTAssertEqual(d.pots[0].contributionPercent, 12.5)
        XCTAssertEqual(d.pots[0].contributionBasis, .salary, "grondslag ontbreekt: alleen salaris")
        let plan = try XCTUnwrap(d.months[aug2026.key])
        XCTAssertEqual(plan.percentAllocations[d.pots[0].id.uuidString], PercentRule(percent: 20, basis: .salary))
        XCTAssertFalse(plan.expenses[0].isException)
        XCTAssertEqual(plan.expenses[0].seriesID, plan.expenses[0].id)
        XCTAssertEqual(try decode(#"{"startMonth":"2026-08","months":{"2026-08":{"percentAllocations":{}}}}"#).months.count, 1)
    }

    // MARK: Nieuwe velden overleven

    /// Gegevens waarin alles zit wat er nieuw is: reeksen met afwijkende, overgeslagen en gestopte maanden, potten en
    /// beleggingen met een percentage (beide grondslagen) en een maand met een eigen percentage en een eigen bedrag.
    private func richData() -> FinanceData {
        var d = recEmptyData()
        var pot = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: aug2026)
        pot.createdAt = Date(timeIntervalSince1970: 1_790_000_000)
        pot.contributionMode = .percentage
        pot.contributionPercent = 12.5
        pot.contributionBasis = .allIncome
        d.addPot(pot, openingBalance: 250, now: day(aug2026, 1))
        var holding = Holding(name: "ETF", kind: .etf, monthlyContribution: 40, startMonth: aug2026)
        holding.contributionMode = .percentage
        holding.contributionPercent = 7.25
        holding.contributionBasis = .salary
        d.addHolding(holding)
        d.materialize(upTo: oct2026)
        d.addRecurringLine(MoneyLine(name: "Sportschool", amount: 40, isRecurring: true, day: 31), kind: .expense, in: oct2026)
        d.addRecurringLine(MoneyLine(name: "Toeslag", amount: 120, isRecurring: true, day: 20), kind: .income, in: oct2026)
        d.addRecurringLine(MoneyLine(name: "Krant", amount: 15, isRecurring: true, day: 3), kind: .expense, in: oct2026)
        var special = d.plan(for: recDec2026).expenses.first { $0.name == "Sportschool" }!
        special.amount = 55
        d.upsertLine(special, kind: .expense, in: recDec2026, scope: .thisMonth)
        d.deleteLine(id: d.plan(for: recJan2027).expenses.first { $0.name == "Sportschool" }!.id, kind: .expense, in: recJan2027,
                     scope: .thisMonth)
        d.deleteLine(id: d.plan(for: recMar2027).expenses.first { $0.name == "Krant" }!.id, kind: .expense, in: recMar2027)
        d.setAllocationPercent(pot.id, in: recNov2026, percent: 20, basis: .salary)
        d.setAllocation(holding.id, in: recNov2026, amount: 75)
        return d
    }

    func testNewFieldsSurviveEveryWayOfStoring() throws {
        let d = richData()
        // De gegevens bevatten echt alles wat nieuw is.
        let keys = allKeys(in: try JSONSerialization.jsonObject(with: FinanceStorage.makeEncoder().encode(d)))
        XCTAssertTrue(newKeys.isSubset(of: keys), "ontbrekend in de gegevens: \(newKeys.subtracting(keys))")

        let figures = aug2026.range(count: 30).map { d.monthFigures($0) }
        let plans = aug2026.range(count: 30).map { d.plan(for: $0) }

        func check(_ back: FinanceData, _ label: String) {
            XCTAssertEqual(back, d, label)
            XCTAssertEqual(aug2026.range(count: 30).map { back.monthFigures($0) }, figures, label)
            XCTAssertEqual(aug2026.range(count: 30).map { back.plan(for: $0) }, plans, label)
            XCTAssertEqual(back.pots[0].contributionBasis, .allIncome, label)
            XCTAssertEqual(back.pots[0].contributionPercent, 12.5, label)
            XCTAssertEqual(back.holdings[0].contributionPercent, 7.25, label)
        }

        // Het lokale bestand (compact), de opgemaakte vorm, de gewone JSON-codering.
        check(try FinanceStorage.makeDecoder().decode(FinanceData.self, from: FinanceStorage.makeFileEncoder().encode(d)), "bestand")
        check(try FinanceStorage.makeDecoder().decode(FinanceData.self, from: FinanceStorage.makeEncoder().encode(d)), "opgemaakt")
        check(try JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(d)), "gewoon")
        // De back-up.
        let backup = try BackupService.export(d, now: Date(timeIntervalSince1970: 1_790_000_000))
        check(try BackupService.importBackup(backup), "back-up")
        XCTAssertEqual(try BackupService.inspect(backup).potCount, 1)
        // De cloud-envelop (JSON-tekst in een document).
        let snapshot = try RemoteSnapshot(finance: d, modifiedAt: Date(timeIntervalSince1970: 1_790_000_000), device: "test")
        check(try snapshot.decodeFinance(), "cloud")
        // Een kopie in het geheugen telt als gelijk, ook met een andere tussenopslag.
        var copy = d
        _ = copy.storedPlans
        XCTAssertEqual(copy, d)
        copy.months[oct2026.key] = d.months[oct2026.key]
        XCTAssertEqual(copy, d)
    }

    func testSyncDetectsAChangedPercentageOrGravestone() throws {
        let d = richData()
        XCTAssertTrue(CloudSync.contentEqual(d, d))
        var other = d
        other.pots[0].contributionPercent = 12.75
        XCTAssertFalse(CloudSync.contentEqual(d, other))
        XCTAssertNotEqual(CloudSync.contentDigest(d), CloudSync.contentDigest(other))
        var stopped = d
        stopped.deleteLine(id: stopped.plan(for: recFeb2027).expenses.first { $0.name == "Sportschool" }!.id, kind: .expense,
                           in: recFeb2027)
        XCTAssertFalse(CloudSync.contentEqual(d, stopped))
        XCTAssertNotEqual(CloudSync.contentDigest(d), CloudSync.contentDigest(stopped))
        XCTAssertTrue(CloudSync.hasContent(d))
    }

    func testBackupOfAnOldFileStillImports() throws {
        let envelope = """
        {"format":"mybuddy-backup","version":1,"exportedAt":"2026-10-01T10:00:00Z","appVersion":"1.0","data":\(oldFileJSON)}
        """
        let d = try BackupService.importBackup(Data(envelope.utf8))
        XCTAssertEqual(d.remaining(in: aug2026), 1_820, accuracy: 1e-9)
        XCTAssertEqual(try BackupService.inspect(Data(envelope.utf8)).potCount, 1)
    }

    // MARK: Elke apart nieuw type

    func testNewTypesRoundTripAndKeepTheirDefaultsOutOfTheFile() throws {
        let rule = PercentRule(percent: 33.33, basis: .allIncome)
        XCTAssertEqual(try JSONDecoder().decode(PercentRule.self, from: JSONEncoder().encode(rule)), rule)
        XCTAssertEqual(try JSONDecoder().decode(PercentRule.self, from: Data(#"{}"#.utf8)), PercentRule(percent: 0, basis: .salary))
        for mode in ContributionMode.allCases {
            XCTAssertEqual(try JSONDecoder().decode(ContributionMode.self, from: JSONEncoder().encode(mode)), mode)
        }
        for basis in IncomeBasis.allCases {
            XCTAssertEqual(try JSONDecoder().decode(IncomeBasis.self, from: JSONEncoder().encode(basis)), basis)
        }
        for scope in SeriesScope.allCases {
            XCTAssertEqual(try JSONDecoder().decode(SeriesScope.self, from: JSONEncoder().encode(scope)), scope)
        }
        XCTAssertEqual(SeriesScope.thisMonth.title, "Alleen deze maand")
        XCTAssertEqual(SeriesScope.thisAndFollowing.title, "Deze en alle volgende maanden")
        XCTAssertEqual(ContributionMode.fixed.title, "Vast bedrag")
        XCTAssertEqual(IncomeBasis.allIncome.title, "Alle inkomsten")

        // Een gewone regel schrijft geen reeks-velden; een reeksregel schrijft ze wel.
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MoneyLine(name: "Huur", amount: 1))) as? [String: Any]
        XCTAssertNil(plain?["seriesID"])
        XCTAssertNil(plain?["isException"])
        var series = MoneyLine(name: "Huur", amount: 1, isRecurring: true)
        series.seriesID = series.id
        series.isException = true
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(series)) as? [String: Any]
        XCTAssertEqual(object?["seriesID"] as? String, series.id.uuidString)
        XCTAssertEqual(object?["isException"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(MoneyLine.self, from: JSONEncoder().encode(series)), series)
    }
}
