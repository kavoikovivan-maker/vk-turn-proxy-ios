import SwiftUI
import NetworkExtension
import UIKit
import UniformTypeIdentifiers

private var kcDarkTheme: Bool { UserDefaults.standard.object(forKey: "kcDarkTheme") as? Bool ?? true }
private var kcPureBlack: Bool { UserDefaults.standard.bool(forKey: "kcPureBlack") }
private var kcInk: Color { kcDarkTheme ? Color(white: 0.96) : Color(white: 0.08) }
private let kcCopper = Color(red: 0.23, green: 0.80, blue: 0.45)
private var kcBackground: Color {
    kcDarkTheme ? (kcPureBlack ? .black : Color(red: 0.055, green: 0.060, blue: 0.070))
                : Color(red: 0.955, green: 0.945, blue: 0.925)
}
private var kcPanel: Color {
    kcDarkTheme ? (kcPureBlack ? Color(white: 0.075) : Color(red: 0.115, green: 0.120, blue: 0.135))
                : Color.white.opacity(0.88)
}
private var kcRaised: Color {
    kcDarkTheme ? (kcPureBlack ? Color(white: 0.13) : Color(red: 0.17, green: 0.175, blue: 0.19))
                : Color(red: 0.89, green: 0.88, blue: 0.86)
}
private var kcOutline: Color { kcDarkTheme ? Color.white.opacity(0.075) : Color.black.opacity(0.08) }

private enum KCHomeTab: Int, CaseIterable {
    case home, route, assistant, tools, settings
    var title: String {
        switch self {
        case .home: return "Главная"
        case .route: return "Smart Route"
        case .assistant: return "Помощник"
        case .tools: return "Инструменты"
        case .settings: return "Настройки"
        }
    }
}

/// Permanent graphite dashboard with five full-screen sections. The bottom bar
/// stays in place while the selected page slides horizontally, like a native
/// iPhone tab interface; none of the primary sections is presented as a sheet.
struct KCHomeView: View {
    @ObservedObject var tunnel: TunnelManager
    @ObservedObject private var store = ServerStore.shared
    @ObservedObject private var smartRoute = SmartRouteCoordinator.shared
    @State private var selectedTab: KCHomeTab = .home
    @State private var transitionForward = true
    @AppStorage("kcDarkTheme") private var darkTheme = true
    @AppStorage("kcPureBlack") private var pureBlack = false

    var body: some View {
        ZStack {
            graphiteBackground.ignoresSafeArea()
            page(for: selectedTab)
                .id(selectedTab.rawValue)
                .transition(.asymmetric(
                    insertion: .move(edge: transitionForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: transitionForward ? .leading : .trailing).combined(with: .opacity)
                ))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .onAppear { smartRoute.start() }
        .preferredColorScheme(darkTheme ? .dark : .light)
    }

    @ViewBuilder
    private func page(for tab: KCHomeTab) -> some View {
        switch tab {
        case .home:
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
                .padding(.bottom, 16)
            }
        case .route:
            KCFullSectionPage(title: tab.title, onBack: { select(.home) }) {
                KCRouteSheet(tunnel: tunnel)
            }
        case .assistant:
            KCFullSectionPage(title: tab.title, onBack: { select(.home) }) {
                KCAssistantSheet(tunnel: tunnel)
            }
        case .tools:
            KCFullSectionPage(title: tab.title, onBack: { select(.home) }) {
                KCToolsSheet(tunnel: tunnel)
            }
        case .settings:
            KCFullSettingsPage(tunnel: tunnel) { select(.home) }
        }
    }

