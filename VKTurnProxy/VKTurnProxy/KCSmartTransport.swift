import Foundation

/// Product-level transport abstraction for K&C Smart Proxy.
///
/// This layer deliberately does not hard-code provider endpoints. Each concrete
/// transport adapter reports health samples here; the selector then ranks only
/// adapters that are configured and available. That keeps routing policy
/// separate from provider-specific networking code.
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
}

@MainActor
final class KCSmartTransportManager: ObservableObject {
    static let shared = KCSmartTransportManager()

    @Published private(set) var transports: [KCTransportHealth]
    @Published private(set) var selected: KCTransportKind = .vk
    @Published var automaticSelectionEnabled = true

    private init() {
        transports = KCTransportKind.allCases.map { kind in
            // VK is the currently integrated production transport. Other
            // adapters become eligible only after their concrete networking
            // implementation reports itself configured.
            KCTransportHealth(
                kind: kind,
                isConfigured: kind == .vk,
                isReachable: kind == .vk,
                latencyMs: nil,
                consecutiveFailures: 0,
                lastUpdated: nil
            )
        }
    }

    var selectedDisplayName: String {
        selected.displayName
    }

    var bestAvailable: KCTransportKind? {
        transports.max(by: { $0.score < $1.score })?.score == -.infinity
            ? nil
            : transports.max(by: { $0.score < $1.score })?.kind
    }

    func report(
        kind: KCTransportKind,
        configured: Bool,
        reachable: Bool,
        latencyMs: Double?
    ) {
        guard let index = transports.firstIndex(where: { $0.kind == kind }) else { return }

        var item = transports[index]
        item.isConfigured = configured
        item.isReachable = reachable
        item.latencyMs = latencyMs
        item.lastUpdated = Date()
        item.consecutiveFailures = reachable ? 0 : item.consecutiveFailures + 1
        transports[index] = item

        if automaticSelectionEnabled {
            chooseBestAvailable()
        }
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
