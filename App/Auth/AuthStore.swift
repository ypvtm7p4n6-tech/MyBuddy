import SwiftUI
import Observation

// TIJDELIJKE STUB: wordt vervangen door echte lokale accounts.
struct Account: Identifiable, Codable, Equatable {
    var id: UUID
    var email: String
    var displayName: String?
    var createdAt: Date
}

@MainActor
@Observable
final class AuthStore {
    private(set) var currentAccount: Account? = Account(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                                        email: "lokaal", displayName: nil, createdAt: Date())

    func storageURL(for account: Account) -> URL { FinanceStorage.standard().url }
    func signOut() {}
}
