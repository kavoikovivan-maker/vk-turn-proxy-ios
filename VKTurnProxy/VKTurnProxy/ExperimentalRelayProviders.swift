import Foundation

/// Relay families exposed by K&C. VK is the proven path in the current iOS
/// tunnel. MAX and Yandex are intentionally marked experimental until their
/// credential acquisition and media relay flows are verified on a physical
/// iPhone.
enum KCRelayProvider: String, CaseIterable, Codable, Identifiable {
    case vk
    case max1
    case max2
    case yandex
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vk: return "VK"
        case .max1: return "Max 1"
        case .max2: return "Max 2"
        case .yandex: return "Yandex"
        case .direct: return "VPN"
        }
    }

    var isExperimental: Bool {
        switch self {
        case .max1, .max2, .yandex: return true
        case .vk, .direct: return false
        }
    }
}

struct KCTurnCredentials: Equatable, Codable {
    let urls: [String]
    let username: String
    let credential: String

    var firstUDPRelayAddress: String? {
        for value in urls {
            guard value.hasPrefix("turn:") || value.hasPrefix("turns:") else { continue }
            if value.localizedCaseInsensitiveContains("transport=tcp") { continue }
            let noQuery = value.split(separator: "?", maxSplits: 1).first.map(String.init) ?? value
            return noQuery
                .replacingOccurrences(of: "turn://", with: "")
                .replacingOccurrences(of: "turn:", with: "")
                .replacingOccurrences(of: "turns://", with: "")
                .replacingOccurrences(of: "turns:", with: "")
        }
        return nil
    }
}

/// Shared parser for WebRTC responses from relay providers. It deliberately
/// accepts several common object layouts so the provider-specific network
/// code can stay small and testable.
enum KCTurnCredentialParser {
    static func parse(data: Data) -> KCTurnCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findCredentials(in: json)
    }

    private static func findCredentials(in value: Any) -> KCTurnCredentials? {
        if let object = value as? [String: Any] {
            if let direct = credentials(from: object) { return direct }

            let priorityKeys = [
                "turn_server", "turn", "rtcConfiguration", "iceServers",
                "serverHello", "conversationParams"
            ]
            for key in priorityKeys {
                if let nested = object[key], let found = findCredentials(in: nested) {
                    return found
                }
            }
            for nested in object.values {
                if let found = findCredentials(in: nested) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = findCredentials(in: nested) { return found }
            }
        }
        return nil
    }

    private static func credentials(from object: [String: Any]) -> KCTurnCredentials? {
        guard let username = object["username"] as? String,
              let credential = object["credential"] as? String else { return nil }

        let urls: [String]
        if let list = object["urls"] as? [String] {
            urls = list
        } else if let single = object["urls"] as? String {
            urls = [single]
        } else {
            return nil
        }

        guard urls.contains(where: { $0.hasPrefix("turn:") || $0.hasPrefix("turns:") }) else {
            return nil
        }
        return KCTurnCredentials(urls: urls, username: username, credential: credential)
    }
}

enum KCYandexTelemostLink {
    /// Extracts the conference id from a Telemost link without doing any
    /// network work. Credential acquisition is implemented separately so we
    /// can test parsing before touching live provider endpoints.
    static func conferenceID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if let range = trimmed.range(of: "/j/") {
            candidate = String(trimmed[range.upperBound...])
        } else {
            candidate = trimmed
        }

        let id = candidate.split(whereSeparator: { $0 == "?" || $0 == "#" || $0 == "/" }).first.map(String.init)
        return id?.isEmpty == false ? id : nil
    }
}

/// Status surface used by UI/Smart Route while MAX/Yandex are being brought
/// online. This prevents an experimental route from being presented as proven.
struct KCRelayCapability: Identifiable, Equatable {
    let provider: KCRelayProvider
    let credentialDiscoveryImplemented: Bool
    let tunnelVerifiedOnDevice: Bool

    var id: String { provider.id }

    static let current: [KCRelayCapability] = [
        .init(provider: .vk, credentialDiscoveryImplemented: true, tunnelVerifiedOnDevice: false),
        .init(provider: .max1, credentialDiscoveryImplemented: true, tunnelVerifiedOnDevice: false),
        .init(provider: .max2, credentialDiscoveryImplemented: true, tunnelVerifiedOnDevice: false),
        .init(provider: .yandex, credentialDiscoveryImplemented: true, tunnelVerifiedOnDevice: false),
        .init(provider: .direct, credentialDiscoveryImplemented: true, tunnelVerifiedOnDevice: false),
    ]
}


