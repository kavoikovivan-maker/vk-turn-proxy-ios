import SwiftUI
import NetworkExtension

struct KCShieldRootView: View {
    @StateObject private var tunnel = TunnelManager.shared
    @ObservedObject private var store = ServerStore.shared

    private let canvas = Color(red: 0.945, green: 0.948, blue: 0.952)
    private let surface = Color.white.opacity(0.82)
    private let graphite = Color(red: 0.16, green: 0.17, blue: 0.19)
    private let iceBlue = Color(red: 0.44, green: 0.72, blue: 0.96)

    var body: some View {
        NavigationView {
            ZStack {
                canvas.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        brandHeader
                        connectionCard
                        quickActions
                        diagnosticsPreview
                        brandFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $tunnel.captchaPending) {
                if let urlStr = tunnel.captchaImageURL, let url = URL(string: urlStr) {
                    CaptchaWebView(
                        url: url,
                        captchaSID: tunnel.captchaSID ?? "",
                        onSolved: { tunnel.solveCaptcha(answer: $0) },
                        onDismiss: {
                            tunnel.onCaptchaSheetDismissed()
                            tunnel.captchaPending = false
                            tunnel.captchaImageURL = nil
                        },
                        onLimitDetected: { tunnel.onCaptchaLimitDetected() },
                        onCaptchaReady: { tunnel.onCaptchaReady() },
                        onLog: { tunnel.logFromCaptchaView($0) },
                        tunnel: tunnel
                    )
                }
            }
            .sheet(isPresented: $tunnel.vkLoginPending) {
                VKAuthWebView { result in
                    tunnel.onVKLoginResult(result)
                }
            }
            .background(ConnectionLinkImporter())
        }
    }

    private var brandHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("K&C Smart Proxy")
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .foregroundColor(graphite)
                Text("Умный маршрут для iPhone")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            NavigationLink(destination: SettingsView()) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(graphite)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.72))
                    .clipShape(Circle())
            }
        }
    }

    private var connectionCard: some View {
        VStack(spacing: 18) {
            Text(statusTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)

            Button(action: toggleTunnel) {
                ZStack {
                    Circle()
                        .fill(buttonFill)
                        .frame(width: 154, height: 154)
                        .shadow(color: glowColor, radius: glowRadius, x: 0, y: 8)

                    Circle()
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                        .frame(width: 134, height: 134)

                    Text("K&C")
                        .font(.system(size: 35, weight: .semibold, design: .rounded))
                        .foregroundColor(graphite)
                }
            }
            .buttonStyle(.plain)
            .disabled(tunnel.status == .disconnecting)

            VStack(spacing: 5) {
                Text(tunnel.serverCaption.subtitle)
                    .font(.headline)
                    .foregroundColor(graphite)
                    .multilineTextAlignment(.center)

                if let message = tunnel.errorMessage, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                } else {
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: SpeedTestView(tunnel: tunnel)) {
                quickAction(title: "Speed", icon: "gauge.with.dots.needle.50percent")
            }

            NavigationLink(destination: KCNetworkHealthView(tunnel: tunnel)) {
                quickAction(title: "Health", icon: "waveform.path.ecg")
            }

            NavigationLink(destination: SettingsView()) {
                quickAction(title: "Route", icon: "point.3.connected.trianglepath.dotted")
            }
        }
    }

    private func quickAction(title: String, icon: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(graphite)
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .background(Color.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var diagnosticsPreview: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Smart route")
                    .font(.headline)
                    .foregroundColor(graphite)
                Spacer()
                Text(healthLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(healthColor)
            }

            Divider().opacity(0.45)

            HStack {
                metric(label: "Tunnel", value: tunnel.status == .connected ? "Active" : "Standby")
                Spacer()
                metric(label: "Server", value: store.activeServer.serverName.isEmpty ? "Default" : store.activeServer.serverName)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(graphite)
                .lineLimit(1)
        }
    }

    private var brandFooter: some View {
        HStack {
            Spacer()
            Text("Kavoikoff&CO.")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .tracking(0.4)
        }
        .padding(.top, 2)
        .padding(.trailing, 4)
    }

    private var statusTitle: String {
        if tunnel.preBootstrapInProgress { return "Preparing smart route" }
        switch tunnel.status {
        case .connected: return "Protected"
        case .connecting, .reasserting: return "Connecting"
        case .disconnecting: return "Disconnecting"
        case .invalid: return "Configuration required"
        default: return "Ready to connect"
        }
    }

    private var statusSubtitle: String {
        switch tunnel.status {
        case .connected: return "Smart Proxy route is active"
        case .connecting, .reasserting: return "Finding a stable route"
        case .disconnecting: return "Closing the tunnel safely"
        default: return "Tap K&C to start"
        }
    }

    private var buttonFill: Color {
        switch tunnel.status {
        case .connected: return Color(red: 0.86, green: 0.95, blue: 1.0)
        case .connecting, .reasserting: return Color(red: 0.90, green: 0.94, blue: 0.98)
        default: return Color.white.opacity(0.94)
        }
    }

    private var glowColor: Color {
        switch tunnel.status {
        case .connected: return iceBlue.opacity(0.62)
        case .connecting, .reasserting: return iceBlue.opacity(0.28)
        default: return Color.black.opacity(0.07)
        }
    }

    private var glowRadius: CGFloat {
        tunnel.status == .connected ? 28 : 12
    }

    private var healthLabel: String {
        switch tunnel.status {
        case .connected: return "Active"
        case .connecting, .reasserting: return "Checking"
        default: return "Ready"
        }
    }

    private var healthColor: Color {
        tunnel.status == .connected ? iceBlue : .secondary
    }

    private func toggleTunnel() {
        if tunnel.status == .connected || tunnel.status == .connecting || tunnel.preBootstrapInProgress {
            SharedLogger.shared.log("[K&C UI] user requested disconnect")
            tunnel.disconnect()
            return
        }

        let active = store.activeServer
        SharedLogger.shared.log("[K&C UI] user requested connect: \(active.serverName) [\(active.modeLabel)]")
        let config = TunnelConfig.make(for: active)
        Task {
            await tunnel.connect(config: config)
        }
    }
}
