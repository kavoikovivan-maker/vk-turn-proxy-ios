import SwiftUI

struct KCSmartRouteView: View {
    @StateObject private var manager = KCSmartTransportManager.shared

    private let canvas = Color(red: 0.945, green: 0.948, blue: 0.952)
    private let graphite = Color(red: 0.16, green: 0.17, blue: 0.19)
    private let iceBlue = Color(red: 0.44, green: 0.72, blue: 0.96)

    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    modeCard
                    transportList
                }
                .padding(20)
            }
        }
        .navigationTitle("Smart Route")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Умный маршрут")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(graphite)
            Text("K&C сравнивает только реально подключённые и доступные транспорты. Недоступный маршрут не будет выбран автоматически.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Режим")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(manager.automaticSelectionEnabled ? "Автоматический" : "Ручной")
                        .font(.headline)
                        .foregroundColor(graphite)
                }
                Spacer()
                Text(manager.selectedDisplayName)
                    .font(.headline)
                    .foregroundColor(iceBlue)
            }

            Divider().opacity(0.45)

            VStack(alignment: .leading, spacing: 4) {
                Text("Последнее решение")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(manager.lastSwitchReason)
                    .font(.subheadline)
                    .foregroundColor(graphite)
                if let date = manager.lastSwitchAt {
                    Text(date.formatted(date: .omitted, time: .standard))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            if !manager.automaticSelectionEnabled {
                Button("Вернуть автоматический выбор") {
                    manager.enableAutomaticSelection()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var transportList: some View {
        VStack(spacing: 12) {
            ForEach(manager.transports) { item in
                Button {
                    if item.isConfigured {
                        manager.selectManually(item.kind)
                    }
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(statusColor(item))
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(item.kind.displayName)
                                    .font(.headline)
                                    .foregroundColor(graphite)
                                if manager.selected == item.kind {
                                    Text("ACTIVE")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(iceBlue)
                                }
                            }
                            Text(statusText(item))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(latencyText(item))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor((item.isReachable || item.probeReachable == true) ? graphite : .secondary)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!item.isConfigured)
            }
        }
    }

    private func statusText(_ item: KCTransportHealth) -> String {
        if item.isConfigured && item.isReachable {
            return "Доступен и участвует в выборе"
        }
        if item.isConfigured {
            if item.consecutiveFailures > 0 {
                return "Проверка стабильности · ошибок подряд: \(item.consecutiveFailures)"
            }
            return item.lastUpdated == nil ? "Ожидает проверку" : "Сейчас недоступен"
        }
        if item.kind == .max, item.probeReachable == true {
            return "Сеть MAX доступна · адаптер готовится"
        }
        if item.kind == .max, item.probeReachable == false {
            return "Сеть MAX сейчас недоступна"
        }
        return "Адаптер ещё не подключён"
    }

    private func latencyText(_ item: KCTransportHealth) -> String {
        if item.isConfigured { return item.latencyLabel }
        if item.probeReachable == true { return item.probeLatencyLabel }
        return "—"
    }

    private func statusColor(_ item: KCTransportHealth) -> Color {
        if item.isReachable { return iceBlue }
        if item.probeReachable == true { return iceBlue.opacity(0.65) }
        if item.isConfigured { return .orange.opacity(0.75) }
        return .secondary.opacity(0.35)
    }
}