enum KCRelayProviderError: LocalizedError {
    case invalidInput(String)
    case http(Int)
    case malformedResponse(String)
    case websocketClosed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message), .malformedResponse(let message), .websocketClosed(let message):
            return message
        case .http(let code):
            return "HTTP \(code)"
        }
    }
}

private enum KCRelayHTTP {
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"

    static func jsonRequest(
        _ request: URLRequest,
        session: URLSession = .shared
    ) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KCRelayProviderError.malformedResponse("Нет HTTP-ответа")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw KCRelayProviderError.http(http.statusCode)
        }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KCRelayProviderError.malformedResponse("Некорректный JSON")
        }
        return value
    }

    static func formBody(_ values: [String: String]) -> Data {
        values
            .map { key, value in
                let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    static func credentials(from object: Any) -> KCTurnCredentials? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return KCTurnCredentialParser.parse(data: data)
    }
}

/// Independently implemented Yandex Telemost TURN credential discovery.
/// A successful result only proves credential discovery; the PacketTunnel path
/// still has to pass traffic on a physical iPhone before the route is marked Ready.
enum KCYandexTurnProvider {
    static func fetch(telemostLink: String, session: URLSession = .shared) async throws -> KCTurnCredentials {
        guard let conferenceID = KCYandexTelemostLink.conferenceID(from: telemostLink) else {
            throw KCRelayProviderError.invalidInput("Некорректная ссылка Yandex Telemost")
        }

        let canonical = "https://telemost.yandex.ru/j/\(conferenceID)"
        guard let encoded = canonical.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string:
                "https://cloud-api.yandex.ru/telemost_front/v2/telemost/conferences/\(encoded)/connection?next_gen_media_platform_allowed=false"
              ) else {
            throw KCRelayProviderError.invalidInput("Не удалось сформировать Yandex URL")
        }

        var request = URLRequest(url: url)
        request.setValue(KCRelayHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://telemost.yandex.ru/", forHTTPHeaderField: "Referer")
        request.setValue("https://telemost.yandex.ru", forHTTPHeaderField: "Origin")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "Client-Instance-Id")

        let json = try await KCRelayHTTP.jsonRequest(request, session: session)
        guard let roomID = json["room_id"] as? String, !roomID.isEmpty,
              let peerID = json["peer_id"] as? String, !peerID.isEmpty,
              let credentials = json["credentials"] as? String, !credentials.isEmpty,
              let config = json["client_configuration"] as? [String: Any],
              let mediaURL = config["media_server_url"] as? String,
              let wsURL = URL(string: mediaURL) else {
            throw KCRelayProviderError.malformedResponse("Yandex не вернул параметры конференции")
        }

        var wsRequest = URLRequest(url: wsURL)
        wsRequest.setValue("https://telemost.yandex.ru", forHTTPHeaderField: "Origin")
        wsRequest.setValue(KCRelayHTTP.userAgent, forHTTPHeaderField: "User-Agent")

        let socket = session.webSocketTask(with: wsRequest)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }

        let hello: [String: Any] = [
            "uid": UUID().uuidString,
            "hello": [
                "participantMeta": [
                    "name": "Guest", "role": "SPEAKER", "description": "",
                    "sendAudio": false, "sendVideo": false
                ],
                "participantAttributes": [
                    "name": "Guest", "role": "SPEAKER", "description": ""
                ],
                "sendAudio": false,
                "sendVideo": false,
                "sendSharing": false,
                "participantId": peerID,
                "roomId": roomID,
                "serviceName": "telemost",
                "credentials": credentials,
                "sdkInfo": [
                    "implementation": "browser",
                    "version": "5.15.0",
                    "userAgent": KCRelayHTTP.userAgent,
                    "hwConcurrency": 4
                ],
                "sdkInitializationId": UUID().uuidString,
                "disablePublisher": false,
                "disableSubscriber": false
            ]
        ]
        let helloData = try JSONSerialization.data(withJSONObject: hello)
        let helloText = String(decoding: helloData, as: UTF8.self)
        try await socket.send(.string(helloText))

        for _ in 0..<40 {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case .string(let text): data = Data(text.utf8)
            case .data(let value): data = value
            @unknown default: continue
            }
            if let found = KCTurnCredentialParser.parse(data: data) {
                return found
            }
        }
        throw KCRelayProviderError.websocketClosed("Yandex TURN не получен")
    }
}

/// Independently implemented MAX/OneMe credential discovery. Max 1 and Max 2
/// use the same protocol adapter but keep separate account/session settings.
enum KCMaxTurnProvider {
    private static let websocketURL = URL(string: "wss://ws-api.oneme.ru/websocket")!
    private static let callsURL = URL(string: "https://calls.okcdn.ru/fb.do")!
    private static let applicationKey = "CNHIJPLGDIHBABABA"

