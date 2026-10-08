import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MyBuddyCore

let aug2026 = YearMonth(year: 2026, month: 8)
let sep2026 = YearMonth(year: 2026, month: 9)
let oct2026 = YearMonth(year: 2026, month: 10)

/// Een vaste dag in een maand (om 12:00), zodat tests niet van de klok afhangen.
func day(_ m: YearMonth, _ d: Int) -> Date {
    m.firstDay.addingTimeInterval(Double(d - 1) * 86_400 + 12 * 3_600)
}

/// Basisdata: vast salaris 3000, terugkerende huur en toeslag, één pot met inleg 200.
/// Startmaand augustus, "nu" is oktober (materialize loopt dus 3 maanden).
func makeBaseData() -> FinanceData {
    var d = FinanceData(startMonth: aug2026)
    d.salary = SalarySettings(mode: .fixed, fixedMonthly: 3000, hourlyRate: 0, hoursPerWeek: 0)
    var plan = MonthPlan()
    plan.expenses = [
        MoneyLine(name: "Huur", amount: 1000, isRecurring: true),
        MoneyLine(name: "Eenmalig", amount: 50, isRecurring: false)
    ]
    plan.extraIncome = [MoneyLine(name: "Toeslag", amount: 100, isRecurring: true)]
    d.months[aug2026.key] = plan
    return d
}

func addBufferPot(_ d: inout FinanceData, opening: Double = 500, goal: Double? = 2000) -> Pot {
    let pot = Pot(name: "Buffer", goalAmount: goal, monthlyContribution: 200, startMonth: aug2026)
    d.addPot(pot, openingBalance: opening, now: day(aug2026, 2))
    return pot
}

struct FakeClient: HTTPClient {
    let handler: (URL) -> (Data, Int)
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let (data, status) = handler(url)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
