import XCTest
@testable import MyBuddyCore

/// Tests voor de teksten van de albumpagina's van een spaarpot en een belegging en van hun lijstrijen (`SavingAlbumText`). Alle
/// getallen komen uit bestaande cijfers; hier staat alleen hoe ze als tekst bij elkaar staan.
final class SavingAlbumTextTests: XCTestCase {
    /// Een pot Vakantie die 100 per maand inlegt, met een salaris van 3000 (november 2026).
    private func makeData(percent: Bool) -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: engNov2026)
        d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3_000, hourlyRate: 0, hoursPerWeek: 0, payDay: 25)
        var pot = Pot(name: "Vakantie", monthlyContribution: 100, startMonth: engNov2026)
        d.addPot(pot, openingBalance: 0, now: engTime(engNov2026, 1, hour: 8))
        d.materialize(upTo: engNov2026)
        if percent {
            pot.contributionMode = .percentage
            pot.contributionPercent = 10
            pot.contributionBasis = .salary
            d.updatePot(pot, current: engNov2026)
        }
        return (d, pot)
    }

    // MARK: Ondertitel en feiten van een pot

    func testPotSubtitle() {
        XCTAssertEqual(SavingAlbumText.potSubtitle(goal: nil), "Spaarpot")
        XCTAssertEqual(SavingAlbumText.potSubtitle(goal: 0), "Spaarpot")
        XCTAssertEqual(SavingAlbumText.potSubtitle(goal: 2_400), "Spaarpot · doel " + Fmt.euro(2_400))
    }

    func testPotFactsWithAGoal() {
        let facts = SavingAlbumText.potFacts(balance: 1_032, goal: 2_400, progress: 0.43, interestRate: nil, contribution: nil)
        XCTAssertEqual(facts, ["43% van je doel · Nog " + Fmt.euro(1_368) + " te gaan"])
    }

    func testPotFactsWhenTheGoalIsReached() {
        let facts = SavingAlbumText.potFacts(balance: 2_500, goal: 2_400, progress: 1.04, interestRate: nil, contribution: nil)
        XCTAssertEqual(facts, ["104% van je doel · Doel bereikt"])
    }

    func testPotFactsWithoutAGoal() {
        XCTAssertEqual(SavingAlbumText.potFacts(balance: 300, goal: nil, progress: nil, interestRate: nil, contribution: nil),
                       ["Geen doel ingesteld"])
        // Een doel van nul telt als geen doel.
        XCTAssertEqual(SavingAlbumText.potFacts(balance: 300, goal: 0, progress: nil, interestRate: nil, contribution: nil),
                       ["Geen doel ingesteld"])
    }

    func testPotFactsListInterestAndContributionInThatOrder() {
        let facts = SavingAlbumText.potFacts(balance: 300, goal: nil, progress: nil, interestRate: 0.02,
                                             contribution: "Inleg " + Fmt.euro(100) + " deze maand")
        XCTAssertEqual(facts, ["Geen doel ingesteld", "2% rente per jaar", "Inleg " + Fmt.euro(100) + " deze maand"])
        // Rente met twee decimalen zoals elders in de app.
        let precise = SavingAlbumText.potFacts(balance: 300, goal: nil, progress: nil, interestRate: 0.0275, contribution: nil)
        XCTAssertEqual(precise.last, Fmt.percent(0.0275, digits: 2) + " rente per jaar")
    }

    // MARK: Inleg

    func testContributionFactForAFixedAmount() {
        let (d, pot) = makeData(percent: false)
        let info = ContributionInfo(d, id: pot.id, month: engNov2026)
        XCTAssertEqual(SavingAlbumText.contributionFact(info), "Inleg " + Fmt.euro(100) + " deze maand")
    }

    func testContributionFactForAPercentage() {
        let (d, pot) = makeData(percent: true)
        let info = ContributionInfo(d, id: pot.id, month: engNov2026)
        XCTAssertEqual(SavingAlbumText.contributionFact(info), "Inleg 10% van je salaris, " + Fmt.euro(300) + " deze maand")
    }

    func testContributionFactIsNilWithoutContributionOrInfo() {
        XCTAssertNil(SavingAlbumText.contributionFact(nil))
        var d = FinanceData(startMonth: engNov2026)
        let pot = Pot(name: "Leeg", monthlyContribution: 0, startMonth: engNov2026)
        d.addPot(pot, openingBalance: 0, now: engTime(engNov2026, 1, hour: 8))
        let info = ContributionInfo(d, id: pot.id, month: engNov2026)
        XCTAssertNotNil(info)
        XCTAssertNil(SavingAlbumText.contributionFact(info))
    }

    // MARK: Belegging

    func testHoldingSubtitle() {
        XCTAssertEqual(SavingAlbumText.holdingSubtitle(kind: "ETF", ticker: nil), "ETF")
        XCTAssertEqual(SavingAlbumText.holdingSubtitle(kind: "ETF", ticker: ""), "ETF")
        XCTAssertEqual(SavingAlbumText.holdingSubtitle(kind: "ETF", ticker: "VWRL"), "ETF · VWRL")
    }

    func testHoldingFacts() {
        let start = YearMonth(year: 2026, month: 10)
        XCTAssertEqual(SavingAlbumText.holdingFacts(startMonth: start, isEstimated: false, contribution: nil),
                       ["Belegd sinds oktober 2026"])
        XCTAssertEqual(SavingAlbumText.holdingFacts(startMonth: start, isEstimated: true, contribution: "Inleg " + Fmt.euro(50)),
                       ["Belegd sinds oktober 2026", "Waarde geschat uit je inleg", "Inleg " + Fmt.euro(50)])
    }

    // MARK: Lijstrijen

    func testPotListSubtitle() {
        XCTAssertEqual(SavingAlbumText.potListSubtitle(goal: 2_400, progress: 0.43, interestRate: nil, contributionLine: nil),
                       "Doel " + Fmt.euro(2_400) + " · 43%")
        XCTAssertEqual(SavingAlbumText.potListSubtitle(goal: nil, progress: nil, interestRate: nil, contributionLine: nil),
                       "Geen doel ingesteld")
        XCTAssertEqual(SavingAlbumText.potListSubtitle(goal: nil, progress: nil, interestRate: 0.02, contributionLine: nil),
                       "Geen doel ingesteld · 2% rente")
        // De inleg als percentage staat op een tweede regel.
        XCTAssertEqual(SavingAlbumText.potListSubtitle(goal: 2_400, progress: 0.5, interestRate: 0.02,
                                                        contributionLine: "Inleg 10% van je salaris, " + Fmt.euro(300) + " deze maand"),
                       "Doel " + Fmt.euro(2_400) + " · 50% · 2% rente\nInleg 10% van je salaris, " + Fmt.euro(300) + " deze maand")
    }

    func testHoldingListSubtitle() {
        XCTAssertEqual(SavingAlbumText.holdingListSubtitle(base: "VWRL", isEstimated: false, gainFraction: 0.031), "VWRL · +3,1%")
        XCTAssertEqual(SavingAlbumText.holdingListSubtitle(base: "VWRL", isEstimated: false, gainFraction: -0.02), "VWRL · −2%")
        XCTAssertEqual(SavingAlbumText.holdingListSubtitle(base: "VWRL", isEstimated: false, gainFraction: 0), "VWRL · +0%")
        // Zonder inleg is er geen percentage; een geschatte waarde zegt dat ze geschat is en toont geen winst.
        XCTAssertEqual(SavingAlbumText.holdingListSubtitle(base: "ETF", isEstimated: false, gainFraction: nil), "ETF")
        XCTAssertEqual(SavingAlbumText.holdingListSubtitle(base: "ETF", isEstimated: true, gainFraction: 0.5), "ETF · Geschat")
    }
}
