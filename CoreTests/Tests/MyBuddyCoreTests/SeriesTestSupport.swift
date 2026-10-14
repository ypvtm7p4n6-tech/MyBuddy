import XCTest
import Foundation
@testable import MyBuddyCore

// Hulpjes voor de tests van terugkerende regels (reeksen) en percentage-inleg: een verzamelaar van mislukte
// vergelijkingen (snel in een debug-build), een onafhankelijk bijgehouden "orakel" van wat een reeks in elke maand moet
// zijn, en de bewerkingen die beide kanten (rekenmotor en orakel) tegelijk uitvoeren.

/// Verzamelt mislukte vergelijkingen zonder per vergelijking de XCTest-machinerie aan te roepen (dat is in een
/// debug-build zo traag dat een test met tienduizenden vergelijkingen er minuten over zou doen) en meldt ze aan het eind.
final class Collector {
    private(set) var list: [String] = []
    private(set) var count = 0

    func eq<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String) {
        count += 1
        if a != b { list.append("\(message()): \(a) is niet gelijk aan \(b)") }
    }

    func ok(_ condition: Bool, _ message: @autoclosure () -> String) {
        count += 1
        if !condition { list.append(message()) }
    }

    func report(file: StaticString = #filePath, line: UInt = #line) {
        if !list.isEmpty {
            XCTFail("\(list.count) van \(count) vergelijkingen mislukt, de eerste:\n" + list.prefix(15).joined(separator: "\n"),
                    file: file, line: line)
        }
    }
}

// MARK: - Het orakel van een reeks

/// Wat een terugkerende regel in elke maand moet zijn, bijgehouden met de eenvoudigste regels van de gebruiker:
/// "deze en alle volgende maanden" past alles vanaf die maand aan (behalve maanden waar je "alleen deze maand" iets
/// anders van maakte), "alleen deze maand" verandert die ene maand, en verwijderen haalt de regel weg (één maand of
/// vanaf die maand). Het orakel kent geen opgeslagen of afgeleide maanden: dat is juist wat de rekenmotor goed moet doen.
struct SeriesOracle {
    struct Value: Equatable {
        var amount: Double
        var day: Int?
        /// Deel van een uitgave dat uit de spaarpot komt (alleen uitgaven).
        var fromPot: Double = 0
    }

    var name: String
    var income: Bool
    var kind: ExpenseKind
    /// Maandnummer vanaf de startmaand (0 = startmaand) -> hoe de regel er in die maand uitziet. Afwezig = hoort er niet te zijn.
    var months: [Int: Value] = [:]
    var exceptions: Set<Int> = []
    var horizon: Int
    /// De eerste maand waarin de reeks is gestopt ("deze en alle volgende maanden" verwijderd); nil = loopt door.
    var endedFrom: Int?

    /// Een nieuwe reeks vanaf maand `m`.
    mutating func add(from m: Int, _ value: Value) {
        for k in m..<horizon { months[k] = value }
    }

    /// "Deze en alle volgende maanden": maand `m` en alle latere maanden (behalve afwijkende maanden) krijgen de
    /// gewijzigde velden. Aanroepers veranderen altijd zowel bedrag als dag, zodat er geen veld "tussendoor" blijft.
    mutating func updateFollowing(at m: Int, to new: Value) {
        guard let old = months[m] else { return }
        // Was het een afwijkende maand, dan wordt zijn hele regel de nieuwe basis; anders gaat alleen mee wat veranderde.
        let everything = exceptions.contains(m)
        exceptions.remove(m)
        months[m] = new
        if m + 1 < horizon {
            for k in (m + 1)..<horizon where months[k] != nil && !exceptions.contains(k) {
                if everything || old.amount != new.amount { months[k]!.amount = new.amount }
                if everything || old.day != new.day { months[k]!.day = new.day }
                if everything || old.fromPot != new.fromPot { months[k]!.fromPot = new.fromPot }
            }
        }
    }

    /// "Alleen deze maand".
    mutating func updateThisMonth(at m: Int, to new: Value) {
        guard months[m] != nil else { return }
        months[m] = new
        exceptions.insert(m)
    }

    /// Verwijderen voor één maand: de reeks loopt daarna gewoon door.
    mutating func removeThisMonth(at m: Int) {
        months[m] = nil
        exceptions.remove(m)
    }

