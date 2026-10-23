import SwiftUI

// De profielknop rechtsboven op de drie tabwortels (Apple Muziek en Apple TV): een ronde knop die de pagina Instellingen opent
// (B3 van docs/design2/plan.md). Een stip meldt dat de synchronisatie aandacht vraagt. Alleen op iPhone en iPad: op de Mac staat
// Instellingen in het `Settings`-venster (Cmd+komma).

/// De ronde knop met je initiaal (of een persoon) in de olijfkleur. Een tik opent `Destination.settingsRoot` op de stapel waar je
/// bent. De knop heeft geen eigen achtergrond: op iOS 26 geeft het systeem hem glas.
struct ProfileButton: View {
    @Environment(Router.self) private var router
    @Environment(AuthStore.self) private var auth: AuthStore?
    @Environment(\.cloudAccount) private var cloud
    @Environment(\.syncController) private var sync
    @ScaledMetric(relativeTo: .body) private var baseSide: CGFloat = 32

    init() {}

    /// Vraagt de synchronisatie aandacht: een conflict, of een aanbod om lokale gegevens te uploaden?
    private var needsAttention: Bool {
        sync?.importOffer != nil || sync?.conflict != nil
    }

    /// De eerste letter van de naam of het e-mailadres van het account, hoofdletter; nil als die niet bekend is.
    private var initial: String? {
        var name: String?
        if FirebaseConfig.isConfigured, let user = cloud?.user {
            name = user.email
        } else if let account = auth?.currentAccount {
            name = account.displayName ?? account.email
        }
        guard let first = name?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).capitalized
    }

    var body: some View {
        Button {
            router.open(.settingsRoot)
        } label: {
            avatar
                .overlay(alignment: .topTrailing) { attentionDot }
                .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(needsAttention ? "Account en instellingen, actie nodig" : "Account en instellingen")
        .help("Account en instellingen")
    }

    private var avatar: some View {
        let side = min(baseSide, 48)
        return GradientSurface(hue: .olive, radius: side / 2) {
            avatarContent
                .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let initial {
            Text(initial)
                .font(.subheadline.weight(.semibold))
        } else {
            Image(systemName: "person.fill")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var attentionDot: some View {
        if needsAttention {
            Circle()
                .fill(Theme.warning)
                .frame(width: 10, height: 10)
                .overlay { Circle().strokeBorder(Theme.canvas, lineWidth: 2) }
                .offset(x: 2, y: -2)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Zet de profielknop rechtsboven in de werkbalk (`.primaryAction`). Op de Mac doet dit niets: daar staat Instellingen in het
    /// `Settings`-venster.
    @ViewBuilder
    func profileToolbarItem() -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                ProfileButton()
            }
        }
        #else
        self
        #endif
    }
}