    static func fetch(
        token: String,
        calleeUID: String,
        session: URLSession = .shared
    ) async throws -> KCTurnCredentials {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KCRelayProviderError.invalidInput("Не указан токен MAX")
        }
        guard !calleeUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KCRelayProviderError.invalidInput("Не указан MAX ID для звонка")
        }

        let callToken = try await fetchCallToken(token: token, session: session)
        let login = try await postForm(
            to: callsURL,
            values: [
                "method": "auth.anonymLogin",
                "format": "JSON",
                "application_key": applicationKey,
                "session_data": try jsonString([
                    "auth_token": callToken,
                    "client_type": "SDK_JS",
                    "client_version": "1.1",
                    "device_id": UUID().uuidString,
                    "version": 3
                ])
            ],
            session: session
        )

        guard let sessionKey = login["session_key"] as? String, !sessionKey.isEmpty else {
            throw KCRelayProviderError.malformedResponse("MAX не вернул session_key")
        }

        let apiServer = (login["api_server"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint: URL
        if let apiServer, !apiServer.isEmpty {
            if apiServer.hasSuffix("fb.do"), let url = URL(string: apiServer) {
                endpoint = url
            } else if let url = URL(string: apiServer.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/fb.do") {
                endpoint = url
            } else {
                endpoint = callsURL
            }
        } else {
            endpoint = callsURL
        }

        let started = try await postForm(
            to: endpoint,
            values: [
                "method": "vchat.startConversation",
                "format": "JSON",
                "application_key": applicationKey,
                "conversationId": UUID().uuidString,
                "isVideo": "false",
                "protocolVersion": "5",
                "payload": try jsonString(["is_video": false]),
                "externalIds": calleeUID,
                "session_key": sessionKey
            ],
            session: session
        )

        guard let found = KCRelayHTTP.credentials(from: started) else {
            throw KCRelayProviderError.malformedResponse("MAX не вернул TURN параметры")
        }
        return found
    }

    private static func fetchCallToken(token: String, session: URLSession) async throws -> String {
        var request = URLRequest(url: websocketURL)
        request.setValue(KCRelayHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://web.max.ru", forHTTPHeaderField: "Origin")
        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }

        var sequence = 0
        func message(opcode: Int, payload: [String: Any]) throws -> (Int, String) {
            let seq = sequence
            sequence += 1
            let data = try JSONSerialization.data(withJSONObject: [
                "seq": seq, "opcode": opcode, "payload": payload, "ver": 11, "cmd": 0
            ])
            return (seq, String(decoding: data, as: UTF8.self))
        }

        let hello = try message(opcode: 6, payload: [
            "userAgent": [
                "deviceType": "WEB",
                "locale": "ru",
                "deviceLocale": "ru",
                "osVersion": "iOS",
                "deviceName": "K&C",
                "headerUserAgent": KCRelayHTTP.userAgent,
                "appVersion": "26.4.1",
                "screen": "1179x2556 1.0x",
                "timezone": "Europe/Moscow"
            ],
            "deviceId": UUID().uuidString
        ])
        try await socket.send(.string(hello.1))

        var syncSeq: Int?
        var tokenSeq: Int?

        for _ in 0..<50 {
            let received = try await socket.receive()
            let data: Data
            switch received {
            case .string(let text): data = Data(text.utf8)
            case .data(let value): data = value
            @unknown default: continue
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseSeq = object["seq"] as? Int else { continue }

            if responseSeq == hello.0 {
                let sync = try message(opcode: 19, payload: [
                    "token": token,
                    "interactive": false,
                    "chatsCount": 40,
                    "chatsSync": 0,
                    "contactsSync": 0,
                    "presenceSync": 0,
                    "draftsSync": 0
                ])
                syncSeq = sync.0
                try await socket.send(.string(sync.1))
                continue
            }

            if responseSeq == syncSeq {
                let callToken = try message(opcode: 158, payload: [:])
                tokenSeq = callToken.0
                try await socket.send(.string(callToken.1))
                continue
            }

            if responseSeq == tokenSeq,
               let payload = object["payload"] as? [String: Any],
               let value = payload["token"] as? String,
               !value.isEmpty {
                return value
            }
        }

        throw KCRelayProviderError.websocketClosed("MAX call-token не получен")
    }

    private static func postForm(
        to url: URL,
        values: [String: String],
        session: URLSession
    ) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = KCRelayHTTP.formBody(values)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(KCRelayHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        return try await KCRelayHTTP.jsonRequest(request, session: session)
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
