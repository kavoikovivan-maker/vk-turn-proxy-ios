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

    /// Pre-flight reachability of a provider endpoint. This is deliberately
    /// separate from `isReachable`: a provider can answer a TCP probe while its
    /// actual tunnel adapter is still not configured or not healthy.
    var probeReachable: Bool?
    var probeLatencyMs: Double?

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

    var probeLatencyLabel: String {
        guard let probeLatencyMs else { return "—" }
        return "\(Int(probeLatencyMs.rounded())) ms"
    }
}

@MainActor
final class KCSmartTransportManager: ObservableObject {
    static let shared = KCSmartTransportManager()

    @Published private(set) var transports: [KCTransportHealth]
    @Published private(set) var selected: KCTransportKind = .vk
    @Published private(set) var lastSwitchReason = "Начальный маршрут"
    @Published private(set) var lastSwitchAt: Date?
    @Published var automaticSelectionEnabled = true

    /// Stability controls for future multi-provider failover.
    /// A single bad sample must not make Smart Route flap between transports.
    private let failureThreshold = 2
    private let minimumDwellTime: TimeInterval = 20
    private let scoreImprovementRequired: Double = 120

    private var bindings = Set<AnyCancellable>()
    private var vkTunnelBound = false
    private var maxProbeBound = false

    private init() {
        transports = KCTransportKind.allCases.map { kind in
            KCTransportHealth(
                kind: kind,
                isConfigured: kind == .vk,
                isReachable: false,
                latencyMs: nil,
                consecutiveFailures: 0,
                lastUpdated: nil,
                probeReachable: nil,
                probeLatencyMs: nil
            )
        }

        // VK is the first concrete transport adapter. MAX currently has a
        // pre-flight endpoint probe only; it remains ineligible for routing
        // until its concrete tunnel adapter is connected.
        bindVK(to: TunnelManager.shared)
        bindMAXProbe(to: KCMaxTransportProbe.shared)
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
            .filter { $0.isConfigured && $0.isReachable }
            .max(by: { $0.score < $1.score })?
            .kind
    }

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
        .store(in: &bindings)
    }

    /// MAX pre-flight probe. This only tells us whether the signaling endpoint
    /// can be reached from the current network. It never makes MAX selectable.
    func bindMAXProbe(to probe: KCMaxTransportProbe) {
        guard !maxProbeBound else { return }
        maxProbeBound = true

        Publishers.CombineLatest(probe.$isReachable, probe.$latencyMs)
            .receive(on: RunLoop.main)
            .sink { [weak self] reachable, latency in
                guard let self else { return }
                self.reportProbe(kind: .max, reachable: reachable, latencyMs: latency)
            }
            .store(in: &bindings)
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
            chooseBestAvailable(reason: reachable ? "Лучшее качество маршрута" : "Потеря качества текущего транспорта")
        }
    }

    func reportProbe(kind: KCTransportKind, reachable: Bool?, latencyMs: Double?) {
        guard let index = transports.firstIndex(where: { $0.kind == kind }) else { return }
        var item = transports[index]
        item.probeReachable = reachable
        item.probeLatencyMs = reachable == true ? latencyMs : nil
        item.lastUpdated = Date()
        transports[index] = item
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

    func chooseBestAvailable(reason: String = "Автоматический выбор") {
        guard automaticSelectionEnabled, let best = bestAvailable else { return }
        guard best != selected else { return }

        let now = Date()
        let current = selectedHealth
        let candidate = transports.first(where: { $0.kind == best })

        // If the current route is still healthy, avoid cosmetic switches for
        // small RTT changes. The candidate must be materially better and the
        // current transport must have stayed selected for a minimum interval.
        if let current, current.isReachable {
            if let lastSwitchAt, now.timeIntervalSince(lastSwitchAt) < minimumDwellTime {
                return
            }
            guard let candidate, candidate.score >= current.score + scoreImprovementRequired else {
                return
            }
        } else if let current, current.consecutiveFailures < failureThreshold {
            // One failed health sample can be transient. Keep the current
            // selection until failure is confirmed by a second sample.
            return
        }

        selected = best
        lastSwitchAt = now
        lastSwitchReason = reason
        SharedLogger.shared.log("[Smart Route] switched to \(best.displayName): \(reason)")
    }

    func selectManually(_ kind: KCTransportKind) {
        guard let item = transports.first(where: { $0.kind == kind }), item.isConfigured else { return }
        automaticSelectionEnabled = false
        selected = kind
        lastSwitchAt = Date()
        lastSwitchReason = "Выбрано вручную"
        SharedLogger.shared.log("[Smart Route] manual selection: \(kind.displayName)")
    }

    func enableAutomaticSelection() {
        automaticSelectionEnabled = true
        lastSwitchReason = "Автоматический режим включён"
        chooseBestAvailable(reason: "Автоматический режим включён")
    }
}
