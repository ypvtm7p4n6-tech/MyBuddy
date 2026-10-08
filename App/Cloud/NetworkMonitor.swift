import Foundation
import Observation
#if canImport(Network)
import Network
#endif

/// Houdt bij of er internet is, zodat de synchronisatie pauzeert zonder netwerk en daarna meteen inhaalt.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    /// Wordt aangeroepen als er weer internet is gekomen.
    @ObservationIgnored var onReconnect: (() -> Void)?

    #if canImport(Network)
    /// Een geannuleerde monitor kan niet opnieuw starten, dus elke `start()` maakt een nieuwe.
    @ObservationIgnored private var monitor: NWPathMonitor?
    #endif

    init() {}

    func start() {
        #if canImport(Network)
        guard monitor == nil else { return }
        let fresh = NWPathMonitor()
        fresh.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            Task { @MainActor in self?.update(online: online) }
        }
        fresh.start(queue: DispatchQueue(label: "nl.mybuddy.network-monitor", qos: .utility))
        monitor = fresh
        #endif
    }

    func stop() {
        #if canImport(Network)
        monitor?.cancel()
        monitor = nil
        #endif
    }

    private func update(online: Bool) {
        let wasOnline = isOnline
        isOnline = online
        if online && !wasOnline { onReconnect?() }
    }
}
