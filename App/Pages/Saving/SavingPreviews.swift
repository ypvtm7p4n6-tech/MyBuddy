#if DEBUG
import SwiftUI

// Voorbeelden voor de Xcode-canvas (alleen in een debug-build): de lijsten en albumpagina's van Sparen (gevuld, donker, grote tekst,
// breed en leeg) en de bladen, met voorbeelddata, en de drie gemelde gevallen bij Beleggingen
// (`-mybuddy-demo-holding`): een belegging zonder waarde-updates. Onderaan staan de voorbeelden van de nieuwe mogelijkheden: opnemen
// en storten met een bestemming of herkomst, en een pot of belegging met een extra bedrag en extra overschrijfdata.

/// Maakt een winkel met voorbeelddata (en eventueel een belegging zonder waarde-updates, of juist helemaal leeg) en een router voor
/// de voorbeelden.
@MainActor
private struct SavingPreviewHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router = Router()
    private let content: Content

    init(scenario: DemoHoldingScenario? = nil, isEmpty: Bool = false, @ViewBuilder content: () -> Content) {
        let sampleStore = AppStore(storage: nil)
        if !isEmpty { sampleStore.loadSampleData() }
        if let scenario { scenario.apply(to: sampleStore) }
        _store = State(initialValue: sampleStore)
        self.content = content()
    }

    /// Met een winkel die al is voorbereid (zie `distributionStore`).
    init(store prepared: AppStore, @ViewBuilder content: () -> Content) {
        _store = State(initialValue: prepared)
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
        }
        .environment(store)
        .environment(router)
    }
}

/// De pagina van de eerste spaarpot uit de voorbeelddata.
private struct FirstPotPreview: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let pot = store.data.pots.first {
            PotDetailPage(potID: pot.id)
        }
    }
}

/// De pagina van de eerste belegging uit de voorbeelddata.
private struct FirstHoldingPreview: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let holding = store.data.holdings.first {
            HoldingDetailPage(holdingID: holding.id)
        }
    }
}

#Preview("Spaarpotten") {
    SavingPreviewHost { PotsPage() }
}

#Preview("Spaarpotten, donker") {
    SavingPreviewHost { PotsPage() }
        .preferredColorScheme(.dark)
}

#Preview("Spaarpotten, grote tekst") {
    SavingPreviewHost { PotsPage() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Spaarpotten, leeg") {
    SavingPreviewHost(isEmpty: true) { PotsPage() }
}

#Preview("Spaarpot") {
    SavingPreviewHost { FirstPotPreview() }
}

#Preview("Spaarpot, donker") {
    SavingPreviewHost { FirstPotPreview() }
        .preferredColorScheme(.dark)
}

#Preview("Spaarpot, grote tekst") {
    SavingPreviewHost { FirstPotPreview() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Spaarpot, breed") {
    SavingPreviewHost { FirstPotPreview() }
        .frame(width: 720, height: 900)
}

#Preview("Spaarpot, bestaat niet meer") {
    SavingPreviewHost(isEmpty: true) { PotDetailPage(potID: UUID()) }
}

#Preview("Beleggingen") {
    SavingPreviewHost { PortfolioPage() }
}

#Preview("Beleggingen, donker") {
    SavingPreviewHost { PortfolioPage() }
        .preferredColorScheme(.dark)
}

#Preview("Beleggingen, grote tekst") {
    SavingPreviewHost { PortfolioPage() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Beleggingen, leeg") {
    SavingPreviewHost(isEmpty: true) { PortfolioPage() }
}

#Preview("Belegging") {
    SavingPreviewHost { FirstHoldingPreview() }
}

#Preview("Belegging, donker") {
    SavingPreviewHost { FirstHoldingPreview() }
        .preferredColorScheme(.dark)
}

#Preview("Belegging, grote tekst") {
    SavingPreviewHost { FirstHoldingPreview() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Belegging, breed") {
    SavingPreviewHost { FirstHoldingPreview() }
        .frame(width: 720, height: 900)
}

#Preview("Belegging, bestaat niet meer") {
    SavingPreviewHost(isEmpty: true) { HoldingDetailPage(holdingID: UUID()) }
}

#Preview("Beleggingen, alleen ingelegd") {
    SavingPreviewHost(scenario: .onlyInvested) { PortfolioPage() }
}

#Preview("Belegging, alleen ingelegd") {
    SavingPreviewHost(scenario: .onlyInvested) { FirstHoldingPreview() }
}

#Preview("Beleggingen, ticker zonder aantal") {
    SavingPreviewHost(scenario: .tickerNoUnits) { PortfolioPage() }
}

#Preview("Beleggingen, gevolgd zonder koers") {
    SavingPreviewHost(scenario: .trackedOffline) { PortfolioPage() }
}

#Preview("Belegging toevoegen") {
    SavingPreviewHost { HoldingEditSheet(holding: nil) }
}

#Preview("Spaarpot maken") {
    SavingPreviewHost { PotEditSheet(pot: nil) }
}

#Preview("Potten kiezen") {
    SavingPreviewHost { FavoritePotsSheet() }
}

#Preview("Beleggingen kiezen") {
    SavingPreviewHost { FavoriteHoldingsSheet() }
}

// MARK: - Opnemen en storten met een bestemming of herkomst, extra bedrag en extra overschrijfdata

