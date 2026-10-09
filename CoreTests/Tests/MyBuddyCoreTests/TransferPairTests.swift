import XCTest
@testable import MyBuddyCore

/// Overboekingen tussen bank en spaarpot (of tussen twee potten) zijn twee boekingen met hetzelfde `pairID`.
/// Verwijder je één kant, dan gaat de andere mee: bank en potten samen veranderen dan niet door een verwijdering
/// (er ontstaat geen geld uit het niets). Alle momenten zijn vast; niets hangt van de klok af.
final class TransferPairTests: XCTestCase {
    // MARK: Hulpjes

    /// Geen salaris of uitgaven: de bank verandert alleen door het meetpunt en handmatige boekingen.
    /// Meetpunt 2000 op 1 oktober; een pot "Vakantie" zonder standaardinleg.
    private func makeData() -> (data: FinanceData, pot: Pot) {
        var d = FinanceData(startMonth: oct2026)
        d.addBankSnapshot(balance: 2_000, date: day(oct2026, 1))
        let pot = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(pot)
        return (d, pot)
    }

    private let probe = day(oct2026, 20)

    private func bank(_ d: FinanceData) -> Double { d.bankBalance(on: probe) ?? .nan }
    private func pot(_ d: FinanceData, _ id: UUID) -> Double { d.potBalance(id, asOf: probe) }

    /// Bank plus alle potten.
    private func total(_ d: FinanceData) -> Double {
        bank(d) + d.pots.reduce(0) { $0 + pot(d, $1.id) }
    }

    // MARK: Aanmaken

    func testBankToPotGivesBothHalvesTheSamePairID() throws {
        var (d, p) = makeData()
        d.transferBankToPot(potID: p.id, amount: 500, date: day(oct2026, 5))
        let bankEntry = try XCTUnwrap(d.bankEntries.first)
        let potEntry = try XCTUnwrap(d.potEntries.first)
        XCTAssertNotNil(bankEntry.pairID)
        XCTAssertEqual(bankEntry.pairID, potEntry.pairID)
        XCTAssertEqual(bankEntry.amount, -500)
        XCTAssertEqual(potEntry.amount, 500)

        // Een tweede overboeking krijgt een eigen pairID.
        d.transferBankToPot(potID: p.id, amount: 100, date: day(oct2026, 6))
        XCTAssertEqual(Set(d.bankEntries.compactMap(\.pairID)).count, 2)
        XCTAssertEqual(Set(d.potEntries.compactMap(\.pairID)).count, 2)
    }

    func testPotToBankGivesBothHalvesTheSamePairID() throws {
        var (d, p) = makeData()
        d.addPotEntry(potID: p.id, amount: 800, kind: .deposit, date: day(oct2026, 2))
        d.transferPotToBank(potID: p.id, amount: 300, date: day(oct2026, 5))
        let bankEntry = try XCTUnwrap(d.bankEntries.first)
        let transferOut = try XCTUnwrap(d.potEntries.first { $0.kind == .withdrawal })
        XCTAssertNotNil(bankEntry.pairID)
        XCTAssertEqual(bankEntry.pairID, transferOut.pairID)
        // De losse storting van 800 hoort bij niets.
        XCTAssertNil(d.potEntries.first { $0.kind == .deposit }?.pairID)
    }

