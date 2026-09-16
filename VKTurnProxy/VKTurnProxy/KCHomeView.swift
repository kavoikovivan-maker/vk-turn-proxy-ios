import SwiftUI
import NetworkExtension
import UIKit

private let kcInk = Color(white: 0.96)
private let kcCopper = Color(red: 0.23, green: 0.80, blue: 0.45)
private let kcBackground = Color(red: 0.055, green: 0.060, blue: 0.070)
private let kcPanel = Color(red: 0.115, green: 0.120, blue: 0.135)
private let kcRaised = Color(red: 0.17, green: 0.175, blue: 0.19)
private let kcOutline = Color.white.opacity(0.075)

private enum KCHomeSheet: String, Identifiable {
    case route, assistant, tools, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .route: return "Smart Route"
        case .assistant: return "Помощник"
        case .tools: return "Инструменты"
        case .settings: return "Настройки"
        }
    }
}

/// Permanent graphite dashboard. Secondary work appears in a bottom sheet, so the
/// main VPN state and power control are always one dismissal away.
struct KCHomeView: View {
    @ObservedObject var tunnel: TunnelManager
    @ObservedObject private var store = ServerStore.shared
    @ObservedObject private var smartRoute = SmartRouteCoordinator.shared
    @State private var sheet: KCHomeSheet?

    var body: some View {
        ZStack {
            graphiteBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    header
                    KCPowerControl(tunnel: tunnel, server: store.activeServer)
                    routeCard
                    KCNetworkDashboard(live: tunnel.live, connected: tunnel.status == .connected)
                    configuredRoutes
                    activityCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 86)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sheet(item: $sheet) { item in KCHomeBottomSheet(kind: item, tunnel: tunnel) }
        .onAppear { smartRoute.start() }
        .preferredColorScheme(.dark)
    }

