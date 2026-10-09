import Foundation

/// Instellingen en invoer die per account op het apparaat worden bewaard (UserDefaults). De sleutel is de basisnaam
/// plus een achtervoegsel met het account ("buffer.setup.v1.<account>"). Een account zonder naam is "demo".
/// Zo ziet een tweede account op hetzelfde apparaat niets van het eerste, en kan alles van één account in één keer
/// worden opgeruimd als dat account verdwijnt.
enum AccountPrefs {
    /// De basissleutels van alles wat per account wordt bewaard. Voeg hier een nieuwe sleutel aan toe zodra een
    /// pagina iets per account onthoudt, anders blijft het na het verwijderen van een account achter.
    static var baseKeys: [String] {
        [
            SavingsGoalDraft.storageKey,   // concept van de spaardoel-calculator
            BufferSetup.storageKey,        // keuzes van de buffer-calculator
            PurchaseCalc.wageStorageKey    // zelf ingevuld uurloon van de aankoopcheck
        ]
    }

    /// De sleutel van `base` voor dit account.
    static func key(_ base: String, account: String) -> String {
        base + "." + account
    }

    /// Verwijdert alles wat bij dit account bewaard is (alle `baseKeys` met het achtervoegsel van het account).
    /// Andere accounts en de gedeelde instellingen van het apparaat blijven staan.
    static func clearAll(account: String, defaults: UserDefaults = .standard) {
        for base in baseKeys {
            defaults.removeObject(forKey: key(base, account: account))
        }
    }
}
