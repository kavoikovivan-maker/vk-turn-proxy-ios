import SwiftUI
import Network

@MainActor
final class KCNetworkHealthModel: ObservableObject {
    @Published var networkStatus = "Checking"
    @Published var interfaceName = "Unknown"
    @Published var isConstrained = false
    @Published var isExpensive = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kavoikoff.network-health")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.networkStatus = path.status == .satisfied ? "Available" : "Offline"
                self.interfaceName = Self.interfaceLabel(for: path)
                self.isConstrained = path.isConstrained
                self.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private static func interfaceLabel(for path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) { return "Wi‑Fi" }
        if path.usesInterfaceType(.cellular) { return "Cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
        return "Network"
    }
}

struct KCNetworkHealthView: View {
    @StateObject private var model = KCNetworkHealthModel()
    @ObservedObject var tunnel: TunnelManager

    private let canvas = Color(red: 0.945, green: 0.948, blue: 0.952)
    private let graphite = Color(red: 0.16, green: 0.17, blue: 0.19)
    private let iceBlue = Color(red: 0.44, green: 0.72, blue: 0.96)

    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    statusCard
                    routeCard
                    adviceCard
                }
                .padding(20)
            }
        }
        .navigationTitle("Network Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iceBlue.opacity(0.14))
                    .frame(width: 84, height: 84)
                Image(systemName: statusIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(statusColor)
            }

            Text(statusTitle)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .foregroundColor(graphite)

            Text(statusSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Current route")
                .font(.headline)
                .foregroundColor(graphite)

            HStack {
                metric("Tunnel", tunnel.status == .connected ? "Active" : "Standby")
                Spacer()
                metric("Network", model.interfaceName)
            }

            Divider().opacity(0.45)

            HStack {
                metric("Internet", model.networkStatus)
                Spacer()
                metric("Data mode", dataMode)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var adviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(iceBlue)
                Text("Smart Proxy advice")
                    .font(.headline)
                    .foregroundColor(graphite)
            }

            Text(adviceText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(graphite)
        }
    }

    private var statusTitle: String {
        if model.networkStatus == "Offline" { return "Connection issue" }
        return tunnel.status == .connected ? "Route protected" : "Network ready"
    }

    private var statusSubtitle: String {
        if model.networkStatus == "Offline" { return "No usable internet route is currently available." }
        if tunnel.status == .connected { return "The secure tunnel is active on the current network." }
        return "The device has network access and is ready for a secure route."
    }

    private var statusIcon: String {
        if model.networkStatus == "Offline" { return "wifi.exclamationmark" }
        return tunnel.status == .connected ? "checkmark.shield" : "network"
    }

    private var statusColor: Color {
        model.networkStatus == "Offline" ? .red : iceBlue
    }

    private var dataMode: String {
        if model.isConstrained { return "Constrained" }
        if model.isExpensive { return "Metered" }
        return "Normal"
    }

    private var adviceText: String {
        if model.networkStatus == "Offline" {
            return "Check Wi‑Fi or cellular data before changing proxy settings."
        }
        if model.isConstrained {
            return "Low Data Mode is active. Smart routing should avoid unnecessary route changes."
        }
        if model.isExpensive {
            return "The current connection may be cellular or metered. Prefer stable routes with lower overhead."
        }
        if tunnel.status == .connected {
            return "The route is active. The next step is to add latency checks and automatic server ranking."
        }
        return "Connect with K&C to let Smart Proxy evaluate the secure route."
    }
}