    func testPotToPotGivesBothHalvesTheSamePairID() throws {
        var (d, a) = makeData()
        let b = Pot(name: "Auto", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(b)
        d.transfer(from: a.id, to: b.id, amount: 100, date: day(oct2026, 5))
        let out = try XCTUnwrap(d.potEntries.first { $0.kind == .transferOut })
        let into = try XCTUnwrap(d.potEntries.first { $0.kind == .transferIn })
        XCTAssertNotNil(out.pairID)
        XCTAssertEqual(out.pairID, into.pairID)
        XCTAssertTrue(d.bankEntries.isEmpty)
    }

    func testInvalidTransfersCreateNothing() {
        var (d, p) = makeData()
        d.transferBankToPot(potID: p.id, amount: 0)
        d.transferBankToPot(potID: UUID(), amount: 100)
        d.transferPotToBank(potID: p.id, amount: -5)
        d.transfer(from: p.id, to: p.id, amount: 10)
        XCTAssertTrue(d.bankEntries.isEmpty)
        XCTAssertTrue(d.potEntries.isEmpty)
    }

    // MARK: Verwijderen: bank en potten samen blijven kloppen

    func testDeletingTheBankSideRemovesThePotSideToo() throws {
        var (d, p) = makeData()
        XCTAssertEqual(total(d), 2_000, accuracy: 0.001)
        d.transferBankToPot(potID: p.id, amount: 500, date: day(oct2026, 5))
        XCTAssertEqual(bank(d), 1_500, accuracy: 0.001)
        XCTAssertEqual(pot(d, p.id), 500, accuracy: 0.001)
        XCTAssertEqual(total(d), 2_000, accuracy: 0.001)

        d.deleteBankEntry(try XCTUnwrap(d.bankEntries.first).id)
        XCTAssertTrue(d.bankEntries.isEmpty)
        XCTAssertTrue(d.potEntries.isEmpty)
        // Het was een verschuiving: zonder die overboeking staat alles weer waar het stond.
        XCTAssertEqual(bank(d), 2_000, accuracy: 0.001)
        XCTAssertEqual(pot(d, p.id), 0, accuracy: 0.001)
        XCTAssertEqual(total(d), 2_000, accuracy: 0.001)
    }

    func testDeletingThePotSideRemovesTheBankSideToo() throws {
        var (d, p) = makeData()
        d.transferBankToPot(potID: p.id, amount: 500, date: day(oct2026, 5))
        d.deletePotEntry(try XCTUnwrap(d.potEntries.first).id)
        XCTAssertTrue(d.bankEntries.isEmpty)
        XCTAssertTrue(d.potEntries.isEmpty)
        XCTAssertEqual(bank(d), 2_000, accuracy: 0.001)
        XCTAssertEqual(pot(d, p.id), 0, accuracy: 0.001)
        XCTAssertEqual(total(d), 2_000, accuracy: 0.001)
    }

    func testPotToBankIsRemovedAsAPairFromEitherSide() throws {
        var (d, p) = makeData()
        d.addPotEntry(potID: p.id, amount: 800, kind: .deposit, date: day(oct2026, 2))
        for deleteBankSide in [true, false] {
            var copy = d
            copy.transferPotToBank(potID: p.id, amount: 300, date: day(oct2026, 5))
            XCTAssertEqual(bank(copy), 2_300, accuracy: 0.001)
            XCTAssertEqual(pot(copy, p.id), 500, accuracy: 0.001)
            XCTAssertEqual(total(copy), 2_800, accuracy: 0.001)
            if deleteBankSide {
                copy.deleteBankEntry(try XCTUnwrap(copy.bankEntries.first).id)
            } else {
                copy.deletePotEntry(try XCTUnwrap(copy.potEntries.first { $0.kind == .withdrawal }).id)
            }
            XCTAssertTrue(copy.bankEntries.isEmpty)
            XCTAssertEqual(copy.potEntries.count, 1, "alleen de storting van 800 blijft")
            XCTAssertEqual(bank(copy), 2_000, accuracy: 0.001)
            XCTAssertEqual(pot(copy, p.id), 800, accuracy: 0.001)
            XCTAssertEqual(total(copy), 2_800, accuracy: 0.001)
        }
    }

    func testPotToPotIsRemovedAsAPairFromEitherSide() throws {
        var (d, a) = makeData()
        let b = Pot(name: "Auto", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(b)
        d.addPotEntry(potID: a.id, amount: 1_000, kind: .deposit, date: day(oct2026, 2))
        d.transfer(from: a.id, to: b.id, amount: 100, date: day(oct2026, 5))
        XCTAssertEqual(pot(d, a.id), 900, accuracy: 0.001)
        XCTAssertEqual(pot(d, b.id), 100, accuracy: 0.001)

        for kind in [PotEntryKind.transferOut, .transferIn] {
            var copy = d
            copy.deletePotEntry(try XCTUnwrap(copy.potEntries.first { $0.kind == kind }).id)
            XCTAssertEqual(copy.potEntries.count, 1)
            XCTAssertEqual(pot(copy, a.id), 1_000, accuracy: 0.001, "\(kind)")
            XCTAssertEqual(pot(copy, b.id), 0, accuracy: 0.001, "\(kind)")
            XCTAssertEqual(total(copy), 3_000, accuracy: 0.001, "\(kind)")
        }
    }

    func testOnlyTheDeletedPairGoes() throws {
        var (d, p) = makeData()
        d.transferBankToPot(potID: p.id, amount: 500, date: day(oct2026, 5))
        d.transferBankToPot(potID: p.id, amount: 200, date: day(oct2026, 6))
        d.addBankEntry(amount: 75, note: "Contant", date: day(oct2026, 7))
        let first = try XCTUnwrap(d.bankEntries.first { $0.amount == -500 })
        d.deleteBankEntry(first.id)
        XCTAssertEqual(d.bankEntries.count, 2)
        XCTAssertEqual(d.potEntries.count, 1)
        XCTAssertEqual(d.potEntries.first?.amount, 200)
        XCTAssertEqual(bank(d), 2_000 - 200 + 75, accuracy: 0.001)
        XCTAssertEqual(pot(d, p.id), 200, accuracy: 0.001)
    }

    func testOldEntriesWithoutPairIDStayLooselyDeletable() throws {
        var (d, p) = makeData()
        // Zoals in een bestand van vóór de pairID's: twee losse helften.
        let bankEntry = BankEntry(date: day(oct2026, 5), amount: -500, kind: .toPot, note: "Naar Vakantie", potID: p.id)
        let potEntry = PotEntry(potID: p.id, date: day(oct2026, 5), amount: 500, kind: .deposit, note: "Van bankrekening")
        d.bankEntries.append(bankEntry)
        d.potEntries.append(potEntry)
        XCTAssertNil(bankEntry.pairID)
        XCTAssertNil(potEntry.pairID)
        XCTAssertTrue(d.pairedEntries(ofBank: bankEntry.id).isEmpty)
        XCTAssertTrue(d.pairedEntries(ofPot: potEntry.id).isEmpty)

        d.deleteBankEntry(bankEntry.id)
        XCTAssertTrue(d.bankEntries.isEmpty)
        XCTAssertEqual(d.potEntries, [potEntry], "de potkant blijft staan")
        d.deletePotEntry(potEntry.id)
        XCTAssertTrue(d.potEntries.isEmpty)
    }

    func testDeletingAnUnknownEntryChangesNothing() {
        var (d, p) = makeData()
        d.transferBankToPot(potID: p.id, amount: 500, date: day(oct2026, 5))
        let before = d
        d.deleteBankEntry(UUID())
        d.deletePotEntry(UUID())
        XCTAssertEqual(d, before)
    }

    func testManualEntriesWithoutPairStayAlone() throws {
        var (d, p) = makeData()
        d.addBankEntry(amount: 100, date: day(oct2026, 5))
        d.addPotEntry(potID: p.id, amount: 50, kind: .deposit, date: day(oct2026, 5))
        d.transferBankToPot(potID: p.id, amount: 20, date: day(oct2026, 6))
        let manual = try XCTUnwrap(d.bankEntries.first { $0.amount == 100 })
        d.deleteBankEntry(manual.id)
        XCTAssertEqual(d.bankEntries.count, 1)
        XCTAssertEqual(d.potEntries.count, 2)
    }

    // MARK: Wat er meeverdwijnt

    func testPairedEntriesDescribeWhatDisappearsWithABankEntry() throws {
        var (d, p) = makeData()
        d.transferBankToPot(potID: p.id, amount: 500, date: day(oct2026, 5))
        let bankEntry = try XCTUnwrap(d.bankEntries.first)
        let potEntry = try XCTUnwrap(d.potEntries.first)

        let removal = d.pairedEntries(ofBank: bankEntry.id)
        XCTAssertFalse(removal.isEmpty)
        XCTAssertEqual(removal.count, 1)
        XCTAssertEqual(removal.amount, 500, accuracy: 0.001)
        XCTAssertEqual(removal.potEntries, [potEntry])
        XCTAssertTrue(removal.bankEntries.isEmpty, "de gekozen boeking zelf telt niet mee")
        XCTAssertEqual(removal.warning, "Hiermee verdwijnt ook de bijbehorende boeking van \(Fmt.euro(500)).")

        // Dezelfde vraag vanaf de potkant: nu is het de bankboeking die meegaat.
        let fromPot = d.pairedEntries(ofPot: potEntry.id)
        XCTAssertEqual(fromPot.count, 1)
        XCTAssertEqual(fromPot.amount, 500, accuracy: 0.001)
        XCTAssertEqual(fromPot.bankEntries, [bankEntry])
        XCTAssertTrue(fromPot.potEntries.isEmpty)
    }

    func testPairedEntriesOfPotToPotAndUnknownIDs() throws {
        var (d, a) = makeData()
        let b = Pot(name: "Auto", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(b)
        d.transfer(from: a.id, to: b.id, amount: 100.5, date: day(oct2026, 5))
        let out = try XCTUnwrap(d.potEntries.first { $0.kind == .transferOut })
        let into = try XCTUnwrap(d.potEntries.first { $0.kind == .transferIn })
        let removal = d.pairedEntries(ofPot: out.id)
        XCTAssertEqual(removal.potEntries, [into])
        XCTAssertEqual(removal.amount, 100.5, accuracy: 0.001)

        XCTAssertTrue(d.pairedEntries(ofBank: UUID()).isEmpty)
        XCTAssertTrue(d.pairedEntries(ofPot: UUID()).isEmpty)
        XCTAssertNil(d.pairedEntries(ofPot: UUID()).warning)
        XCTAssertEqual(PairedRemoval().count, 0)
        XCTAssertEqual(PairedRemoval().amount, 0)
    }

    func testWarningForSeveralPairedEntries() {
        // Als er (door een samenvoeging van apparaten) meer dan twee boekingen één pairID delen, gaan ze allemaal weg.
        var (d, p) = makeData()
        let pair = UUID()
        let first = BankEntry(date: day(oct2026, 5), amount: -100, kind: .toPot, potID: p.id, pairID: pair)
        let second = PotEntry(potID: p.id, date: day(oct2026, 5), amount: 100, kind: .deposit, pairID: pair)
        let third = PotEntry(potID: p.id, date: day(oct2026, 5), amount: 40, kind: .deposit, pairID: pair)
        d.bankEntries = [first]
        d.potEntries = [second, third]
        let removal = d.pairedEntries(ofBank: first.id)
        XCTAssertEqual(removal.count, 2)
        XCTAssertEqual(removal.amount, 140, accuracy: 0.001)
        XCTAssertEqual(removal.warning, "Hiermee verdwijnen ook 2 bijbehorende boekingen van samen \(Fmt.euro(140)).")
        d.deleteBankEntry(first.id)
        XCTAssertTrue(d.bankEntries.isEmpty)
        XCTAssertTrue(d.potEntries.isEmpty)
    }

    // MARK: Opslaan en inlezen

    func testPairIDSurvivesEncoding() throws {
        var (d, p) = makeData()
        d.transferBankToPot(potID: p.id, amount: 500, date: day(oct2026, 5))
        d.transferPotToBank(potID: p.id, amount: 100, date: day(oct2026, 6))
        let data = try FinanceStorage.makeEncoder().encode(d)
        let back = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: data)
        XCTAssertEqual(back.bankEntries.map(\.pairID), d.bankEntries.map(\.pairID))
        XCTAssertEqual(back.potEntries.map(\.pairID), d.potEntries.map(\.pairID))
        XCTAssertFalse(back.bankEntries.contains { $0.pairID == nil })
        // En ook in het compacte bestand.
        let compact = try FinanceStorage.makeFileEncoder().encode(d)
        let fromFile = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: compact)
        XCTAssertEqual(fromFile.bankEntries.map(\.pairID), d.bankEntries.map(\.pairID))
        // Na het inlezen verdwijnen beide helften nog steeds samen.
        var loaded = back
        loaded.deleteBankEntry(loaded.bankEntries[0].id)
        XCTAssertEqual(loaded.bankEntries.count, 1)
        XCTAssertEqual(loaded.potEntries.count, 1)
    }

    func testOldFilesWithoutPairIDStillLoad() throws {
        let bankID = "11111111-1111-1111-1111-111111111111"
        let potID = "22222222-2222-2222-2222-222222222222"
        let json = """
        {"startMonth":"2026-10",
         "bankEntries":[{"id":"\(bankID)","date":"2026-10-05T10:00:00Z","amount":-500,"kind":"toPot","note":"Naar Vakantie","potID":"\(potID)"}],
         "potEntries":[{"id":"33333333-3333-3333-3333-333333333333","potID":"\(potID)","date":"2026-10-05T10:00:00Z","amount":500,"kind":"deposit","note":"Van bankrekening"}]}
        """
        let decoded = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.bankEntries.count, 1)
        XCTAssertEqual(decoded.potEntries.count, 1)
        XCTAssertNil(decoded.bankEntries[0].pairID)
        XCTAssertNil(decoded.potEntries[0].pairID)
        XCTAssertEqual(decoded.bankEntries[0].amount, -500)

        // Een pairID in het bestand wordt wel gelezen.
        let pair = "44444444-4444-4444-4444-444444444444"
        let withPair = json.replacingOccurrences(of: "\"note\":\"Naar Vakantie\"", with: "\"note\":\"Naar Vakantie\",\"pairID\":\"\(pair)\"")
        let decodedPair = try FinanceStorage.makeDecoder().decode(FinanceData.self, from: Data(withPair.utf8))
        XCTAssertEqual(decodedPair.bankEntries[0].pairID, UUID(uuidString: pair))
        XCTAssertNil(decodedPair.potEntries[0].pairID)
    }

