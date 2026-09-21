import Foundation

struct KCAssistantMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

enum KCAssistantMode: String, CaseIterable, Identifiable {
    case quick, smart, team
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quick: return "Быстрый"
        case .smart: return "Умный"
        case .team: return "Команда"
        }
    }
    var responseWords: Int {
        switch self {
        case .quick: return 80
        case .smart: return 350
        case .team: return 550
        }
    }
}

@MainActor
final class KCAssistantConversation: ObservableObject {
    @Published private(set) var messages: [KCAssistantMessage]
    @Published private(set) var isSending = false
    @Published var errorText: String?

    private let storageKey = "kcAssistantConversationV1"
    private let maximumStoredMessages = 40

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([KCAssistantMessage].self, from: data),
           !saved.isEmpty {
            messages = saved
        } else {
            messages = [KCAssistantMessage(
                role: .assistant,
                text: "Здравствуйте. Я помощник K&C. Могу объяснить состояние сети, маршрут и настройки подключения."
            )]
        }
    }

    func send(_ rawText: String, endpoint: String, networkContext: String, mode: KCAssistantMode = .quick) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        // A real multi-agent server must be integrated and verified before this mode can answer.
        if mode == .team {
            errorText = "Команда агентов пока не подключена к GPT-серверу."
            return
        }
        errorText = nil
        append(.init(role: .user, text: text))
        isSending = true
        defer { isSending = false }

        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            append(.init(role: .assistant, text: localReply(to: text, context: networkContext)))
            return
        }

        guard let url = URL(string: trimmedEndpoint), url.scheme?.lowercased() == "https" else {
            errorText = "В настройках GPT нужен полный HTTPS-адрес сервера."
            append(.init(role: .assistant, text: "Не удалось подключиться к серверу GPT. Проверьте адрес в настройках."))
            return
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(RequestPayload(
                messages: messages.suffix(16).map { .init(role: $0.role.rawValue, content: $0.text) },
                context: networkContext,
                responseWords: mode.responseWords,
                mode: mode.rawValue
            ))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AssistantError.server
            }
            guard let reply = Self.decodeReply(data), !reply.isEmpty else {
                throw AssistantError.emptyReply
            }
            append(.init(role: .assistant, text: reply))
        } catch {
            errorText = "GPT временно недоступен. Проверьте сервер и интернет."
            append(.init(role: .assistant, text: "Сейчас не могу получить ответ от GPT. Данные VPN и история разговора сохранены на телефоне."))
        }
    }

    func clear() {
        messages = [KCAssistantMessage(role: .assistant, text: "История очищена. Чем помочь?")]
        persist()
        errorText = nil
    }

    private func append(_ message: KCAssistantMessage) {
        messages.append(message)
        if messages.count > maximumStoredMessages {
            messages.removeFirst(messages.count - maximumStoredMessages)
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func localReply(to question: String, context: String) -> String {
        let q = question.lowercased()
        if q.contains("маршрут") || q.contains("сервер") || q.contains("vpn") || q.contains("proxy") {
            return context
        }
        if q.contains("скорост") || q.contains("интернет") || q.contains("пинг") || q.contains("задерж") {
            return context
        }
        return "Я уже вижу состояние K&C, но ответы на общие вопросы появятся после подключения GPT-сервера. Сейчас могу объяснить VPN, маршрут и качество сети."
    }

    private static func decodeReply(_ data: Data) -> String? {
        if let direct = try? JSONDecoder().decode(DirectResponse.self, from: data) {
            return direct.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let compatible = try? JSONDecoder().decode(OpenAIResponse.self, from: data) {
            return compatible.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

private struct RequestPayload: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let messages: [Message]
    let context: String
    let responseWords: Int
    let mode: String
}

private struct DirectResponse: Decodable {
    let reply: String
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private enum AssistantError: Error {
    case server
    case emptyReply
}
