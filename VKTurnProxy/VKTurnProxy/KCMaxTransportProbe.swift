import Foundation
import Network

/// Lightweight readiness probe for the future MAX transport adapter.
///
/// This does not make MAX eligible for Smart Route by itself. It only answers
/// a narrower question: is the MAX signaling endpoint reachable from the
/// current network, and roughly how long does a TCP connection take?
///
/// A concrete MAX adapter still has to authenticate, obtain TURN credentials,
/// establish the relay, and report real tunnel health before `isConfigured`
/// may become true in `KCSmartTransportManager`.
@MainActor
final class KCMaxTransportProbe: ObservableObject {
    static let shared = KCMaxTransportProbe()

    @Published private(set) var isReachable: Bool?
    @Published private(set) var latencyMs: Double?
    @Published private(set) var lastChecked: Date?

    private let queue = DispatchQueue(label: "kc.max.transport.probe")
    private var timer: Timer?
    private var activeConnection: NWConnection?

    private init() {
        start()
    }

    deinit {
        timer?.invalidate()
        activeConnection?.cancel()
    }

    func start() {
        guard timer == nil else { return }
        runOnce()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runOnce()
            }
        }
    }

    func runOnce() {
        activeConnection?.cancel()

        let startedAt = Date()
        let connection = NWConnection(host: "api.oneme.ru", port: 443, using: .tcp)
        activeConnection = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self?.finish(connection: connection, startedAt: startedAt, reachable: true)
                }
            case .failed, .cancelled:
                Task { @MainActor in
                    self?.finish(connection: connection, startedAt: startedAt, reachable: false)
                }
            default:
                break
            }
        }

        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak connection] in
            guard let connection else { return }
            Task { @MainActor in
                self?.finish(connection: connection, startedAt: startedAt, reachable: false)
            }
        }
    }

    private func finish(connection: NWConnection, startedAt: Date, reachable: Bool) {
        guard activeConnection === connection else { return }

        let elapsed = Date().timeIntervalSince(startedAt) * 1_000
        isReachable = reachable
        latencyMs = reachable ? elapsed : nil
        lastChecked = Date()
        activeConnection = nil
        connection.cancel()
    }
}
