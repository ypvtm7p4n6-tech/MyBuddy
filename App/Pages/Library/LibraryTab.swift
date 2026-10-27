import SwiftUI

// De Bibliotheek (B7 en par. 1.4 van docs/design2/plan.md): de lijst van alle pagina's van de app in drie groepen, daarna Recent. Elke
// rij is een `MediaRow` met een tegel in de kleur van de pagina, een ondertitel en een waarde. De rijen van "Deze maand" openen op
// de huidige maand (B8). De waarden komen uit `LibraryFigures`, en daarmee uit dezelfde bronnen als de oude kaarten van de tabs
// Maand, Sparen en Plannen. De wortel is alleen inhoud: de stapel komt van `TabStack`.

/// De wortel van de tab Bibliotheek. Leest de bewaarde keuzes van dit account (het concept van de spaardoel-calculator en de
/// instellingen van de noodbuffer, zoals de oude kaarten Doelen en Noodbuffer) en geeft ze aan de lijst.
struct LibraryTab: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    var body: some View {
        let account = accountPrefsID(auth: auth, cloud: cloud)
        LibraryList(draftKey: SavingsGoalDraft.storageKey(account: account),
                    bufferKey: AccountPrefs.key(BufferSetup.storageKey, account: account))
    }
}

/// De lijst zelf, met de bewaarde keuzes van het account als `@AppStorage` (de sleutel staat pas vast bij het aanmaken).
private struct LibraryList: View {
    @Environment(AppStore.self) private var store
    @AppStorage private var storedDraft: String
    @AppStorage private var storedBuffer: String

    init(draftKey: String, bufferKey: String) {
        _storedDraft = AppStorage(wrappedValue: "", draftKey)
        _storedBuffer = AppStorage(wrappedValue: "", bufferKey)
    }

    var body: some View {
        let figures = LibraryFigures(data: store.data, now: store.now, today: store.today,
                                     goalDraftJSON: storedDraft, bufferSetupJSON: storedBuffer)
        ListScaffold(title: "Bibliotheek", large: true) {
            ForEach(LibrarySection.allCases) { section in
                LibrarySectionRows(section: section, figures: figures)
            }
            LibraryRecentRows(items: figures.recent())
        }
        .profileToolbarItem()
    }
}

// MARK: - Groepen

/// Eén groep van de Bibliotheek: de kop en de rijen van `PageCatalog.library(in:)`. De rijen van "Deze maand" zetten de maandpagina's
/// eerst op de huidige maand.
struct LibrarySectionRows: View {
    let section: LibrarySection
    let figures: LibraryFigures

    var body: some View {
        Section {
            ForEach(PageCatalog.library(in: section)) { info in
                LibraryPageRow(info: info, figures: figures.row(for: info.destination),
                               showsCurrentMonth: section == .month)
            }
        } header: {
            SectionHeader(figures.sectionTitle(section))
        }
    }
}

/// Eén rij: titel, symbool en tint uit de catalogus, ondertitel en waarde uit `LibraryFigures`. Een negatieve waarde heeft de
/// kleur van een tekort; het minteken staat altijd in de tekst.
struct LibraryPageRow: View {
    let info: PageInfo
    let figures: LibraryRowFigures
    let showsCurrentMonth: Bool

    var body: some View {
        MediaRow(symbol: info.symbol, hue: info.hue, title: info.title, subtitle: figures.subtitle, value: figures.value,
                 valueColor: valueColor, destination: info.destination, showsCurrentMonth: showsCurrentMonth)
    }

    private var valueColor: Color {
        figures.tone == .negative ? Theme.negative : Color.primary
    }
}

// MARK: - Recent

/// De groep Recent: de laatste vijf handmatige boekingen (`RecentActivity`). Zonder boekingen is er geen groep.
struct LibraryRecentRows: View {
    let items: [RecentItem]

    var body: some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    LibraryRecentRow(item: item)
                }
            } header: {
                SectionHeader("Recent")
            }
        }
    }
}

/// Eén recente boeking: de spaarpot (in zijn kleur en met zijn symbool) of de bankrekening, wat er gebeurde met de datum, en het
/// bedrag met teken. Een tik opent de spaarpot of de bankrekening.
struct LibraryRecentRow: View {
    let item: RecentItem

    var body: some View {
        MediaRow(symbol: item.symbol, hue: item.hue, title: item.title, subtitle: item.subtitle,
                 value: CashflowText.signed(item.amount), valueColor: valueColor, destination: item.destination)
    }

    private var valueColor: Color {
        item.amount >= 0 ? Theme.positive : Theme.negative
    }
}
