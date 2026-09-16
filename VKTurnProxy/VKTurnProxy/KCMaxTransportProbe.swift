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

        var finished = false
        func finish(_ reachable: Bool) {
            guard !finished else { return }
            finished = true
            let elapsed = Date().timeIntervalSince(startedAt) * 1_000
            Task { @MainActor [weak self, weak connection] in
                guard let self else { return }
                if self.activeConnection === connection {
                    self.isReachable = reachable
                    self.latencyMs = reachable ? elapsed : nil
                    self.lastChecked = Date()
                    self.activeConnection = nil
                }
                connection?.cancel()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }

        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 5) {
            finish(false)
        }
    }
}
