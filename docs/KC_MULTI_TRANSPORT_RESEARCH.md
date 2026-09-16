# K&C Smart Proxy — verified transport sources

This note records sources checked during implementation so K&C does not enable a carrier based on assumptions.

## VK

Status: integrated today.

K&C already receives live TURN RTT and tunnel state from the current engine. This is the reference adapter for Smart Route.

## MAX

Candidate implementation: `somewhat-industries/swinter-ios` (The Unlicense / public domain dedication).

Verified pieces in that project:
- `ios/VKTurnVPN/Shared/MaxAuthService.swift` — MAX authentication flow.
- `ios/VKTurnVPN/Shared/MaxCallService.swift` — MAX call/WebRTC pipeline.
- `golib/vpnlib/max_creds.go` — obtains TURN credentials from MAX call setup.
- Network Extension packet tunnel is already used by the reference iOS project.

Integration rule for K&C:
1. Do not copy UI or branding.
2. Isolate MAX-specific auth/credential acquisition behind a K&C adapter.
3. Store credentials/tokens in Keychain, never UserDefaults or logs.
4. Feed only adapter health (reachable, RTT, failures) to `KCSmartTransportManager`.
5. Automatic failover may select MAX only after the adapter has completed a real readiness check.

## Yandex / Telemost

There are multiple public implementations, but their status is inconsistent:
- `KillTheCensorship/Turnel` documents automatic Telemost TURN credential acquisition, but the repository itself says it is a demo project and is no longer maintained.
- `cacggghp/vk-turn-proxy` / forks contain a Telemost path, while some README revisions explicitly note that the old Telemost TURN route was closed.
- `haritos90/olcrtc-ios` is a newer MIT-licensed iOS project using a WebRTC-based proxy core with Telemost as one supported carrier; its current iOS scope exposes a local SOCKS5 proxy rather than a system-wide NetworkExtension route.

Decision: do not mark Yandex as configured in K&C until a current end-to-end iPhone test proves the selected implementation still works.

## Smart Route policy

Provider-specific code never decides the global route. Each adapter reports:
- configured / not configured
- reachable / unreachable
- latency
- consecutive failures
- later: handshake time, packet loss, stability window

`KCSmartTransportManager` owns ranking and the AUTO/MANUAL selection state.

Next implementation target: MAX adapter, because a current iOS reference implementation with Network Extension and TURN credential acquisition is available. Yandex stays behind verification until a current implementation passes an end-to-end test.