    private var graphiteBackground: some View {
        LinearGradient(colors: [darkTheme ? (pureBlack ? .black : Color(red: 0.10, green: 0.105, blue: 0.12))
                                           : Color(red: 0.99, green: 0.97, blue: 0.93), kcBackground],
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
            headerButton("gearshape") { select(.settings) }
            Spacer()
            VStack(spacing: 0) {
                Text("K&C")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .tracking(-2)
                Text("Smart Proxy").font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(kcInk)
            Spacer()
            headerButton("chart.bar.xaxis") { select(.tools) }
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
        Button { select(.route) } label: {
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
                Button("Все") { select(.route) }.font(.caption).foregroundColor(kcCopper)
            }
            HStack(spacing: 8) {
                ForEach(Array(store.servers.prefix(3))) { server in
                    let active = server.id == store.activeServerId
                    Button {
                        store.activate(server.id)
                        select(.route)
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
                    Button { select(.settings) } label: {
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
            KCBottomButton(title: "Главная", icon: "house.fill", selected: selectedTab == .home) { select(.home) }
            KCBottomButton(title: "Маршрут", icon: "point.topleft.down.curvedto.point.bottomright.up", selected: selectedTab == .route) { select(.route) }
            KCBottomButton(title: "Помощник", icon: "face.smiling", selected: selectedTab == .assistant) { select(.assistant) }
            KCBottomButton(title: "Инструменты", icon: "shippingbox", selected: selectedTab == .tools) { select(.tools) }
            KCBottomButton(title: "Настройки", icon: "gearshape.fill", selected: selectedTab == .settings) { select(.settings) }
        }
        .padding(.top, 8).padding(.horizontal, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }

    private func select(_ tab: KCHomeTab) {
        guard tab != selectedTab else { return }
        transitionForward = tab.rawValue > selectedTab.rawValue
        withAnimation(.easeInOut(duration: 0.26)) { selectedTab = tab }
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

private struct KCFullSectionPage<Content: View>: View {
    let title: String
    let onBack: () -> Void
    let content: Content

    init(title: String, onBack: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onBack = onBack
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(kcCopper)
                        .frame(width: 40, height: 40)
                }
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(kcInk)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            Divider().opacity(0.35)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(kcBackground.ignoresSafeArea())
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
    case calculator, speed, logs
}

private struct KCToolsSheet: View {
    let tunnel: TunnelManager
    @State private var panel: KCToolPanel?
    var body: some View {
        Group {
            if let panel {
                KCSlidingPanel(title: toolTitle(panel), onBack: { show(nil) }) {
                    switch panel {
                    case .calculator: KCCalculatorView()
                    case .speed: SpeedTestView(tunnel: tunnel)
                    case .logs: LogsView(tunnel: tunnel)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        Button { show(.calculator) } label: {
                            KCCompactTool(icon: "plus.forwardslash.minus", title: "Калькулятор",
                                          subtitle: "Вычисления")
                        }
                        .buttonStyle(.plain)
                        Button { show(.speed) } label: {
                            KCCompactTool(icon: "speedometer", title: "Скорость",
                                          subtitle: "Тест сети")
                        }.buttonStyle(.plain)
                        Button { show(.logs) } label: {
                            KCCompactTool(icon: "waveform.path.ecg", title: "Диагностика",
                                          subtitle: "Состояние VPN")
                        }.buttonStyle(.plain)
                    }
                    .padding(16)
                }
                .transition(.opacity)
            }
        }
        .background(kcBackground)
    }

    private func show(_ next: KCToolPanel?) {
        withAnimation(.easeInOut(duration: 0.22)) { panel = next }
    }

    private func toolTitle(_ panel: KCToolPanel) -> String {
        switch panel {
        case .calculator: return "Калькулятор"
        case .speed: return "Тест скорости"
        case .logs: return "Диагностика"
        }
    }
}

private struct KCSlidingPanel<Content: View>: View {
    let title: String
    let onBack: () -> Void
    let content: Content

    init(title: String, onBack: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onBack = onBack
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 24)).foregroundColor(kcCopper)
                }
                Text(title).font(.headline).foregroundColor(kcInk)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 8)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(kcBackground)
    }
}

private enum KCSettingsPanel: Hashable {
    case appearance, connection, vk, servers, server(UUID), advanced, backup
}

private struct KCFullSettingsPage: View {
    @ObservedObject var tunnel: TunnelManager
    let onClose: () -> Void
    @AppStorage("kcDarkTheme") private var darkTheme = true

    var body: some View {
        NavigationView {
            KCSettingsHub(tunnel: tunnel)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: onClose) {
                            Label("Назад", systemImage: "chevron.left")
                                .foregroundColor(kcCopper)
                        }
                    }
                }
        }
        .background(kcBackground.ignoresSafeArea())
        .preferredColorScheme(darkTheme ? .dark : .light)
    }
}

private struct KCSettingsHub: View {
    @ObservedObject var tunnel: TunnelManager
    @State private var panel: KCSettingsPanel?