    private var graphiteBackground: some View {
        LinearGradient(colors: [Color(red: 0.10, green: 0.105, blue: 0.12), kcBackground],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Color.white.opacity(0.035))
                    .frame(width: 300, height: 300)
                    .offset(x: -170, y: -155)
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(kcCopper.opacity(0.035))
                    .frame(width: 240, height: 240)
                    .offset(x: 145, y: -105)
            }
    }

    private var header: some View {
        HStack(alignment: .top) {
            headerButton("gearshape") { sheet = .settings }
            Spacer()
            VStack(spacing: 0) {
                Text("K&C")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .tracking(-2)
                Text("Smart Proxy").font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(kcInk)
            Spacer()
            headerButton("chart.bar.xaxis") { sheet = .tools }
        }
    }

    private func headerButton(_ image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 21, weight: .medium))
                .foregroundColor(kcInk)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    private var routeCard: some View {
        Button { sheet = .route } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe.europe.africa")
                    .font(.system(size: 24))
                    .foregroundColor(kcCopper)
                    .frame(width: 44, height: 44)
                    .background(kcRaised)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Текущий маршрут").font(.caption).foregroundColor(.secondary)
                    Text(tunnel.serverCaption.subtitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(kcInk).lineLimit(1)
                    Text(smartRoute.statusText).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(kcCopper.opacity(0.7))
            }
            .padding(12)
            .background(kcPanel)
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(kcOutline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var configuredRoutes: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Маршруты").font(.headline).foregroundColor(kcInk)
                Spacer()
                Button("Все") { sheet = .route }.font(.caption).foregroundColor(kcCopper)
            }
            HStack(spacing: 8) {
                ForEach(Array(store.servers.prefix(3))) { server in
                    let active = server.id == store.activeServerId
                    Button {
                        store.activate(server.id)
                        sheet = .route
                    } label: {
                        VStack(spacing: 5) {
                            Text(monogram(server.serverName))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(active ? kcCopper : kcRaised)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(server.serverName).font(.caption2.weight(.semibold)).foregroundColor(kcInk).lineLimit(1)
                            Label(active ? "Выбран" : "Готов", systemImage: "circle.fill")
                                .font(.system(size: 9)).foregroundColor(active ? .green : .secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(kcPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(kcOutline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(0..<max(0, 3 - store.servers.count), id: \.self) { _ in
                    Button { sheet = .settings } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .frame(width: 34, height: 34)
                                .background(kcRaised).clipShape(RoundedRectangle(cornerRadius: 10))
                            Text("Добавить").font(.caption2.weight(.semibold))
                            Text("маршрут").font(.system(size: 9))
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(kcPanel.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Последние события").font(.headline).foregroundColor(kcInk)
            KCEventRow(color: statusColor, text: statusText, time: "сейчас")
            Divider().opacity(0.45)
            KCEventRow(color: .blue, text: smartRoute.statusText, time: "авто")
            if let error = tunnel.errorMessage {
                Divider().opacity(0.45)
                KCEventRow(color: .red, text: error, time: "ошибка")
            }
        }
        .padding(13).background(kcPanel)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(kcOutline, lineWidth: 1))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            KCBottomButton(title: "Главная", icon: "house.fill", selected: sheet == nil) { sheet = nil }
            KCBottomButton(title: "Маршрут", icon: "point.topleft.down.curvedto.point.bottomright.up", selected: sheet == .route) { sheet = .route }
            KCBottomButton(title: "Помощник", icon: "face.smiling", selected: sheet == .assistant) { sheet = .assistant }
            KCBottomButton(title: "Инструменты", icon: "shippingbox", selected: sheet == .tools) { sheet = .tools }
        }
        .padding(.top, 8).padding(.horizontal, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }

    private var statusText: String {
        if tunnel.preBootstrapInProgress { return "Подготавливаю подключение" }
        switch tunnel.status {
        case .connected: return tunnel.directMode ? "VPN готов · интернет напрямую" : "Подключение установлено"
        case .connecting, .reasserting: return "Устанавливаю соединение"
        case .disconnecting: return "Отключаю VPN"
        case .invalid: return "Конфигурация недоступна"
        default: return "VPN отключён"
        }
    }

    private var statusColor: Color {
        switch tunnel.status {
        case .connected: return .green
        case .connecting, .reasserting: return .orange
        case .invalid: return .red
        default: return .gray
        }
    }

    private func monogram(_ name: String) -> String {
        let result = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
        return result.isEmpty ? "K&C" : result
    }
}

private struct KCPowerControl: View {
    @ObservedObject var tunnel: TunnelManager
    let server: ServerProfile
    private var connected: Bool { tunnel.status == .connected }
    private var working: Bool {
        tunnel.preBootstrapInProgress || tunnel.status == .connecting ||
        tunnel.status == .disconnecting || tunnel.status == .reasserting
    }
    private var validationError: String? {
        let defaults = UserDefaults.standard
        let vkLink = defaults.string(forKey: "vkLink") ?? ""
        var issues: [ConfigValidation.Issue?] = [
            ConfigValidation.vkLink(vkLink),
            ConfigValidation.peerAddress(server.peerAddress),
            ConfigValidation.turnOverride(server.turnServerOverride),
        ]
        if server.useCsqtt {
            issues.append(ConfigValidation.csqttPassword(server.csqttPassword))
            issues.append(ConfigValidation.csqttDeviceID(server.csqttDeviceID))
        } else if server.useWrapA {
            issues.append(ConfigValidation.wrapAPassword(server.wrapAPassword))
        } else {
            issues.append(ConfigValidation.wgKey(server.privateKey, label: "Private key", required: true))
            issues.append(ConfigValidation.wgKey(server.peerPublicKey, label: "Peer public key", required: true))
            issues.append(ConfigValidation.wgKey(server.presharedKey, label: "Preshared key", required: false))
            issues.append(ConfigValidation.tunnelAddress(server.tunnelAddress))
            if (!server.useSrtp && server.useWrap) || server.useWrapS {
                issues.append(ConfigValidation.wrapKeyHex(server.wrapKeyHex))
            }
        }
        return issues.compactMap { $0 }.first { $0.severity == .error }?.message
    }

    var body: some View {
        VStack(spacing: 8) {
            Button(action: toggle) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [kcRaised, kcPanel], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 118, height: 118)
                        .shadow(color: Color.black.opacity(0.55), radius: 20, y: 10)
                        .overlay(Circle().stroke(Color.white.opacity(0.09), lineWidth: 1))
                    Circle().stroke(connected ? Color.green.opacity(0.60) : kcCopper.opacity(0.38), lineWidth: 2)
                        .frame(width: 130, height: 130)
                    if working {
                        ProgressView().scaleEffect(1.45).tint(kcCopper)
                    } else {
                        Image(systemName: "power").font(.system(size: 45, weight: .light))
                            .foregroundColor(connected ? .green : kcInk)
                    }
                }
            }
            .buttonStyle(.plain).disabled(working || (!connected && validationError != nil))
            Text(working ? "Подключение…" : (connected ? "Подключено" : "Подключить"))
                .font(.system(size: 21, weight: .semibold)).foregroundColor(connected ? .green : kcCopper)
            Text(connected ? "Интернет работает стабильно" : "Нажмите, чтобы включить Smart VPN")
                .font(.caption).foregroundColor(.secondary)
            if !connected, let validationError {
                Text(validationError)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 2)
    }

    private func toggle() {
        if connected {
            SharedLogger.shared.log("[UI] K&C home power: disconnect")
            tunnel.disconnect()
        } else {
            SharedLogger.shared.log("[UI] K&C home power: connect")
            let config = TunnelConfig.make(for: server)
            Task { await tunnel.connect(config: config) }
        }
    }
}

private struct KCNetworkDashboard: View {
    @ObservedObject var live: TunnelLiveStats
    let connected: Bool
    @State private var pingHistory: [Double] = []
    @State private var rateHistory: [Double] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Показатели").font(.headline).foregroundColor(kcInk)
                Spacer()
                Text("сейчас").font(.caption2).foregroundColor(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(kcRaised).clipShape(Capsule())
            }
            HStack(spacing: 8) {
                KCMetricCard(title: "Задержка", value: pingText, detail: qualityText,
                             tint: pingTint, values: pingHistory, bars: false)
                KCMetricCard(title: "Стабильность", value: stabilityText, detail: connectionText,
                             tint: .green, values: stabilityBars, bars: true)
            }
            HStack(spacing: 8) {
                KCMetricCard(title: "Получение", value: rateText(live.rxRate), detail: "↓ RX",
                             tint: kcCopper, values: rateHistory, bars: false)
                KCUptimeCard(live: live, connected: connected)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                KCCompactMetric(title: "TX", value: bytesText(live.stats.txBytes))
                KCCompactMetric(title: "RX", value: bytesText(live.stats.rxBytes))
                KCCompactMetric(title: "TURN", value: live.stats.turnRTTms > 0 ? "\(Int(live.stats.turnRTTms)) мс" : "—")
                KCCompactMetric(title: "DTLS", value: live.stats.dtlsHandshakeMs > 0 ? "\(Int(live.stats.dtlsHandshakeMs)) мс" : "—")
                KCCompactMetric(title: "Переподкл.", value: connected ? "\(live.stats.reconnects)" : "—")
                KCCompactMetric(title: "Пул", value: connected ? "\(live.stats.credPoolFilled)/\(live.stats.credPoolSize)" : "—")
            }
        }
        .onAppear { capture() }
        .onReceive(timer) { _ in capture() }
    }

    private var ping: Double { live.internetRTTms > 0 ? live.internetRTTms : live.stats.turnRTTms }
    private var pingText: String { ping > 0 ? "\(Int(ping)) мс" : "—" }
    private var pingTint: Color { ping == 0 ? .gray : (ping < 180 ? .green : (ping < 400 ? .orange : .red)) }
    private var qualityText: String { ping == 0 ? "ожидаю данные" : (ping < 180 ? "отлично" : (ping < 400 ? "нормально" : "нестабильно")) }
    private var stability: Int {
        guard connected, live.statsReceivedOnce, live.stats.totalConns > 0 else { return 0 }
        return min(100, max(0, Int(Double(live.stats.activeConns) / Double(live.stats.totalConns) * 100)))
    }
    private var stabilityText: String { connected ? "\(stability)%" : "—" }
    private var connectionText: String { connected ? "\(live.stats.activeConns)/\(live.stats.totalConns) соединений" : "VPN выключен" }
    private var stabilityBars: [Double] {
        let base = Double(max(stability, 8))
        return [base * 0.42, base * 0.55, base * 0.67, base * 0.75, base * 0.88, base]
    }

    private func capture() {
        guard connected else { pingHistory = []; rateHistory = []; return }
        if ping > 0 { pingHistory = Array((pingHistory + [ping]).suffix(18)) }
        rateHistory = Array((rateHistory + [max(live.rxRate, 0)]).suffix(18))
    }

    private func rateText(_ value: Double) -> String {
        if value >= 1_048_576 { return String(format: "%.1f МБ/с", value / 1_048_576) }
        if value >= 1024 { return String(format: "%.0f КБ/с", value / 1024) }
        return value > 0 ? String(format: "%.0f Б/с", value) : "—"
    }
    private func bytesText(_ value: Int64) -> String {
        guard connected, live.statsReceivedOnce else { return "—" }
        let number = Double(value)
        if number >= 1_073_741_824 { return String(format: "%.1f ГБ", number / 1_073_741_824) }
        if number >= 1_048_576 { return String(format: "%.1f МБ", number / 1_048_576) }
        if number >= 1024 { return String(format: "%.0f КБ", number / 1024) }
        return "\(value) Б"
    }
}

private struct KCCompactMetric: View {
    let title: String, value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(kcInk).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8).background(kcRaised.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(kcOutline, lineWidth: 1))
    }
}

