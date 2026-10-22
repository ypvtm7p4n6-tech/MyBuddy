import Foundation
// Foundation-only: geen SwiftUI. De teksten van Instellingen en Account die uit gegevens volgen staan hier, zodat ze zonder
// scherm te testen zijn (Tests/AppTests/SettingsTextTests.swift).

/// Wat de Account-rij op de lijst Instellingen en de pagina Account over de synchronisatie zeggen.
struct SyncSummary: Equatable {
    var text: String
    /// Een symbool bij de tekst, alleen als er aandacht nodig is.
    var symbol: String?
    var needsAttention: Bool
}

enum SettingsText {
    /// Het symbool bij "Actie nodig" en andere meldingen die aandacht vragen.
    static let attentionSymbol = "exclamationmark.triangle.fill"

    // MARK: Tijd

    /// "9:41" of "14:02": uur zonder voorloopnul, minuten met twee cijfers.
    static func time(_ date: Date, timeZone: TimeZone = TimeZone.current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Fmt.locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }

    /// Dezelfde kalenderdag als `now`: alleen de tijd ("14:02"); anders de datum met tijd ("20 okt 14:02").
    static func moment(_ date: Date, now: Date = Date(), timeZone: TimeZone = TimeZone.current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            return "om " + time(date, timeZone: timeZone)
        }
        return "op " + Fmt.dateTime(date)
    }

    // MARK: Synchronisatie

    /// De korte status voor de Account-rij. Zonder Firebase-sleutel is er geen synchronisatie ("Alleen op dit apparaat");
    /// een conflict of een aanbod om lokale gegevens te uploaden is "Actie nodig".
    static func syncSummary(isConfigured: Bool, status: SyncStatus?, needsAttention: Bool,
                            now: Date = Date(), timeZone: TimeZone = TimeZone.current) -> SyncSummary {
        guard isConfigured else {
            return SyncSummary(text: "Alleen op dit apparaat", symbol: nil, needsAttention: false)
        }
        if needsAttention {
            return SyncSummary(text: "Actie nodig", symbol: attentionSymbol, needsAttention: true)
        }
        guard let status else {
            return SyncSummary(text: "Synchronisatie niet actief", symbol: nil, needsAttention: false)
        }
        switch status {
        case .disabled:
            return SyncSummary(text: "Synchronisatie staat uit", symbol: nil, needsAttention: false)
        case .connecting:
            return SyncSummary(text: "Verbinden…", symbol: nil, needsAttention: false)
        case .busy:
            return SyncSummary(text: "Bezig met synchroniseren…", symbol: nil, needsAttention: false)
        case .synced(let date):
            let when = moment(date, now: now, timeZone: timeZone)
            return SyncSummary(text: "Gesynchroniseerd " + when, symbol: nil, needsAttention: false)
        case .offline:
            return SyncSummary(text: "Offline", symbol: nil, needsAttention: false)
        case .failed:
            return SyncSummary(text: "Synchroniseren mislukt", symbol: nil, needsAttention: false)
        case .conflict:
            return SyncSummary(text: "Actie nodig", symbol: attentionSymbol, needsAttention: true)
        }
    }

    // MARK: Waarden onder de rijen van Instellingen

    /// "Inflatie 2%, spaarrente 2%"
    static func calculationsSummary(inflation: Double, savingsRate: Double) -> String {
        "Inflatie \(Fmt.percent(inflation, digits: 2)), spaarrente \(Fmt.percent(savingsRate, digits: 2))"
    }

    /// "Automatisch, laatst bijgewerkt 9:41" of "Handmatig".
    static func pricesSummary(automatic: Bool, lastRefresh: Date?, now: Date = Date(),
                              timeZone: TimeZone = TimeZone.current) -> String {
        let mode = automatic ? "Automatisch" : "Handmatig"
        guard let lastRefresh else { return mode }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(lastRefresh, inSameDayAs: now) {
            return mode + ", laatst bijgewerkt " + time(lastRefresh, timeZone: timeZone)
        }
        return mode + ", laatst bijgewerkt " + Fmt.dateTime(lastRefresh)
    }

    // MARK: Versie

    /// "Versie 1.0". Zonder versie in de bundel (bijvoorbeeld in een test) is het "Versie 1.0".
    static func versionText(short: String?) -> String {
        "Versie " + cleanVersion(short)
    }

    /// "Versie 1.0 (1)": de versie met het buildnummer erachter, als dat er is en anders is dan de versie.
    static func detailedVersionText(short: String?, build: String?) -> String {
        let version = cleanVersion(short)
        if let build, !build.isEmpty, build != version {
            return "Versie \(version) (\(build))"
        }
        return "Versie " + version
    }

    private static func cleanVersion(_ short: String?) -> String {
        if let short, !short.isEmpty { return short }
        return "1.0"
    }

    /// De versie van de app uit de bundel (`CFBundleShortVersionString`).
    static var appVersionShort: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Het buildnummer van de app uit de bundel (`CFBundleVersion`).
    static var appBuild: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