    var body: some View {
        Group {
            if let panel {
                KCSlidingPanel(title: title(panel), onBack: { show(nil) }) {
                    panelContent(panel)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        KCSettingsVKStatusCard { show(.vk) }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            settingButton(.appearance, "circle.lefthalf.filled", "Оформление", "Светлая · графит · чёрная")
                            settingButton(.connection, "point.3.connected.trianglepath.dotted", "Подключение", "Smart Route и DIRECT")
                            settingButton(.vk, "person.crop.circle.badge.checkmark", "VK и вход", "Ссылки и сессия")
                            settingButton(.servers, "server.rack", "Серверы", "Протоколы и ключи")
                            settingButton(.advanced, "slider.horizontal.3", "Расширенные", "MTU, Island, журнал")
                            settingButton(.backup, "externaldrive", "Резерв и импорт", "Копия, ссылка, сброс")
                        }
                    }
                    .padding(16)
                }
                .transition(.opacity)
            }
        }
        .background(kcBackground)
    }

    @ViewBuilder private func panelContent(_ panel: KCSettingsPanel) -> some View {
        switch panel {
        case .appearance: KCAppearancePanel()
        case .connection: KCRouteSheet(tunnel: tunnel)
        case .vk: KCVKSettingsPanel()
        case .servers: KCServerListPanel { show(.server($0)) }
        case let .server(id): ServerEditView(serverId: id)
        case .advanced: AdvancedView()
        case .backup: KCBackupPanel()
        }
    }

    private func settingButton(_ target: KCSettingsPanel, _ icon: String, _ title: String, _ subtitle: String) -> some View {
        Button { show(target) } label: {
            KCCompactTool(icon: icon, title: title, subtitle: subtitle)
        }.buttonStyle(.plain)
    }

    private func show(_ next: KCSettingsPanel?) {
        withAnimation(.easeInOut(duration: 0.22)) { panel = next }
    }

    private func title(_ panel: KCSettingsPanel) -> String {
        switch panel {
        case .appearance: return "Оформление"
        case .connection: return "Подключение"
        case .vk: return "VK и вход"
        case .servers: return "Серверы"
        case .server: return "Настройка сервера"
        case .advanced: return "Расширенные"
        case .backup: return "Резерв и импорт"
        }
    }
}

private struct KCSettingsVKStatusCard: View {
    @AppStorage("vkLink") private var vkLink = ""
    @AppStorage("VKAuth") private var vkAuth = false
    let action: () -> Void

    private var linkCount: Int {
        vkLink.split(whereSeparator: { $0.isNewline }).filter { !$0.isEmpty }.count
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Text("VK")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white).frame(width: 46, height: 46)
                    .background(Color(red: 0.10, green: 0.48, blue: 0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Канал VK").font(.subheadline.weight(.semibold)).foregroundColor(kcInk)
                    Text(linkCount == 0 ? "Call‑ссылка не добавлена" : "\(linkCount) call‑ссылок · \(vkAuth ? "аккаунт VK" : "анонимный режим")")
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 5) {
                        Circle().fill(VKCookieStore.isValid() ? kcCopper : (linkCount > 0 ? Color.orange : Color.gray)).frame(width: 7, height: 7)
                        Text(VKCookieStore.isValid() ? "Сессия" : (linkCount > 0 ? "Готов" : "Настроить"))
                    }.font(.caption2).foregroundColor(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(14).background(kcPanel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(kcOutline, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

private struct KCAppearancePanel: View {
    @AppStorage("kcDarkTheme") private var darkTheme = true
    @AppStorage("kcPureBlack") private var pureBlack = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    Toggle("Тёмная тема", isOn: $darkTheme)
                        .padding(14)
                    Divider().padding(.leading, 14)
                    Toggle("Настоящий чёрный", isOn: $pureBlack)
                        .padding(14).disabled(!darkTheme)
                }
                .background(kcPanel)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 10) {
                    themePreview("Светлая", dark: false, black: false)
                    themePreview("Графит", dark: true, black: false)
                    themePreview("Чёрная", dark: true, black: true)
                }
                Text("Оформление меняется сразу во всём интерфейсе K&C. Настройки VPN и соединение при этом не затрагиваются.")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(16)
        }.background(kcBackground)
    }

    private func themePreview(_ title: String, dark: Bool, black: Bool) -> some View {
        let selected = darkTheme == dark && (!dark || pureBlack == black)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { darkTheme = dark; pureBlack = black }
        } label: {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(dark ? (black ? Color.black : Color(red: 0.09, green: 0.095, blue: 0.11)) : Color(red: 0.97, green: 0.95, blue: 0.91))
                    .frame(height: 58)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 3) { ForEach(0..<3) { _ in Capsule().fill(kcCopper).frame(height: 5) } }
                            .padding(8)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? kcCopper : kcOutline, lineWidth: selected ? 2 : 1))
                Text(title).font(.caption2.weight(selected ? .semibold : .regular)).foregroundColor(kcInk)
            }
        }.buttonStyle(.plain)
    }
}