private struct KCMetricCard: View {
    let title: String, value: String, detail: String
    let tint: Color
    let values: [Double]
    let bars: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundColor(kcInk)
            KCMiniChart(values: values, tint: tint, bars: bars).frame(height: 25)
            Label(detail, systemImage: "circle.fill").font(.system(size: 9)).foregroundColor(tint).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(kcPanel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(kcOutline, lineWidth: 1))
    }
}

private struct KCUptimeCard: View {
    @ObservedObject var live: TunnelLiveStats
    let connected: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 5) {
                Text("Время работы").font(.caption).foregroundColor(.secondary)
                Text(uptime(at: context.date)).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundColor(kcInk)
                Spacer(minLength: 4)
                Label(connected ? "активно" : "VPN выключен", systemImage: "clock")
                    .font(.system(size: 9)).foregroundColor(connected ? .green : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 79, alignment: .leading).padding(12).background(kcPanel)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(kcOutline, lineWidth: 1))
        }
    }
    private func uptime(at date: Date) -> String {
        guard connected, let start = live.connectedAt else { return "—" }
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) ч \(minutes) мин" : "\(minutes) мин"
    }
}

private struct KCMiniChart: View {
    let values: [Double]
    let tint: Color
    let bars: Bool
    var body: some View {
        GeometryReader { geo in
            if values.isEmpty {
                Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 2).offset(y: geo.size.height / 2)
            } else if bars {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Capsule().fill(tint.opacity(0.35 + min(0.55, value / 160)))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(4, geo.size.height * CGFloat(value / max(values.max() ?? 1, 1))))
                    }
                }
            } else {
                Path { path in
                    let high = max(values.max() ?? 1, 1), low = values.min() ?? 0
                    let range = max(high - low, high * 0.12, 1)
                    for (index, value) in values.enumerated() {
                        let x = values.count == 1 ? geo.size.width / 2 : geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geo.size.height - geo.size.height * CGFloat((value - low) / range) * 0.82 - 2
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(tint.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct KCEventRow: View {
    let color: Color, text: String, time: String
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).lineLimit(1)
            Spacer()
            Text(time).font(.caption2).foregroundColor(.secondary)
        }
    }
}

private struct KCBottomButton: View {
    let title: String, icon: String, selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(title).font(.system(size: 10, weight: selected ? .semibold : .regular))
            }
            .foregroundColor(selected ? kcCopper : .secondary)
            .frame(maxWidth: .infinity).padding(.bottom, 6)
        }
        .buttonStyle(.plain)
    }
}

