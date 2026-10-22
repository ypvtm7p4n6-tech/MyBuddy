import SwiftUI

// Schermen rond het cloudaccount en het synchroniseren. De pagina's zelf (Account, Wachtwoord wijzigen, Account verwijderen,
// Back-ups van conflicten) staan in App/Pages/Settings/. Hier staan:
// - de teksten van de synchronisatie (`SyncText`) en de statusrij (`SyncStatusRow`)
// - de melding op het Overzicht als de synchronisatie aandacht nodig heeft (`SyncAttentionBanner`)
// - de eis aan een nieuw cloudwachtwoord (`CloudPasswordHint`)
// - tot golf 1c: de meldingen bij het starten (`SyncPromptsHost`), die dan vervallen

// MARK: - Teksten

enum SyncText {
    static func conflictMessage(_ conflict: SyncConflict) -> String {
        let local = conflict.localModified.map { Fmt.dateTime($0) } ?? "onbekend"
        let remote = conflict.remoteModified.map { Fmt.dateTime($0) } ?? "onbekend"
        let device = conflict.remoteDevice.isEmpty ? "" : " door \(conflict.remoteDevice)"
        var text = "Op dit apparaat (gewijzigd op \(local)) en in de cloud (gewijzigd op \(remote)\(device)) staan verschillende gegevens. Welke versie wil je houden? De andere versie bewaar ik eerst als back-up op dit apparaat."
        switch conflict.newerSide {
        case .some(.local): text += " De versie op dit apparaat is nieuwer."
        case .some(.remote): text += " De cloud-versie is nieuwer."
        case .none: break
        }
        return text
    }

    static func importMessage(_ offer: LocalDataCandidate) -> String {
        "Je hebt lokale gegevens op dit apparaat (laatst gewijzigd op \(Fmt.dateTime(offer.modified))). Uploaden naar je account? Staan er in je account al gegevens, dan kies je straks welke versie je houdt."
    }
}

// MARK: - Statusrij

/// De status van de synchronisatie als rij op de pagina Account: een symbool, een titel en een regel uitleg.
struct SyncStatusRow: View {
    let sync: SyncController