private struct KCServerListPanel: View {
    @ObservedObject private var store = ServerStore.shared
    let onEdit: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(store.servers) { server in
                    HStack(spacing: 12) {
                        Button { store.activate(server.id) } label: {
                            Image(systemName: server.id == store.activeServerId ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundColor(server.id == store.activeServerId ? kcCopper : .secondary)
                        }.buttonStyle(.plain)
                        Button { onEdit(server.id) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.serverName).font(.subheadline.weight(.semibold)).foregroundColor(kcInk)
                                Text(server.modeLabel).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                    .padding(14).background(kcPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Text("Кружок выбирает активный сервер. Нажатие на карточку открывает его параметры в этой же нижней панели.")
                    .font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16)
        }.background(kcBackground)
    }
}

private struct KCVKSettingsPanel: View {
    @AppStorage("vkLink") private var vkLink = ""
    @AppStorage("VKAuth") private var vkAuth = false
    @State private var cookie: VKCookieStore.Stored?
    @State private var showLogin = false
    @State private var showDelete = false

    private var links: [String] {
        vkLink.split(whereSeparator: { $0.isNewline }).map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VK Call Link\(vkAuth ? "s" : "")").font(.caption).foregroundColor(.secondary)
                    TextEditor(text: $vkLink).frame(minHeight: vkAuth ? 115 : 76)
                        .autocapitalization(.none).disableAutocorrection(true)
                        .padding(8).background(kcRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(vkAuth ? "\(links.count) ссылок · до \(links.count * 2) TURN-реле" : "Основная ссылка для подключения")
                        .font(.caption2).foregroundColor(.secondary)
                }.padding(14).background(kcPanel).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 0) {
                    Toggle("Использовать аккаунт VK", isOn: $vkAuth).padding(14)
                    Divider().padding(.leading, 14)
                    HStack { Text("Сессия"); Spacer(); Text(cookieStatus).foregroundColor(cookieIsValid ? kcCopper : .orange) }
                        .font(.subheadline).padding(14)
                    Button { showLogin = true } label: {
                        Label(cookie == nil ? "Войти во VK" : "Войти повторно", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    }.buttonStyle(.plain).foregroundColor(kcCopper)
                    if cookie != nil {
                        Divider().padding(.leading, 14)
                        Button(role: .destructive) { showDelete = true } label: {
                            Label("Удалить сохранённую сессию", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        }
                    }
                }.background(kcPanel).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }.padding(16)
        }
        .background(kcBackground)
        .onAppear { cookie = VKCookieStore.load() }
        .onChange(of: vkAuth) { enabled in if enabled && !VKCookieStore.isValid() { showLogin = true } }
        .sheet(isPresented: $showLogin) {
            VKAuthWebView { result in
                showLogin = false
                if case let .harvested(header, expiry) = result {
                    VKCookieStore.save(cookieHeader: header, expiry: expiry)
                    cookie = VKCookieStore.load()
                }
            }
        }
        .alert("Удалить сохранённую сессию?", isPresented: $showDelete) {
            Button("Удалить", role: .destructive) { VKCookieStore.delete(); cookie = nil }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var cookieIsValid: Bool { (cookie?.expiry ?? .distantPast) > Date() }
    private var cookieStatus: String {
        guard let cookie else { return "Нет входа" }
        if !cookieIsValid { return "Истекла" }
        return "Активна до " + cookie.expiry.formatted(date: .numeric, time: .omitted)
    }
}

private struct KCBackupPanel: View {
    @State private var exportURL: IdentifiableURL?
    @State private var showPicker = false
    @State private var pendingConfig: AppConfig?
    @State private var pendingLink: ConnectionLink?
    @State private var showImportConfirm = false
    @State private var showLinkConfirm = false
    @State private var showResetCache = false
    @State private var showResetProfile = false
    @State private var alertTitle = ""
    @State private var alertMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                action("Экспорт полной копии", "square.and.arrow.up", handleExport)
                action("Импорт полной копии", "square.and.arrow.down") { showPicker = true }
                action("Импорт ссылки из буфера", "link.badge.plus", handleLinkPaste)
                action("Сбросить кэш TURN", "trash", destructive: true) { showResetCache = true }
                action("Сбросить профиль браузера", "trash", destructive: true) { showResetProfile = true }
                Text("Резервная копия содержит настройки, ключи WireGuard, данные TURN и профиль браузера. Храните файл как секрет.")
                    .font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            }.padding(16)
        }
        .background(kcBackground)
        .sheet(item: $exportURL) { ShareSheet(activityItems: [$0.url]) }
        .sheet(isPresented: $showPicker) {
            DocumentPicker(contentTypes: [.json, .text, .data, .item]) { importFile($0) }
        }
        .alert("Импортировать резервную копию?", isPresented: $showImportConfirm, presenting: pendingConfig) { config in
            Button("Импортировать", role: .destructive) { apply(config) }
            Button("Отмена", role: .cancel) { pendingConfig = nil }
        } message: { _ in Text("Текущие настройки будут заменены данными из выбранного файла.") }
        .alert("Импортировать ссылку подключения?", isPresented: $showLinkConfirm, presenting: pendingLink) { link in
            Button("Импортировать", role: .destructive) {
                alertTitle = ConnectionLinkPrompt.importedTitle
                alertMessage = ConnectionLinkPrompt.apply(link)
                pendingLink = nil
            }
            Button("Отмена", role: .cancel) { pendingLink = nil }
        } message: { Text(ConnectionLinkPrompt.message(for: $0)) }
        .alert("Сбросить кэш TURN?", isPresented: $showResetCache) {
            Button("Сбросить", role: .destructive) { resetCache() }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Кэш будет создан заново при следующем подключении.") }
        .alert("Сбросить профиль браузера?", isPresented: $showResetProfile) {
            Button("Сбросить", role: .destructive) { resetProfile() }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Автоматический решатель временно будет использовать новый профиль.") }
        .alert(alertTitle, isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMessage ?? "") }
    }