    // MARK: Spaarpot verwijderen met saldo terug naar de bank

    func testDeletePotReturningTheBalanceKeepsTheMoneyOnTheBank() throws {
        var d = FinanceData(startMonth: oct2026)
        d.addBankSnapshot(balance: 2_000, date: day(oct2026, 1))
        let pot = Pot(name: "Vakantie", monthlyContribution: 100, startMonth: oct2026)
        d.addPot(pot, openingBalance: 1_100, now: day(oct2026, 2))
        let ninth = day(oct2026, 9)
        // Op de 9e: bank 2000 (de inleg van 100 gaat pas op de 25e van de bank), pot 1100.
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: ninth), 2_000, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: oct2026, today: ninth), 1_100, accuracy: 0.001)
        let totalBefore = d.bankBalanceNow(current: oct2026, today: ninth) + d.totalSaved(current: oct2026, today: ninth)

        var withReturn = d
        withReturn.deletePot(pot.id, returningBalanceToBank: true, current: oct2026, today: ninth)
        XCTAssertTrue(withReturn.pots.isEmpty)
        XCTAssertTrue(withReturn.potEntries.isEmpty)
        XCTAssertEqual(withReturn.bankEntries.count, 1)
        let returned = try XCTUnwrap(withReturn.bankEntries.first)
        XCTAssertEqual(returned.amount, 1_100, accuracy: 0.001)
        XCTAssertEqual(returned.kind, .fromPot)
        XCTAssertEqual(returned.date, ninth)
        XCTAssertNil(returned.pairID, "de potkant verdwijnt met de pot: de bankboeking staat los")
        // Bank + potten van nu blijven samen 3100.
        let totalAfter = withReturn.bankBalanceNow(current: oct2026, today: ninth) + withReturn.totalSaved(current: oct2026, today: ninth)
        XCTAssertEqual(totalAfter, totalBefore, accuracy: 0.001)
        XCTAssertEqual(withReturn.bankBalanceNow(current: oct2026, today: ninth), 3_100, accuracy: 0.001)
        // Zonder pot gaat er ook geen inleg meer van de bank af op de 25e.
        XCTAssertEqual(withReturn.bankBalance(on: day(oct2026, 31)) ?? .nan, 3_100, accuracy: 0.001)

        // Het losse bankregeltje is later gewoon te verwijderen, zonder iets anders mee te nemen.
        var removed = withReturn
        removed.deleteBankEntry(returned.id)
        XCTAssertTrue(removed.bankEntries.isEmpty)

        // Zonder terugboeken verdwijnt het saldo uit het overzicht, zoals voorheen.
        var withoutReturn = d
        withoutReturn.deletePot(pot.id, returningBalanceToBank: false, current: oct2026, today: ninth)
        var plain = d
        plain.deletePot(pot.id)
        XCTAssertEqual(withoutReturn, plain)
        XCTAssertTrue(withoutReturn.bankEntries.isEmpty)
        XCTAssertEqual(withoutReturn.bankBalanceNow(current: oct2026, today: ninth), 2_000, accuracy: 0.001)
    }

    func testDeletePotReturnsTheBalanceOfTheMomentNotOfTheMonthEnd() throws {
        var d = FinanceData(startMonth: oct2026)
        d.addBankSnapshot(balance: 2_000, date: day(oct2026, 1))
        let pot = Pot(name: "Vakantie", monthlyContribution: 100, startMonth: oct2026)
        d.addPot(pot, openingBalance: 1_100, now: day(oct2026, 2))

        // Voor de 25e is er 1100 om terug te boeken. Bank 2000 + pot 1100 = 3100 blijft 3100.
        let early = day(oct2026, 24)
        var beforeInleg = d
        beforeInleg.deletePot(pot.id, returningBalanceToBank: true, current: oct2026, today: early)
        XCTAssertEqual(beforeInleg.bankEntries.count, 1)
        XCTAssertEqual(beforeInleg.bankEntries.first?.amount ?? 0, 1_100, accuracy: 0.001)
        XCTAssertEqual(beforeInleg.bankBalanceNow(current: oct2026, today: early), 3_100, accuracy: 0.001)
    }

    func testDeletePotNeverGivesTheBankTheSameInlegTwice() throws {
        var d = FinanceData(startMonth: oct2026)
        d.addBankSnapshot(balance: 2_000, date: day(oct2026, 1))
        let pot = Pot(name: "Vakantie", monthlyContribution: 100, startMonth: oct2026)
        d.addPot(pot, openingBalance: 1_100, now: day(oct2026, 2))

        // Na de 25e (12:00) is de inleg van 100 van de bank naar de pot gegaan: bank 1900, pot 1200, samen 3100.
        let late = day(oct2026, 26)
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: late), 1_900, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: oct2026, today: late), 1_200, accuracy: 0.001)

        var after = d
        after.deletePot(pot.id, returningBalanceToBank: true, current: oct2026, today: late)
        // De pot geeft 1200 terug. Zijn overboeking van de 25e verdwijnt met de pot uit het bankverloop (+100);
        // dat is al meegeteld in die 1200 en wordt daarom als losse boeking van -100 teruggezet.
        XCTAssertEqual(after.bankEntries.count, 2)
        XCTAssertEqual(after.bankEntries[0].amount, 1_200, accuracy: 0.001)
        XCTAssertEqual(after.bankEntries[0].kind, .fromPot)
        XCTAssertEqual(after.bankEntries[1].amount, -100, accuracy: 0.001)
        XCTAssertEqual(after.bankEntries[1].kind, .toPot)
        XCTAssertTrue(after.bankEntries.allSatisfy { $0.pairID == nil && $0.potID == nil })
        // Samen nog steeds 3100: 2000 meetpunt + 1200 terug - 100.
        XCTAssertEqual(after.bankBalanceNow(current: oct2026, today: late), 3_100, accuracy: 0.001)
        XCTAssertEqual(after.totalSaved(current: oct2026, today: late), 0, accuracy: 0.001)
        XCTAssertTrue(after.pots.isEmpty)
        XCTAssertTrue(after.potEntries.isEmpty)
    }

    func testDeletePotWithExpensePaidFromThePotKeepsBankAndPotsTogether() throws {
        var d = FinanceData(startMonth: oct2026)
        d.addBankSnapshot(balance: 1_000, date: day(oct2026, 1))
        let pot = Pot(name: "Vakantie", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(pot, openingBalance: 600, now: day(oct2026, 2))
        // Tandarts van 200 op de 5e, waarvan 150 uit de pot (de bank betaalt 50).
        d.upsertLine(MoneyLine(name: "Tandarts", amount: 200, day: 5,
                               potShares: [PotShare(potID: pot.id, amount: 150)]), kind: .expense, in: oct2026)
        let today = day(oct2026, 9)
        XCTAssertEqual(d.bankBalanceNow(current: oct2026, today: today), 950, accuracy: 0.001)
        XCTAssertEqual(d.potBalanceNow(pot.id, current: oct2026, today: today), 450, accuracy: 0.001)

        var after = d
        after.deletePot(pot.id, returningBalanceToBank: true, current: oct2026, today: today)
        // Zonder pot betaalt de bank de hele tandarts (-150 extra), de pot geeft 450 terug: 950 + 450 = 1400.
        XCTAssertEqual(after.bankBalanceNow(current: oct2026, today: today), 1_400, accuracy: 0.001)
    }

    func testDeletePotWithoutPositiveBalanceBooksNothing() {
        var d = FinanceData(startMonth: oct2026)
        d.addBankSnapshot(balance: 500, date: day(oct2026, 1))
        let empty = Pot(name: "Leeg", monthlyContribution: 0, startMonth: oct2026)
        let negative = Pot(name: "Min", monthlyContribution: 0, startMonth: oct2026)
        d.addPot(empty)
        d.addPot(negative, openingBalance: -50, now: day(oct2026, 2))
        d.deletePot(empty.id, returningBalanceToBank: true, current: oct2026, today: day(oct2026, 9))
        d.deletePot(negative.id, returningBalanceToBank: true, current: oct2026, today: day(oct2026, 9))
        XCTAssertTrue(d.pots.isEmpty)
        XCTAssertTrue(d.bankEntries.isEmpty)
        // Een onbekende pot verandert niets.
        let before = d
        d.deletePot(UUID(), returningBalanceToBank: true, current: oct2026, today: day(oct2026, 9))
        XCTAssertEqual(d, before)
    }
}