    /// Verwijderen vanaf een maand: de reeks stopt (ook in maanden die al waren opgeslagen).
    mutating func removeFollowing(from m: Int) {
        endedFrom = min(endedFrom ?? m, m)
        for k in m..<horizon {
            months[k] = nil
            exceptions.remove(k)
        }
    }
}

/// Een dataset met reeksen, het orakel en alles wat daarbij hoort om te controleren.
struct SeriesWorld {
    var data: FinanceData
    var start: YearMonth
    var horizon: Int
    var series: [SeriesOracle]
    /// Eenmalige uitgaven per maandnummer (in euro's), mogen nooit buiten hun eigen maand voorkomen.
    var oneOffs: [Int: Double]
    var pot: Pot?
    var potOpening: Double
    /// Overschreven verdeling van de pot per maandnummer.
    var potAllocation: [Int: Double]
    /// Afwijkend salaris per maandnummer.
    var salaryOverrides: [Int: Double] = [:]
    /// Het ingevulde banksaldo aan het eind van de maand vóór de start (geen andere boekingen op de bank).
    var bankStart: Double = 0
    var ops: [String]
    var seed: UInt64

    func month(_ k: Int) -> YearMonth { start.adding(k) }
}

/// Bouwt een herhaalbare dataset en voert er willekeurige bewerkingen op uit (aan beide kanten tegelijk).
///
/// - startmaand tussen 2026-01 en 2027-12 (dus ook met korte maanden en een schrikkeljaar in de horizon);
/// - salaris op een willekeurige dag; één pot met vaste inleg, een deel van de uitgaven komt uit die pot;
/// - 3...12 bewerkingen: reeks toevoegen (uitgave of inkomsten), bewerken (alleen deze maand of deze en alle volgende),
///   verwijderen (idem), een maand vastleggen op een andere manier (verdeling, overschrijfdag, salaris) en
///   `materialize(upTo:)`. De volgorde is willekeurig: ook "toevoegen terwijl een latere maand al is vastgelegd".
func seriesWorld(seed: UInt64, operations: ClosedRange<Int> = 3...12) -> SeriesWorld {
    var r = EngRandom(seed: seed &+ 91_000)
    let start = YearMonth(year: 2026, month: 1).adding(r.int(0...23))
    let current = r.int(0...5)                // "nu" is dit aantal maanden na de start
    let horizon = current + 62                // t/m ruim 5 jaar vooruit
    var d = FinanceData(startMonth: start)
    d.salary = SalarySettings(mode: .fixed, fixedMonthly: 2_000 + Double(r.int(0...2_000)), hourlyRate: 0, hoursPerWeek: 0,
                              payDay: r.int(1...31))
    // Een deel van de datasets krijgt een salaris om de zoveel weken of dagen (een eigen reeks getallen, zodat de rest van de
    // dataset voor elke zaadwaarde gelijk blijft): inkomsten zonder eigen dag volgen dan de eerste uitbetaling van de maand.
    var schedule = EngRandom(seed: seed &+ 99_000)
    if schedule.chance(35) {
        let anchor: CalendarDay? = schedule.chance(75)
            ? CalendarDay(dayNumber: CalendarDay(month: start, day: 10).dayNumber + schedule.int(-200...200)) : nil
        switch schedule.int(0...3) {
        case 0: d.salary.setSchedule(.weeks, interval: 4, anchor: anchor)
        case 1: d.salary.setSchedule(.weeks, interval: 2, anchor: anchor)
        case 2: d.salary.setSchedule(.days, interval: schedule.int(1...45), anchor: anchor)
        default: d.salary.setSchedule(.weeks, interval: schedule.int(5...9), anchor: anchor)
        }
    }
    var pot = Pot(name: "Spaarpot", monthlyContribution: Double(r.int(0...30)) * 10, startMonth: start.adding(r.int(0...2)))
    pot.id = StableID.uuid("series-world|\(seed)|pot")
    pot.createdAt = Date(timeIntervalSince1970: 1_790_000_000)   // hele seconden: de bestandsvorm bewaart geen fracties
    let opening = Double(r.int(0...100)) * 10
    d.addPot(pot, openingBalance: opening, now: start.firstDay.addingTimeInterval(3_600))
    let bankStart = Double(r.int(0...5_000))
    d.addBankSnapshot(balance: bankStart, note: "Start", date: start.adding(-1).date(day: 20))

    var world = SeriesWorld(data: d, start: start, horizon: horizon, series: [], oneOffs: [:], pot: pot,
                            potOpening: opening, potAllocation: [:], bankStart: bankStart, ops: [], seed: seed)
    var counter = 0

    /// Een nieuwe waarde. Met `old`: het bedrag en de dag veranderen, tenzij `partial` waar is: dan blijft een van beide
    /// (of allebei) soms gelijk, zodat ook "alleen het bedrag veranderd" voorkomt.
    func randomValue(income: Bool, avoiding old: SeriesOracle.Value? = nil, partial: Bool = false) -> SeriesOracle.Value {
        var amount = Double(r.int(500...50_000)) / 100
        var day: Int? = r.chance(12) ? nil : r.int(1...31)
        if let old {
            if partial, r.chance(40) {
                amount = old.amount
            } else {
                while amount == old.amount { amount = Double(r.int(500...50_000)) / 100 }
            }
            if partial, r.chance(40) {
                day = old.day
            } else {
                while day == old.day { day = r.chance(12) ? nil : r.int(1...31) }
            }
        }
        var value = SeriesOracle.Value(amount: amount, day: day)
        // Soms meer dan het bedrag zelf: de rekenmotor kapt af op het bedrag.
        if !income, r.chance(30) { value.fromPot = Double(r.int(100...max(100, Int(amount * 130)))) / 100 }
        return value
    }

    func line(_ oracle: SeriesOracle, _ value: SeriesOracle.Value, id: UUID? = nil, recurring: Bool = true) -> MoneyLine {
        var l = MoneyLine(name: oracle.name, amount: value.amount, isRecurring: recurring, kind: oracle.kind, day: value.day)
        if let id { l.id = id }
        if !oracle.income, value.fromPot > 0, let pot = world.pot {
            l.potShares = [PotShare(id: StableID.uuid("series-world|\(seed)|share|\(oracle.name)"), potID: pot.id,
                                    amount: value.fromPot)]
        }
        return l
    }

    func engineLine(_ oracle: SeriesOracle, in m: Int) -> MoneyLine? {
        let plan = world.data.plan(for: world.month(m))
        return (oracle.income ? plan.extraIncome : plan.expenses).first { $0.name == oracle.name }
    }

    let count = r.int(operations.lowerBound...operations.upperBound)
    for step in 0..<count {
        switch r.int(0...12) {
        case 10:   // opslaan en weer inlezen (cloud, back-up, bestand): niets mag veranderen
            let encoder = FinanceStorage.makeFileEncoder()
            if let bytes = try? encoder.encode(world.data), let back = try? FinanceStorage.makeDecoder().decode(FinanceData.self, from: bytes) {
                if back != world.data { XCTFail("seed \(seed): gegevens veranderen na opslaan en inlezen (stap \(step))") }
                world.data = back
            }
            world.ops.append("\(step): opgeslagen en ingelezen")
        case 11:   // de afgeleide reeks-id's van oude gegevens wegschrijven
            world.data.migrateRecurringSeries()
            world.ops.append("\(step): migratie")
        case 12:   // andere salarisdag: inkomsten zonder eigen dag volgen die
            world.data.salary.payDay = r.int(1...31)
            world.ops.append("\(step): andere salarisdag")
        case 0, 1, 2:   // een reeks toevoegen, in een willekeurige maand (ook ver vooruit of lang geleden)
            counter += 1
            let income = r.chance(25)
            let m = r.int(0...min(horizon - 1, current + 10))
            var oracle = SeriesOracle(name: "Reeks \(counter)", income: income, kind: r.chance(50) ? .fixed : .variable,
                                      horizon: horizon)
            let value = randomValue(income: income)
            oracle.add(from: m, value)
            var added = line(oracle, value)
            added.id = StableID.uuid("series-world|\(seed)|line|\(counter)")
            world.data.upsertLine(added, kind: income ? .income : .expense, in: world.month(m))
            world.series.append(oracle)
            world.ops.append("\(step): toevoegen \(oracle.name) in \(m)")
        case 3, 4:   // bewerken, deze en alle volgende
            guard let (i, m) = pick(&r, world.series, current: current) else { continue }
            let old = world.series[i].months[m]!
            let new = randomValue(income: world.series[i].income, avoiding: old, partial: true)
            guard let existing = engineLine(world.series[i], in: m) else {
                XCTFail("seed \(seed): regel ontbreekt vóór bewerken: \(world.series[i].name) in \(m)")
                continue
            }
            var changed = line(world.series[i], new, id: existing.id)
            changed.seriesID = existing.seriesID
            changed.isException = existing.isException
            world.data.upsertLine(changed, kind: world.series[i].income ? .income : .expense, in: world.month(m),
                                  scope: .thisAndFollowing)
            world.series[i].updateFollowing(at: m, to: new)
            world.ops.append("\(step): bewerk volgende \(world.series[i].name) in \(m)")
        case 5:   // bewerken, alleen deze maand
            guard let (i, m) = pick(&r, world.series, current: current) else { continue }
            let old = world.series[i].months[m]!
            let new = randomValue(income: world.series[i].income, avoiding: old)
            guard let existing = engineLine(world.series[i], in: m) else { continue }
            var changed = line(world.series[i], new, id: existing.id)
            changed.seriesID = existing.seriesID
            changed.isException = existing.isException
            world.data.upsertLine(changed, kind: world.series[i].income ? .income : .expense, in: world.month(m),
                                  scope: .thisMonth)
            world.series[i].updateThisMonth(at: m, to: new)
            world.ops.append("\(step): bewerk alleen \(world.series[i].name) in \(m)")
        case 6:   // verwijderen, alleen deze maand
            guard let (i, m) = pick(&r, world.series, current: current) else { continue }
            guard let existing = engineLine(world.series[i], in: m) else { continue }
            world.data.deleteLine(id: existing.id, kind: world.series[i].income ? .income : .expense, in: world.month(m),
                                  scope: .thisMonth)
            world.series[i].removeThisMonth(at: m)
            world.ops.append("\(step): verwijder alleen \(world.series[i].name) in \(m)")
        case 7:   // verwijderen, deze en alle volgende
            guard let (i, m) = pick(&r, world.series, current: current) else { continue }
            guard let existing = engineLine(world.series[i], in: m) else { continue }
            world.data.deleteLine(id: existing.id, kind: world.series[i].income ? .income : .expense, in: world.month(m),
                                  scope: .thisAndFollowing)
            world.series[i].removeFollowing(from: m)
            world.ops.append("\(step): verwijder volgende \(world.series[i].name) in \(m)")
        case 8:   // een maand vastleggen door iets anders te bewerken
            let m = r.int(0...min(horizon - 1, current + 12))
            switch r.int(0...3) {
            case 0: world.data.editPlan(world.month(m)) { $0.transferDay = r.int(1...28) }
            case 1:
                let salary = Double(r.int(1_000...4_000))
                world.data.editPlan(world.month(m)) { $0.salaryOverride = salary }
                world.salaryOverrides[m] = salary
            case 2:
                if let pot = world.pot {
                    let value = Double(r.int(0...40)) * 10
                    world.data.setAllocation(pot.id, in: world.month(m), amount: value)
                    world.potAllocation[m] = value
                }
            default: world.data.editPlan(world.month(m)) { _ in }
            }
            world.ops.append("\(step): maand \(m) vastgelegd")
        default:   // alles t/m een maand vastleggen; en soms een eenmalige uitgave
            if r.chance(60) {
                let m = r.int(0...min(horizon - 1, current + 3))
                world.data.materialize(upTo: world.month(m))
                world.ops.append("\(step): materialize t/m \(m)")
            } else {
                let m = r.int(0...min(horizon - 1, current + 12))
                let amount = Double(r.int(500...30_000)) / 100
                if world.oneOffs[m] == nil {
                    world.data.upsertLine(MoneyLine(name: "Eenmalig", amount: amount, isRecurring: false, day: r.int(1...31)),
                                          kind: .expense, in: world.month(m))
                    world.oneOffs[m] = amount
                    world.ops.append("\(step): eenmalig in \(m)")
                }
            }
        }
    }
    return world
}

/// Kiest een reeks en een maand waarin de reeks (volgens het orakel) een regel heeft, tot een eind voorbij "nu".
private func pick(_ r: inout EngRandom, _ series: [SeriesOracle], current: Int) -> (Int, Int)? {
    guard !series.isEmpty else { return nil }
    let i = r.int(0...series.count - 1)
    let candidates = series[i].months.keys.filter { $0 <= current + 14 }.sorted()
    guard !candidates.isEmpty else { return nil }
    return (i, candidates[r.int(0...candidates.count - 1)])
}
