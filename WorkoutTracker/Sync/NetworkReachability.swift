import Foundation
import Network
import Observation

@Observable
final class NetworkReachability {
    static let shared = NetworkReachability()

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkReachability")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }
}
