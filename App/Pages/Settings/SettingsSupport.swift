import SwiftUI

// Gedeelde bouwstenen van de pagina's in Instellingen en Account.

// MARK: - Subpagina's openen

private struct OpenSettingsPageKey: EnvironmentKey {
    static let defaultValue: ((SettingsPage) -> Void)? = nil
}

extension EnvironmentValues {
    /// Opent een subpagina van Instellingen op de stapel waar de pagina nu in staat. Zonder waarde (de tab Instellingen op iOS)
    /// loopt het via de router (`router.open`); in een pane van het `Settings`-venster op de Mac zet `SettingsPane` hier het
    /// pad van de pane, want daar heeft elke pane een eigen stapel.
    var openSettingsPage: ((SettingsPage) -> Void)? {
        get { self[OpenSettingsPageKey.self] }
        set { self[OpenSettingsPageKey.self] = newValue }
    }
}

// MARK: - Rij naar een instellingenpagina

/// Een rij in een lijst die naar een instellingenpagina leidt: pictogram, titel, een korte waarde eronder en een pijltje.
/// Zonder `title` en `symbol` zijn dat die van de pagina (`SettingsPage.title` en `.symbol`). De rij is een knop die de pagina
/// opent via `openSettingsPage` of, zonder die, via de router.
struct SettingsLinkRow: View {
    let page: SettingsPage
    var title: String? = nil
    var subtitle: String? = nil
    var symbol: String? = nil
    var badgeSize: CGFloat = 32
    var needsAttention: Bool = false
    var isDestructive: Bool = false
    @Environment(Router.self) private var router
    @Environment(\.openSettingsPage) private var openPage

    var body: some View {
        Button(action: openTarget) {
            HStack(spacing: 12) {
                SymbolBadge(symbol: symbol ?? page.symbol, color: badgeColor, size: badgeSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? page.title)
                        .font(.body)
                        .foregroundStyle(titleColor)
                    subtitleView
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(.isLink)
    }

    private var titleColor: Color {
        isDestructive ? Theme.negative : Color.primary
    }

    private var badgeColor: Color {
        isDestructive ? Theme.negative : AppDomain.settings.color
    }

    @ViewBuilder
    private var subtitleView: some View {
        if let subtitle {
            if needsAttention {
                Label(subtitle, systemImage: SettingsText.attentionSymbol)
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            } else {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func openTarget() {
        if let openPage {
            openPage(page)
        } else {
            router.open(.settings(page))
        }
    }
}

// MARK: - Tekst en acties

/// Een voetnoot onder een sectie, in de uitlegkleur (de systeemkleur van een voetnoot is te zwak).
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// Het label van een actierij in een lijst: een titel met pictogram en eronder een regel uitleg. De rij is een `Button`; de
/// titel staat in de accentkleur (of rood bij iets wat gegevens weggooit).
struct SettingsActionLabel: View {
    let title: String
    let detail: String?
    let symbol: String
    var isDestructive: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .foregroundStyle(isDestructive ? Theme.negative : Theme.accent)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Een melding bovenaan een lijstpagina: een `NoticeCard` zonder de rijachtergrond van de lijst eromheen.
struct SettingsNotice: View {
    let text: String
    var symbol: String = "info.circle.fill"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        NoticeCard(text: text, symbol: symbol, actionTitle: actionTitle, action: action)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Een voortgangsregel in een lijst: een draaiend rondje met een tekst ("Bezig met verwijderen…").
struct SettingsProgressRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Een foutregel bij een knop: symbool en tekst, zodat de betekenis niet alleen in de kleur zit.
struct SettingsErrorRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "xmark.octagon.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.negative)
    }
}