    var body: some View {
        let status = sync.displayStatus
        HStack(spacing: 12) {
            SymbolBadge(symbol: symbol(status), color: tint(status), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(status))
                    .font(.headline)
                Text(detail(status))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isWorking(status) {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .animated(by: status)
        .accessibilityElement(children: .combine)
    }

    private func isWorking(_ status: SyncStatus) -> Bool {
        switch status {
        case .busy, .connecting: return true
        default: return false
        }
    }

    private func symbol(_ status: SyncStatus) -> String {
        switch status {
        case .disabled: return "pause.circle"
        case .connecting, .busy: return "arrow.triangle.2.circlepath"
        case .synced: return "checkmark.circle.fill"
        case .offline: return "wifi.slash"
        case .failed: return "exclamationmark.triangle.fill"
        case .conflict: return "arrow.triangle.branch"
        }
    }

    private func tint(_ status: SyncStatus) -> Color {
        switch status {
        case .synced: return Theme.positive
        case .failed: return Theme.negative
        case .conflict, .offline: return Theme.warning
        default: return Theme.accent
        }
    }

    private func title(_ status: SyncStatus) -> String {
        switch status {
        case .disabled: return "Uit"
        case .connecting: return "Verbinden…"
        case .busy: return "Bezig…"
        case .synced: return "Gesynchroniseerd"
        case .offline: return "Offline"
        case .failed: return "Synchroniseren mislukt"
        case .conflict: return "Kies een versie"
        }
    }

    private func detail(_ status: SyncStatus) -> String {
        switch status {
        case .disabled: return "Er wordt niet gesynchroniseerd."
        case .connecting: return "Verbinding met de cloud maken."
        case .busy: return "Je gegevens worden bijgewerkt."
        case .synced(let date): return "Bijgewerkt om \(Fmt.dateTime(date))."
        case .offline: return "Je kunt gewoon doorwerken. Wijzigingen gaan mee zodra er weer internet is."
        case .failed(let text): return text
        case .conflict: return "Op dit apparaat en in de cloud staan verschillende gegevens."
        }
    }
}

// MARK: - Melding op het Overzicht

/// Een melding bovenaan het Overzicht als de synchronisatie aandacht nodig heeft: er is een conflict ("Kies welke versie je
/// houdt") of een aanbod om lokale gegevens te uploaden. De keuze zelf staat op de pagina Account; de knop gaat daarheen. Er is
/// geen melding bij het starten van de app (ALT-5). Zonder aandacht is de view leeg.
struct SyncAttentionBanner: View {
    @Environment(\.syncController) private var sync
    @Environment(Router.self) private var router

    var body: some View {
        if let sync, let text = attentionText(for: sync) {
            NoticeCard(text: text,
                       symbol: SettingsText.attentionSymbol,
                       actionTitle: "Naar Account",
                       action: { router.go(.settings(.account)) })
        }
    }

    /// Het aanbod om te uploaden gaat voor een conflict, zoals de meldingen bij het starten deden.
    private func attentionText(for sync: SyncController) -> String? {
        if sync.importOffer != nil {
            return "Lokale gegevens uploaden? Je hebt gegevens op dit apparaat die nog niet in je account staan."
        }
        if sync.conflict != nil {
            return "Kies welke versie je houdt. Op dit apparaat en in de cloud staan verschillende gegevens."
        }
        return nil
    }
}

// MARK: - Eis aan het wachtwoord

/// De ene eis die de cloud aan een wachtwoord stelt, als vinkje.
struct CloudPasswordHint: View {
    let password: String

    private var isMet: Bool { password.count >= FirebaseAuthClient.minimumPasswordLength }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
            Text("Minstens \(FirebaseAuthClient.minimumPasswordLength) tekens")
        }
        .font(.footnote)
        .foregroundStyle(isMet ? Theme.positive : Theme.textSecondary)
        .animated(by: isMet, quick: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Meldingen bij het starten (vervalt in golf 1c)

/// Toont de meldingen van de synchronisatie bovenop de app. Eén melding tegelijk, want meerdere alerts op
/// dezelfde view overschrijven elkaar. TIJDELIJK: vervangen door `SyncAttentionBanner`; verdwijnt in golf 1c, zodra
/// `MyBuddyApp` de aanroep van `.syncPrompts(_:)` niet meer doet.
struct SyncPromptsHost<Content: View>: View {
    let sync: SyncController?
    let content: Content

    private enum Prompt {
        case importLocal
        case conflict
    }

    private var prompt: Prompt? {
        guard let sync else { return nil }
        if sync.importOffer != nil { return .importLocal }
        if sync.conflict != nil && !sync.conflictPromptDeferred && !sync.isResolving { return .conflict }
        return nil
    }

    private var title: String {
        switch prompt {
        case .some(.importLocal): return "Lokale gegevens uploaden?"
        case .some(.conflict): return "Welke versie wil je houden?"
        case .none: return ""
        }
    }

    private var message: String {
        switch prompt {
        case .some(.importLocal):
            if let offer = sync?.importOffer { return SyncText.importMessage(offer) }
            return ""
        case .some(.conflict):
            if let conflict = sync?.conflict { return SyncText.conflictMessage(conflict) }
            return ""
        case .none:
            return ""
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { _ in })
    }

    var body: some View {
        content.alert(title, isPresented: isPresented) {
            switch prompt {
            case .some(.importLocal):
                Button("Uploaden") { sync?.answerImportOffer(accept: true) }
                Button("Niet uploaden", role: .cancel) { sync?.answerImportOffer(accept: false) }
            case .some(.conflict):
                Button("Bewaar deze versie") { sync?.startResolving(.keepLocal) }
                Button("Neem cloud-versie over") { sync?.startResolving(.takeRemote) }
                Button("Later", role: .cancel) { sync?.deferConflictPrompt() }
            case .none:
                EmptyView()
            }
        } message: {
            Text(message)
        }
    }
}

extension View {
    /// Voegt de meldingen van de synchronisatie toe (lokale gegevens uploaden, conflict). Vervalt in golf 1c.
    func syncPrompts(_ sync: SyncController?) -> some View {
        SyncPromptsHost(sync: sync, content: self)
    }
}
