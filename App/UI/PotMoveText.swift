import Foundation
// Foundation-only: geen SwiftUI. In de app zit alles in één module. In het testpakket (CoreTests/Tests/MyBuddyCoreTests) staat
// dit bestand als symlink tussen de tests en leest het de rekenmotor via `@testable import`; de tests staan in
// PotMoveTextTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

/// Naar of van een pot: opnemen of storten.
enum PotMoveDirection {
    case withdraw, deposit
}

/// Teksten en keuzes bij geld uit of naar een spaarpot met een bestemming of herkomst (D5). Alleen tekst: bedragen en namen komen uit de
/// rekenmotor.
enum PotMoveText {
    static let outsideTitle = "Nergens (uit je overzicht)"
    static let bankTitle = "Bankrekening"

    /// De vraag boven de keuze.
    static func question(_ direction: PotMoveDirection) -> String {
        direction == .withdraw ? "Waar gaat het naartoe?" : "Waar komt het vandaan?"
    }

    /// De naam van een uiteinde: "Nergens (uit je overzicht)", "Bankrekening" of de naam van de pot.
    static func title(_ end: MoneyEnd, in data: FinanceData) -> String {
        switch end {
        case .outside: return outsideTitle
        case .bank: return bankTitle
        case .pot(let id): return data.pot(id)?.name ?? "Spaarpot"
        }
    }

    /// De keuzes voor een pot: buiten het overzicht, de bankrekening en elke andere spaarpot, op de volgorde van de potten.
    static func choices(excluding potID: UUID, in data: FinanceData) -> [MoneyEnd] {
        [.outside, .bank] + data.pots.filter { $0.id != potID }.map { MoneyEnd.pot($0.id) }
    }

    /// De zin onder het formulier: wat er met het bedrag gebeurt.
    static func footer(_ direction: PotMoveDirection, end: MoneyEnd, amount: Double, in data: FinanceData) -> String {
        let value = Fmt.euro(amount.cents)
        switch (direction, end) {
        case (.withdraw, .outside):
            return "\(value) gaat uit deze pot en komt nergens anders in je overzicht terug, bijvoorbeeld omdat je het contant uitgeeft."
        case (.withdraw, .bank):
            return "\(value) gaat van deze pot naar je bankrekening. De boeking staat in de geschiedenis van allebei."
        case (.withdraw, .pot(let id)):
            return "\(value) gaat naar \(data.pot(id)?.name ?? "de andere pot"). De boeking staat in de geschiedenis van allebei."
        case (.deposit, .outside):
            return "\(value) komt van buiten je overzicht in deze pot. Er verandert niets aan je bankrekening."
        case (.deposit, .bank):
            return "\(value) gaat van je bankrekening naar deze pot. De boeking staat in de geschiedenis van allebei."
        case (.deposit, .pot(let id)):
            return "\(value) komt uit \(data.pot(id)?.name ?? "de andere pot"). De boeking staat in de geschiedenis van allebei."
        }
    }

    /// Melding bij de bankrekening als bron of bestemming terwijl het saldo nog niet bekend is: de boeking begint dan het saldo.
    static func bankUnknownNote(amount: Double) -> String {
        "Je banksaldo is nog niet ingevuld. Met deze boeking begint het saldo bij \(Fmt.euro(amount.cents)); vul je echte saldo in op Bankrekening."
    }
}