/// De voorbeelddata met de nieuwe verdeelmogelijkheden (`FinanceData.sampleWithDistribution`: de vakantiepot met een percentage plus
/// een extra bedrag en een deel op de 10e), een belegging met een extra bedrag en een deel op de 5e, en een doel "Japan" dat uit twee
/// spaarpotten komt. Met `bankKnown: false` is het banksaldo nog niet ingevuld.
@MainActor
private func distributionStore(bankKnown: Bool = true) -> AppStore {
    let prepared = AppStore(storage: nil)
    prepared.replaceData(FinanceData.sampleWithDistribution(now: Date()))
    let current = prepared.now
    prepared.mutate { data in
        if let world = data.holdings.first(where: { $0.name == "Wereld ETF" }) {
            data.setContributionPercent(world.id, percent: 2, basis: .salary, extra: 30, current: current)
            data.setStandardTransferParts(world.id, parts: [TransferPart(day: 5, amount: 50)], current: current)
        }
        if let holiday = data.pots.first(where: { $0.name == "Vakantie" }),
           let buffer = data.pots.first(where: { $0.name == "Buffer" }) {
            var japan = LifeGoal(name: "Japan", kind: .vacation)
            japan.targetAmount = 4_000
            japan.setFundingPots([holiday.id, buffer.id])
            data.goals.insert(japan, at: 0)
        }
        if !bankKnown {
            data.bankSnapshots = []
            data.bankEntries = []
        }
    }
    return prepared
}

/// Het blad om geld bij de vakantiepot te storten of op te nemen, met een bestemming of herkomst: `end` is "Bankrekening", de naam van
/// een andere spaarpot of nil (buiten je overzicht).
private struct PotEntryPreview: View {
    let action: PotAction
    var end: String? = nil
    var amount = 0.0
    @Environment(AppStore.self) private var store

    var body: some View {
        if let pot = store.data.pots.first(where: { $0.name == "Vakantie" }) {
            PotEntrySheet(pot: pot, action: action, end: moneyEnd, amount: amount)
        }
    }

    private var moneyEnd: MoneyEnd {
        guard let end else { return .outside }
        if end == "Bankrekening" { return .bank }
        return store.data.pots.first(where: { $0.name == end }).map { MoneyEnd.pot($0.id) } ?? .outside
    }
}

/// Het blad van de vakantiepot: een percentage met extra bedrag en een extra overschrijfdag.
private struct HolidayPotEditPreview: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let pot = store.data.pots.first(where: { $0.name == "Vakantie" }) {
            PotEditSheet(pot: pot)
        }
    }
}

/// De pagina van de vakantiepot: met extra overschrijfdata en een doel dat de pot gebruikt.
private struct HolidayPotPagePreview: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let pot = store.data.pots.first(where: { $0.name == "Vakantie" }) {
            PotDetailPage(potID: pot.id)
        }
    }
}

/// Het blad van de wereld-ETF: een percentage met extra bedrag en een extra overschrijfdag.
private struct WorldHoldingEditPreview: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let holding = store.data.holdings.first(where: { $0.name == "Wereld ETF" }) {
            HoldingEditSheet(holding: holding)
        }
    }
}

#Preview("Opnemen, naar de bankrekening") {
    SavingPreviewHost(store: distributionStore()) { PotEntryPreview(action: .withdraw, end: "Bankrekening", amount: 60) }
}

#Preview("Opnemen, naar een andere pot") {
    SavingPreviewHost(store: distributionStore()) { PotEntryPreview(action: .withdraw, end: "Buffer", amount: 60) }
}

#Preview("Opnemen, nergens (uit je overzicht)") {
    SavingPreviewHost(store: distributionStore()) { PotEntryPreview(action: .withdraw, amount: 60) }
}

#Preview("Opnemen, donker") {
    SavingPreviewHost(store: distributionStore()) { PotEntryPreview(action: .withdraw, end: "Bankrekening", amount: 60) }
        .preferredColorScheme(.dark)
}

#Preview("Opnemen, grote tekst") {
    SavingPreviewHost(store: distributionStore()) { PotEntryPreview(action: .withdraw, end: "Buffer", amount: 60) }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Storten, uit een andere pot") {
    SavingPreviewHost(store: distributionStore()) { PotEntryPreview(action: .deposit, end: "Buffer", amount: 60) }
}

#Preview("Storten, van de bankrekening zonder saldo") {
    SavingPreviewHost(store: distributionStore(bankKnown: false)) { PotEntryPreview(action: .deposit, end: "Bankrekening", amount: 60) }
}

#Preview("Storten, van buiten je overzicht") {
    SavingPreviewHost(store: distributionStore()) { PotEntryPreview(action: .deposit) }
}

#Preview("Spaarpot bewerken, extra bedrag en extra dag") {
    SavingPreviewHost(store: distributionStore()) { HolidayPotEditPreview() }
}

#Preview("Spaarpot bewerken, donker") {
    SavingPreviewHost(store: distributionStore()) { HolidayPotEditPreview() }
        .preferredColorScheme(.dark)
}

#Preview("Spaarpot bewerken, grote tekst") {
    SavingPreviewHost(store: distributionStore()) { HolidayPotEditPreview() }
        .dynamicTypeSize(.accessibility3)
}

#Preview("Spaarpot, extra dag en doel") {
    SavingPreviewHost(store: distributionStore()) { HolidayPotPagePreview() }
}

#Preview("Spaarpot, extra dag en doel, donker") {
    SavingPreviewHost(store: distributionStore()) { HolidayPotPagePreview() }
        .preferredColorScheme(.dark)
}

#Preview("Belegging bewerken, extra bedrag en extra dag") {
    SavingPreviewHost(store: distributionStore()) { WorldHoldingEditPreview() }
}

#Preview("Belegging bewerken, grote tekst") {
    SavingPreviewHost(store: distributionStore()) { WorldHoldingEditPreview() }
        .dynamicTypeSize(.accessibility3)
}
#endif
