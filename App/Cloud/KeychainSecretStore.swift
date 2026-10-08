import Foundation
#if canImport(Security)
import Security
#endif

#if canImport(Security)
/// Bewaart kleine geheimen (het refresh-token van de login) in de Keychain van het apparaat.
/// Het wachtwoord komt hier nooit in.
struct KeychainSecretStore: SecretStore {
    let service: String

    init(service: String = "nl.mybuddy.app.cloud") {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    func read(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(key)
        let changes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            #if os(iOS)
            // Alleen na de eerste keer ontgrendelen, en niet mee in een back-up naar een ander apparaat.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretStoreError(code: Int(status)) }
    }

    func remove(_ key: String) {
        _ = SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
#endif

/// Probeert eerst de Keychain. Weigert die (bijvoorbeeld een app zonder handtekening op de Mac), dan blijft het
/// geheim tot het afsluiten van de app in het geheugen: je bent ingelogd, maar moet na een herstart opnieuw inloggen.
final class FallbackSecretStore: SecretStore {
    private let primary: (any SecretStore)?
    private let memory = InMemorySecretStore()
    /// Is het geheim ooit alleen in het geheugen bewaard? Dan blijf je niet ingelogd na afsluiten.
    private(set) var usesMemoryOnly = false

    init(primary: (any SecretStore)?) {
        self.primary = primary
        self.usesMemoryOnly = (primary == nil)
    }

    func read(_ key: String) -> String? {
        primary?.read(key) ?? memory.read(key)
    }

    func write(_ value: String, for key: String) throws {
        if let primary {
            do {
                try primary.write(value, for: key)
                memory.remove(key)
                return
            } catch {
                usesMemoryOnly = true
            }
        }
        try memory.write(value, for: key)
    }

    func remove(_ key: String) {
        primary?.remove(key)
        memory.remove(key)
    }

    /// De opslag die de app normaal gebruikt.
    static func standard() -> FallbackSecretStore {
        #if canImport(Security)
        return FallbackSecretStore(primary: KeychainSecretStore())
        #else
        return FallbackSecretStore(primary: nil)
        #endif
    }
}
