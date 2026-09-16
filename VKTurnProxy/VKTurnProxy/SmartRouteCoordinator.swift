import Foundation
import NetworkExtension
import SwiftUI

enum KCRoutingMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Авто"
        case .manual: return "Ручной"
        }
    }
}

/// Connects the deterministic SmartRouteAgent to the running tunnel.
/// It deliberately switches only after three measured failures and never
/// guesses while the statistics channel itself is unavailable.
@MainActor
final class SmartRouteCoordinator: ObservableObject {
    static let shared = SmartRouteCoordinator()

    nonisolated static let modeKey = "kcRoutingMode"

    @Published private(set) var statusText = "Smart Route готов"
    @Published private(set) var isRecovering = false

    private let agent = SmartRouteAgent()
    private var timer: Timer?
    private var consecutiveFailures = 0
    private var lastRecoveryAt = Date.distantPast

    private init() {}

    var mode: KCRoutingMode {
        KCRoutingMode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .automatic
    }

    func start() {
        guard timer == nil else { return }
        evaluate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func modeChanged() {
        consecutiveFailures = 0
        statusText = mode == .automatic
            ? "Smart Route следит за соединением"
            : "Сервер выбирается вручную"
    }

    private func evaluate() {
        let tunnel = TunnelManager.shared
        guard mode == .automatic else {
            statusText = "Ручной выбор сервера"
            consecutiveFailures = 0
            return
        }
        guard tunnel.status == .connected else {
            statusText = isRecovering ? "Восстанавливаю соединение…" : "Ожидаю подключения"
            return
        }
        guard tunnel.live.statsReceivedOnce, !tunnel.live.statsChannelDown else {
            statusText = "Получаю данные соединения…"
            return
        }

        let stats = tunnel.live.stats
        let healthy = stats.activeConns > 0
        consecutiveFailures = healthy ? 0 : consecutiveFailures + 1

        if healthy {
            let rtt = max(stats.turnRTTms, tunnel.live.internetRTTms)
            statusText = rtt > 0 ? "Маршрут стабилен · \(Int(rtt)) мс" : "Маршрут стабилен"
        } else {
            statusText = "Проверка маршрута · \(consecutiveFailures)/3"
        }

        // Do not react during bootstrap and do not flap between servers.
        guard stats.tunnelUptimeSec >= 15,
              consecutiveFailures >= agent.policy.failureThreshold,
              !isRecovering,
              Date().timeIntervalSince(lastRecoveryAt) >= 60 else { return }

        let store = ServerStore.shared
        let alternatives = orderedAlternatives(in: store)
        let current = RouteTelemetry(
            routeID: store.activeServerId.uuidString,
            rttMs: stats.turnRTTms,
            internetRttMs: tunnel.live.internetRTTms,
            packetLoss: 1,
            consecutiveFailures: consecutiveFailures,
            isReachable: false,
            measuredAt: Date()
        )
        // An alternative is a configured candidate, not a claim that MAX or
        // Yandex already has a verified transport. The server profile still
        // defines the actual protocol and credentials.
        let candidates = alternatives.map {
            RouteTelemetry(routeID: $0.id.uuidString, rttMs: 700,
                           internetRttMs: 700, packetLoss: 0,
                           consecutiveFailures: 0, isReachable: true,
                           measuredAt: Date())
        }
        let decision = agent.decide(current: current, alternatives: candidates,
                                    secondsOnCurrent: TimeInterval(stats.tunnelUptimeSec))
        guard decision.action == .switchRoute,
              let selected = decision.selectedRouteID,
              let id = UUID(uuidString: selected) else {
            statusText = "Нет запасного настроенного сервера"
            return
        }

        isRecovering = true
        lastRecoveryAt = Date()
        consecutiveFailures = 0
        statusText = "Переключаю на запасной сервер…"
        SharedLogger.shared.log("[SmartRoute] \(decision.reason) target=\(selected)")
        Task { @MainActor [weak self] in
            await tunnel.switchAndReconnect(to: id, because: .smartRoute)
            self?.isRecovering = false
            self?.statusText = tunnel.status == .connected
                ? "Соединение восстановлено"
                : "Проверяю новое соединение…"
        }
    }

    private func orderedAlternatives(in store: ServerStore) -> [ServerProfile] {
        guard let currentIndex = store.servers.firstIndex(where: { $0.id == store.activeServerId }),
              store.servers.count > 1 else { return [] }
        let after = Array(store.servers.dropFirst(currentIndex + 1))
        let before = Array(store.servers.prefix(currentIndex))
        return (after + before).filter(isConfigured)
    }

    private func isConfigured(_ server: ServerProfile) -> Bool {
        guard !server.peerAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if server.useCsqtt {
            return !server.csqttPassword.isEmpty && !server.csqttDeviceID.isEmpty
        }
        if server.useWrapA {
            return !server.wrapAPassword.isEmpty
        }
        return !server.privateKey.isEmpty
            && !server.peerPublicKey.isEmpty
            && !server.tunnelAddress.isEmpty
    }
}

struct SmartRouteModePanel: View {
    @AppStorage(SmartRouteCoordinator.modeKey) private var modeRaw = KCRoutingMode.automatic.rawValue
    @ObservedObject private var coordinator = SmartRouteCoordinator.shared

    private var selection: Binding<KCRoutingMode> {
        Binding(
            get: { KCRoutingMode(rawValue: modeRaw) ?? .automatic },
            set: { modeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("K&C")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.36, green: 0.22, blue: 0.16))
                    .clipShape(Capsule())
                Text("Smart Route")
                    .font(.headline)
                Spacer()
            }

            Picker("Режим", selection: selection) {
                ForEach(KCRoutingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(coordinator.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(red: 0.96, green: 0.92, blue: 0.86).opacity(0.72))
        .cornerRadius(14)
        .padding(.horizontal)
        .onAppear { coordinator.start() }
        .onChange(of: modeRaw) { _ in coordinator.modeChanged() }
    }
}