private struct KCHomeBottomSheet: View {
    let kind: KCHomeSheet
    @ObservedObject var tunnel: TunnelManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                switch kind {
                case .route: KCRouteSheet(tunnel: tunnel)
                case .assistant: KCAssistantSheet(tunnel: tunnel)
                case .tools: KCToolsSheet(tunnel: tunnel)
                case .settings: SettingsView()
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 23))
                            .foregroundColor(kcCopper)
                    }
                    .accessibilityLabel("Закрыть панель")
                }
            }
        }
        .kcBottomSheetPresentation()
        .preferredColorScheme(.dark)
    }
}

private struct KCRouteSheet: View {
    @ObservedObject var tunnel: TunnelManager
    @ObservedObject private var store = ServerStore.shared
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SmartRouteModePanel().padding(.horizontal, -16)
                TrafficRouteModePanel(tunnel: tunnel).padding(.horizontal, -16)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Настроенные маршруты").font(.headline)
                    ForEach(store.servers) { server in
                        Button { store.activate(server.id) } label: {
                            HStack {
                                Image(systemName: server.id == store.activeServerId ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(server.id == store.activeServerId ? .green : .secondary)
                                VStack(alignment: .leading) {
                                    Text(server.serverName).foregroundColor(.primary)
                                    Text(server.modeLabel).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12).background(Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(kcBackground)
    }
}

private struct KCAssistantSheet: View {
    @ObservedObject var tunnel: TunnelManager
    @ObservedObject private var coordinator = SmartRouteCoordinator.shared
    @State private var question = ""
    @State private var answer = "Я слежу за соединением и подскажу, что происходит."

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").foregroundColor(kcCopper)
                Text(answer).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14).background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            Button("Почему выбран этот маршрут?") {
                answer = coordinator.statusText + ". Активный профиль: " + ServerStore.shared.activeServer.serverName + "."
            }
            .buttonStyle(KCWideButtonStyle())
            Button("Как качество интернета?") {
                let ping = tunnel.live.internetRTTms
                answer = ping > 0
                    ? "Текущая задержка \(Int(ping)) мс. " + (ping < 180 ? "Соединение хорошее." : "Есть заметная задержка.")
                    : "Пока собираю реальные показатели соединения."
            }
            .buttonStyle(KCWideButtonStyle())

            HStack {
                TextField("Задайте вопрос…", text: $question).textFieldStyle(.roundedBorder)
                Button {
                    guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    answer = "Вопрос сохранён. Полного агента подключим к этому окну; данные VPN уже доступны."
                    question = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundColor(kcCopper)
                }
            }
            Spacer()
        }
        .padding(16).background(kcBackground)
    }
}

private enum KCToolPanel {
    case calculator
}

private struct KCToolsSheet: View {
    let tunnel: TunnelManager
    @State private var panel: KCToolPanel?
    var body: some View {
        Group {
            if panel == .calculator {
                VStack(spacing: 10) {
                    HStack {
                        Text("Калькулятор")
                            .font(.headline)
                            .foregroundColor(kcInk)
                        Spacer()
                        Button { withAnimation(.easeInOut(duration: 0.22)) { panel = nil } } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(kcCopper)
                        }
                        .accessibilityLabel("Свернуть калькулятор")
                    }
                    KCCalculatorView()
                }
                .padding(16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        Button { withAnimation(.easeInOut(duration: 0.22)) { panel = .calculator } } label: {
                            KCCompactTool(icon: "plus.forwardslash.minus", title: "Калькулятор",
                                          subtitle: "Вычисления")
                        }
                        .buttonStyle(.plain)
                        NavigationLink(destination: SpeedTestView(tunnel: tunnel)) {
                            KCCompactTool(icon: "speedometer", title: "Скорость",
                                          subtitle: "Тест сети")
                        }
                        NavigationLink(destination: LogsView(tunnel: tunnel)) {
                            KCCompactTool(icon: "waveform.path.ecg", title: "Диагностика",
                                          subtitle: "Состояние VPN")
                        }
                        NavigationLink(destination: SettingsView()) {
                            KCCompactTool(icon: "gearshape", title: "Настройки",
                                          subtitle: "Все параметры")
                        }
                    }
                    .padding(16)
                }
                .transition(.opacity)
            }
        }
        .background(kcBackground)
    }
}

