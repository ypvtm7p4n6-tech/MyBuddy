import Foundation

// MARK: - Geld uit of naar een spaarpot, met een bestemming of herkomst (D5)
//
// Opnemen uit een pot en storten in een pot kennen drie uiteinden (`MoneyEnd`):
//
//   .outside  buiten de app (contant, ergens anders besteed): alleen de potkant bestaat. Dit is wat "Opnemen" en "Storten" altijd deden;
//             oude gegevens en de standaardkeuze blijven zo.
//   .bank     de bankrekening: een boeking op de bank en een boeking in de pot met hetzelfde `pairID` (`transferPotToBank`,
//             `transferBankToPot`). Het geld komt echt op de rekening aan, in het saldo van de bank, de dagboekhouding en de geschiedenis.
//   .pot(id)  een andere pot: twee boekingen met hetzelfde `pairID` en dezelfde datum (`transfer`).
//
// Een boeking met `pairID` wordt samen met haar andere helft verwijderd (`deletePotEntry`, `deleteBankEntry`); de andere helft staat
// op dezelfde datum en telt dus ook voor de startdatum op dezelfde manier mee (`countedBankEntries`, `countedPotEntries`).

/// Waar geld vandaan komt of heen gaat bij een pot.
enum MoneyEnd: Hashable {
    case outside
    case bank
    case pot(UUID)
}

extension FinanceData {
    /// Neemt `amount` op uit de pot `id` en zet het op `destination`. Geeft false (en doet niets) bij een onbekende pot, een bedrag
    /// van nul of minder (op hele centen), een onbekende doelpot of een doelpot die de pot zelf is.
    @discardableResult
    mutating func withdraw(fromPot id: UUID, amount: Double, to destination: MoneyEnd, note: String = "", date: Date = Date()) -> Bool {
        let value = amount.cents
        guard pot(id) != nil, value > 0 else { return false }
        switch destination {
        case .outside:
            addPotEntry(potID: id, amount: -value, kind: .withdrawal, note: note, date: date)
        case .bank:
            transferPotToBank(potID: id, amount: value, note: note, date: date)
        case .pot(let other):
            guard other != id, pot(other) != nil else { return false }
            transfer(from: id, to: other, amount: value, note: note, date: date)
        }
        return true
    }

    /// Stort `amount` in de pot `id` en haalt het van `source`. Zelfde regels als `withdraw(fromPot:amount:to:note:date:)`.
    @discardableResult
    mutating func deposit(toPot id: UUID, amount: Double, from source: MoneyEnd, note: String = "", date: Date = Date()) -> Bool {
        let value = amount.cents
        guard pot(id) != nil, value > 0 else { return false }
        switch source {
        case .outside:
            addPotEntry(potID: id, amount: value, kind: .deposit, note: note, date: date)
        case .bank:
            transferBankToPot(potID: id, amount: value, note: note, date: date)
        case .pot(let other):
            guard other != id, pot(other) != nil else { return false }
            transfer(from: other, to: id, amount: value, note: note, date: date)
        }
        return true
    }
}
