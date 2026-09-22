# MAX / Yandex relay research for K&C iOS

Status: **experimental research**, not a claim of a working tunnel.

## Goal

Bring the same route families planned for Android to the iOS VPN client:

- VK
- Max 1
- Max 2
- Yandex
- direct WireGuard/VPN

Smart Route may only select MAX or Yandex after the provider-specific credential flow and the complete tunnel have been verified on a physical iPhone.

## MAX findings

Public reverse-engineering material currently shows that MAX/OneMe calling uses WebRTC infrastructure and exposes TURN/STUN information during call setup.

Observed flow in public research:

1. MAX/OneMe WebSocket authentication.
2. Obtain a short-lived call token.
3. Authenticate to the call HTTP API.
4. Start/join a conversation.
5. The response / signaling ServerHello contains TURN data with URLs, username and credential.
6. Media signaling continues over a WebRTC WebSocket endpoint.

Useful research references:

- pr0bel1230/max-api-docs — protocol/calls.md
- anazoa/anazoa — reveng/call_via_sdk.py (Apache-2.0 repository)

We do **not** copy undocumented third-party source into K&C unless its license permits it. The K&C implementation should be written against observed protocol behaviour and isolated behind its own provider adapter.

Two MAX entries (Max 1 / Max 2) are treated as two independently configurable profiles of the same provider family so Smart Route can fail over between separate call/session configurations.

## Yandex findings

A public Android experiment contains a Yandex Telemost credential flow:

1. Parse a Telemost conference link.
2. Obtain conference metadata.
3. Connect to the returned media-server WebSocket.
4. Send a Telemost hello message.
5. Parse serverHello -> rtcConfiguration -> iceServers.
6. Select a TURN URL and its username/credential.

Reference:

- hightemp/turn_proxy_connector — YandexCredentialFetcher.kt

That repository did not expose an obvious license file during this review, therefore its source is treated as research material only; K&C code must be independently implemented.

## iOS implementation plan

1. Provider-neutral TURN credential model/parser — **added**.
2. MAX credential adapter — pending.
3. Yandex Telemost credential adapter — pending.
4. Pass acquired relay address/credential material into the existing PacketTunnel transport — pending.
5. Add health checks and Smart Route scoring per provider — pending.
6. Physical-iPhone verification — required before marking a provider as working.

## Safety / truthfulness rule

A visible route can be labelled Ready only after:
- credentials are acquired from that provider,
- the PacketTunnel passes traffic,
- reconnect works,
- failure is detected,
- Smart Route can leave the failed path,
- the result is reproduced on a physical iPhone.

Until then MAX/Yandex remain Experimental.