private struct KCCompactTool: View {
    let icon: String, title: String, subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundColor(kcCopper)
                .frame(width: 40, height: 40).background(kcRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(kcInk)
                Text(subtitle).font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(13).background(kcPanel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(kcOutline, lineWidth: 1))
    }
}

private struct KCCalculatorView: View {
    @State private var display = "0"
    @State private var stored: Double?
    @State private var operation: String?
    @State private var startsNewNumber = true
    private let rows = [["7","8","9","÷"], ["4","5","6","×"], ["1","2","3","−"], ["C","0","=","+"]]

    var body: some View {
        VStack(spacing: 8) {
            Text(display)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .trailing).padding(14).background(kcRaised)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .lineLimit(1).minimumScaleFactor(0.5)
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button(key) { tap(key) }
                            .font(.title3.weight(.semibold))
                            .foregroundColor(isAction(key) ? .white : kcInk)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(isAction(key) ? kcCopper : kcRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(12).background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func isAction(_ key: String) -> Bool { ["÷","×","−","+","="].contains(key) }
    private func tap(_ key: String) {
        if let digit = Int(key) {
            display = startsNewNumber || display == "0" ? String(digit) : display + String(digit)
            startsNewNumber = false
        } else if key == "C" {
            display = "0"; stored = nil; operation = nil; startsNewNumber = true
        } else if key == "=" {
            calculate(); operation = nil; stored = nil; startsNewNumber = true
        } else if ["÷","×","−","+"].contains(key) {
            if operation != nil && !startsNewNumber { calculate() }
            stored = Double(display); operation = key; startsNewNumber = true
        }
    }

    private func calculate() {
        guard let lhs = stored, let op = operation, let rhs = Double(display) else { return }
        let value: Double
        switch op {
        case "+": value = lhs + rhs
        case "−": value = lhs - rhs
        case "×": value = lhs * rhs
        case "÷": value = rhs == 0 ? .nan : lhs / rhs
        default: return
        }
        display = value.isFinite ? String(format: value.rounded() == value ? "%.0f" : "%.6g", value) : "Ошибка"
    }
}

private struct KCWideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium)).foregroundColor(kcInk)
            .frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(Color(UIColor.secondarySystemBackground).opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private extension View {
    @ViewBuilder func kcBottomSheetPresentation() -> some View {
        if #available(iOS 16.4, *) {
            self
                .presentationDetents([.fraction(0.48), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(kcBackground)
        } else if #available(iOS 16.0, *) {
            self.presentationDetents([.fraction(0.48), .large]).presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}
