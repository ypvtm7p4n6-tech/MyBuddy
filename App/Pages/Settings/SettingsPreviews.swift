#if DEBUG
import SwiftUI

// Previews van de pagina's van Instellingen en Account, met voorbeelddata, in licht, donker en bij grote tekst. De pagina's
// staan in een eigen `NavigationStack`, zoals `TabStack` (iOS) of `SettingsPane` (Mac) dat in de app doet.

/// Maakt een winkel met voorbeelddata, een router en een lokaal account voor de previews.
@MainActor
private struct SettingsPreviewHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router = Router()
    @State private var auth: AuthStore
    @State private var cloud = CloudAccount()
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        let sampleStore = AppStore(storage: nil)
        sampleStore.loadSampleData()
        _store = State(initialValue: sampleStore)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MyBuddySettingsPreview", isDirectory: true)
        let defaults = UserDefaults(suiteName: "nl.mybuddy.settings-preview") ?? UserDefaults.standard
        _auth = State(initialValue: AuthStore(directory: directory, defaults: defaults, iterations: 1))
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
        }
        .environment(store)
        .environment(router)
        .environment(auth)
        .environment(\.cloudAccount, cloud)
    }
}

#Preview("Instellingen, licht") {
    SettingsPreviewHost {
        SettingsView()
    }
    .preferredColorScheme(.light)
}

#Preview("Instellingen, donker") {
    SettingsPreviewHost {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Instellingen, grote tekst") {
    SettingsPreviewHost {
        SettingsView()
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Account") {
    SettingsPreviewHost {
        AccountPage()
    }
}

#Preview("Wachtwoord wijzigen") {
    SettingsPreviewHost {
        PasswordPage()
    }
}

#Preview("Account verwijderen") {
    SettingsPreviewHost {
        DeleteAccountPage()
    }
}

#Preview("Rekenen") {
    SettingsPreviewHost {
        CalculationsPage()
    }
}

#Preview("Koersen") {
    SettingsPreviewHost {
        PricesPage()
    }
}

#Preview("Gegevens") {
    SettingsPreviewHost {
        DataPage()
    }
}

#Preview("Indeling") {
    SettingsPreviewHost {
        LayoutPage()
    }
}

#Preview("Over MyBuddy") {
    SettingsPreviewHost {
        AboutPage()
    }
}

#Preview("Importoverzicht zonder bestand") {
    SettingsPreviewHost {
        SpreadsheetImportPage()
    }
}
#endif
