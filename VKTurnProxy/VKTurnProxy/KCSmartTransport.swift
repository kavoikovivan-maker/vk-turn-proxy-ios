import Foundation
import Combine
import NetworkExtension

/// Product-level transport abstraction for K&C Smart Proxy.
///
/// Provider-specific networking stays outside this selector. Concrete adapters
/// only report health samples; this layer ranks configured, reachable transports.
enum KCTransportKind: String, CaseIterable, Identifiable {
    case vk
    case yandex
    case max
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vk: return "VK"
        case .yandex: return "Yandex"
        case .max: return "MAX"
        case .custom: return "Custom"
        }
    }
}

struct KCTransportHealth: Identifiable, Equatable {
    let kind: KCTransportKind
    var isConfigured: Bool
    var isReachable: Bool
    var latencyMs: Double?
    var consecutiveFailures: Int
    var lastUpdated: Date?

    var id: KCTransportKind { kind }

    var score: Double {
        guard isConfigured, isReachable else { return -.infinity }
        let latencyPenalty = min(latencyMs ?? 1_000, 1_000)
        let failurePenalty = Double(consecutiveFailures) * 250
        return 10_000 - latencyPenalty - failurePenalty
    }

    var latencyLabel: String {
        guard let latencyMs else { return "—" }
        return "\(Int(latencyMs.rounded())) ms"
    }
}

@MainActor
final class KCSmartTransportManager: ObservableObject {
    static let shared = KCSmartTransportManager()

    @Published private(set) var transports: [KCTransportHealth]
    @Published private(set) var selected: KCTransportKind = .vk
    @Published var automaticSelectionEnabled = true

    private var vkBindings = Set<AnyCancellable>()
    private var vkTunnelBound = false

    private init() {
        transports = KCTransportKind.allCases.map { kind in
            KCTransportHealth(
                kind: kind,
                isConfigured: kind == .vk,
                // Do not claim VK is reachable until the running tunnel returns
                // a real stats sample. This avoids a fake green state at launch.
                isReachable: false,
                latencyMs: nil,
                consecutiveFailures: 0,
                lastUpdated: nil
            )
        }
    }

    var selectedDisplayName: String { selected.displayName }

    var selectedHealth: KCTransportHealth? {
        transports.first(where: { $0.kind == selected })
    }

    var selectedLatencyLabel: String {
        selectedHealth?.latencyLabel ?? "—"
    }

    var bestAvailable: KCTransportKind? {
        transports
            .filter { $0.score != -.infinity }
            .max(by: { $0.score < $1.score })?
            .kind
    }

    /// Connect the already-working VK tunnel to Smart Route using real runtime
    /// telemetry from TunnelManager. TURN RTT is measured by the tunnel engine;
    /// statsReceivedOnce prevents the all-zero placeholder from being treated as
    /// a measurement, and statsChannelDown removes VK from eligibility if IPC
    /// telemetry stops arriving while connected.
    func bindVK(to tunnel: TunnelManager) {
        guard !vkTunnelBound else { return }
        vkTunnelBound = true

        Publishers.CombineLatest4(
            tunnel.$status,
            tunnel.live.$stats,
            tunnel.live.$statsReceivedOnce,
            tunnel.live.$statsChannelDown
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] status, stats, received, channelDown in
            guard let self else { return }

            switch status {
            case .connected:
                let reachable = received && !channelDown
                let measuredRTT = stats.turnRTTms > 0 ? stats.turnRTTms : nil
                self.report(
                    kind: .vk,
                    configured: true,
                    reachable: reachable,
                    latencyMs: measuredRTT,
                    countFailure: received && channelDown
                )
            case .connecting, .reasserting:
                self.markWaiting(kind: .vk, configured: true)
            default:
                self.markIdle(kind: .vk, configured: true)
            }
        }
        .store(in: &vkBindings)
    }

    func report(
        kind: KCTransportKind,
        configured: Bool,
        reachable: Bool,
        latencyMs: Double?,
        countFailure: Bool = true
    ) {
        guard let index = transports.firstIndex(where: { $0.kind == kind }) else { return }

        var item = transports[index]
        item.isConfigured = configured
        item.isReachable = reachable
        item.latencyMs = latencyMs
        item.lastUpdated = Date()
        if reachable {
            item.consecutiveFailures = 0
        } else if countFailure {
            item.consecutiveFailures += 1
        }
        transports[index] = item

        if automaticSelectionEnabled {
            chooseBestAvailable()
        }
    }

    func markIdle(kind: KCTransportKind, configured: Bool) {
        guard let index = transports.firstIndex(where: { $0.kind == kind }) else { return }
        var item = transports[index]
        item.isConfigured = configured
        item.isReachable = false
        item.latencyMs = nil
        item.lastUpdated = Date()
        transports[index] = item
    }

    func markWaiting(kind: KCTransportKind, configured: Bool) {
        guard let index = transports.firstIndex(where: { $0.kind == kind }) else { return }
        var item = transports[index]
        item.isConfigured = configured
        item.isReachable = false
        item.latencyMs = nil
        item.lastUpdated = Date()
        transports[index] = item
    }

    func chooseBestAvailable() {
        guard automaticSelectionEnabled, let bestAvailable else { return }
        selected = bestAvailable
    }

    func selectManually(_ kind: KCTransportKind) {
        guard let item = transports.first(where: { $0.kind == kind }), item.isConfigured else { return }
        automaticSelectionEnabled = false
        selected = kind
    }

    func enableAutomaticSelection() {
        automaticSelectionEnabled = true
        chooseBestAvailable()
    }
}
