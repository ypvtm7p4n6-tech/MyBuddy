import Foundation
// Foundation-only: geen SwiftUI. In het testpakket staat dit bestand als symlink; de tests staan in GoalPotsTextTests.swift.
#if canImport(MyBuddyCore)
@testable import MyBuddyCore
#endif

/// Teksten rond een doel dat uit meer spaarpotten wordt gefinancierd (D4).
enum GoalPotsText {
    static let pickerTitle = "Spaarpotten"
    static let pickerFooter = "Het saldo en de inleg per maand van alle gekozen potten tellen samen. Een pot mag voor meer doelen meetellen: zijn saldo telt dan voor elk doel."
    static let needsOnePot = "Kies minstens één spaarpot."
    static let acceleratorNote = "Een versneller zet extra geld in de eerste spaarpot van het doel."

    /// "Vakantie", "Vakantie en Reis", "Vakantie, Reis en Auto".
    static func potNames(_ names: [String]) -> String {
        DayText.list(names)
    }

    /// Onder de keuze van een pot die ook een ander doel voedt: "Deze spaarpot telt ook mee voor Auto." nil zonder ander doel.
    static func sharedWarning(otherGoalNames: [String]) -> String? {
        guard !otherGoalNames.isEmpty else { return nil }
        return "Deze spaarpot telt ook mee voor \(DayText.list(otherGoalNames))."
    }

    /// Op de pagina van een spaarpot: "Telt mee voor het doel Japan." of "Telt mee voor de doelen Japan en Auto." nil zonder doel.
    static func potLine(goalNames: [String]) -> String? {
        switch goalNames.count {
        case 0: return nil
        case 1: return "Telt mee voor het doel \(goalNames[0])."
        default: return "Telt mee voor de doelen \(DayText.list(goalNames))."
        }
    }

    /// De regel op de pagina van een doel: "Uit Vakantie en Reis" of "Uit 3 spaarpotten".
    static func sourceLine(potNames names: [String]) -> String {
        names.count > 2 ? "Uit \(names.count) spaarpotten" : "Uit \(DayText.list(names))"
    }
}