    private func action(_ title: String, _ icon: String, destructive: Bool = false, _ work: @escaping () -> Void) -> some View {
        Button(action: work) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).frame(width: 28)
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .foregroundColor(destructive ? .red : kcInk).padding(14).background(kcPanel)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func handleExport() {
        do { exportURL = IdentifiableURL(url: try BackupManager.exportToTempFile()) }
        catch { fail("Экспорт не выполнен", error) }
    }
    private func importFile(_ url: URL) {
        do { pendingConfig = try BackupManager.importFromFileURL(url); showImportConfirm = true }
        catch { fail("Импорт не выполнен", error) }
    }
    private func apply(_ config: AppConfig) {
        do {
            try BackupManager.applyConfig(config); pendingConfig = nil
            alertTitle = "Импорт завершён"; alertMessage = "Настройки и кэш TURN восстановлены."
        } catch { fail("Импорт не выполнен", error) }
    }
    private func handleLinkPaste() {
        let raw = UIPasteboard.general.string ?? ""
        guard !raw.isEmpty else { alertTitle = "Буфер пуст"; alertMessage = "Сначала скопируйте ссылку подключения."; return }
        do { pendingLink = try BackupManager.parseConnectionLinkString(raw); showLinkConfirm = true }
        catch { fail(ConnectionLinkPrompt.invalidTitle, error) }
    }
    private func resetCache() {
        do { try BackupManager.resetTurnCache(); alertTitle = "Кэш очищен"; alertMessage = "Кэш TURN будет создан при следующем подключении." }
        catch { fail("Сброс не выполнен", error) }
    }
    private func resetProfile() {
        do { try BackupManager.resetCapturedProfile(); alertTitle = "Профиль очищен"; alertMessage = "Профиль браузера будет создан заново." }
        catch { fail("Сброс не выполнен", error) }
    }
    private func fail(_ title: String, _ error: Error) { alertTitle = title; alertMessage = error.localizedDescription }
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
