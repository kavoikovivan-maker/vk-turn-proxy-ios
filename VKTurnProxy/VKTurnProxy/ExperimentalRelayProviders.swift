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
        .init(provider: .max1, credentialDiscoveryImplemented: false, tunnelVerifiedOnDevice: false),
        .init(provider: .max2, credentialDiscoveryImplemented: false, tunnelVerifiedOnDevice: false),
        .init(provider: .yandex, credentialDiscoveryImplemented: false, tunnelVerifiedOnDevice: false),
        .init(provider: .direct, credentialDiscoveryImplemented: true, tunnelVerifiedOnDevice: false),
    ]
}
