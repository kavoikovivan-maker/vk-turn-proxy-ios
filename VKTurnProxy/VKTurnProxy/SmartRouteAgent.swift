import Foundation

/// K&C Smart Route decision core.
/// Pure Swift on purpose: it can be unit-tested without NetworkExtension.
struct RouteTelemetry: Codable, Equatable {
    let routeID: String
    let rttMs: Double
    let internetRttMs: Double
    let packetLoss: Double
    let consecutiveFailures: Int
    let isReachable: Bool
    let measuredAt: Date
}

enum RouteHealth: String, Codable {
    case excellent, good, degraded, failed
}

enum RecoveryAction: String, Codable {
    case keepCurrent
    case probeAlternatives
    case reconnectCurrent
    case switchRoute
    case fallBackToDirect
    case reportFailure
}

struct SmartRouteDecision: Codable, Equatable {
    let action: RecoveryAction
    let selectedRouteID: String?
    let health: RouteHealth
    let reason: String
    let score: Double
}

struct SmartRoutePolicy {
    var degradedRttMs: Double = 350
    var failedRttMs: Double = 1200
    var degradedLoss: Double = 0.08
    var failedLoss: Double = 0.35
    var failureThreshold: Int = 3
    var switchImprovement: Double = 0.20
    var minimumHoldSeconds: TimeInterval = 20
}

/// Deterministic safety layer. An AI assistant may explain these decisions,
/// but it does not get unrestricted access to NetworkExtension settings.
struct SmartRouteAgent {
    var policy = SmartRoutePolicy()

    func health(of t: RouteTelemetry) -> RouteHealth {
        if !t.isReachable || t.consecutiveFailures >= policy.failureThreshold || t.packetLoss >= policy.failedLoss || t.internetRttMs >= policy.failedRttMs {
            return .failed
        }
        if t.packetLoss >= policy.degradedLoss || t.internetRttMs >= policy.degradedRttMs {
            return .degraded
        }
        if t.internetRttMs < 180 && t.packetLoss < 0.02 { return .excellent }
        return .good
    }

    /// Lower is better. Loss and failures intentionally dominate latency.
    func score(_ t: RouteTelemetry) -> Double {
        // Keep decisions JSON-encodable when they are written to the event
        // store. JSONEncoder rejects IEEE infinity.
        guard t.isReachable else { return Double.greatestFiniteMagnitude }
        return t.internetRttMs + t.rttMs * 0.35 + t.packetLoss * 3000 + Double(t.consecutiveFailures) * 500
    }

    func decide(current: RouteTelemetry, alternatives: [RouteTelemetry], secondsOnCurrent: TimeInterval) -> SmartRouteDecision {
        let currentHealth = health(of: current)
        let currentScore = score(current)
        let viable = alternatives.filter { health(of: $0) != .failed }.sorted { score($0) < score($1) }

        if currentHealth == .failed {
            if let best = viable.first {
                return .init(action: .switchRoute, selectedRouteID: best.routeID, health: currentHealth, reason: "Текущий маршрут недоступен. Переключаюсь на проверенный доступный маршрут.", score: score(best))
            }
            return .init(action: .fallBackToDirect, selectedRouteID: nil, health: currentHealth, reason: "Рабочих туннельных маршрутов не найдено. Проверяю прямое соединение.", score: currentScore)
        }

        if currentHealth == .degraded {
            guard secondsOnCurrent >= policy.minimumHoldSeconds else {
                return .init(action: .probeAlternatives, selectedRouteID: nil, health: currentHealth, reason: "Качество снизилось. Проверяю альтернативы без преждевременного переключения.", score: currentScore)
            }
            if let best = viable.first, score(best) < currentScore * (1 - policy.switchImprovement) {
                return .init(action: .switchRoute, selectedRouteID: best.routeID, health: currentHealth, reason: "Найден заметно более устойчивый маршрут.", score: score(best))
            }
            return .init(action: .reconnectCurrent, selectedRouteID: current.routeID, health: currentHealth, reason: "Лучшей альтернативы нет. Восстанавливаю текущий маршрут.", score: currentScore)
        }

        return .init(action: .keepCurrent, selectedRouteID: current.routeID, health: currentHealth, reason: "Соединение стабильно.", score: currentScore)
    }
}

struct SmartRouteEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let telemetry: RouteTelemetry
    let decision: SmartRouteDecision
}

final class SmartRouteEventStore {
    private let url: URL
    private let encoder = JSONEncoder()

    init(url: URL) { self.url = url }

    func append(_ event: SmartRouteEvent) throws {
        var events = (try? load()) ?? []
        events.append(event)
        if events.count > 500 { events.removeFirst(events.count - 500) }
        let data = try encoder.encode(events)
        try data.write(to: url, options: .atomic)
    }

    func load() throws -> [SmartRouteEvent] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([SmartRouteEvent].self, from: data)
    }
}
