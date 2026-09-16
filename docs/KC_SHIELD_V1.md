# K&C Smart Proxy v1

## Product direction

K&C Smart Proxy is an iPhone-first private network companion built on the existing VPN/TURN tunnel engine.

### Core modules

1. **Connect** — one-tap connection with a calm, readable status screen.
2. **Health** — connection diagnostics, latency/quality checks, DNS and tunnel health.
3. **Smart Route** — automatically rank configured transports and select the healthiest available route.
4. **Assistant** — explain network problems in plain language and suggest safe fixes based on app diagnostics.
5. **Proxy** — user-provided/personal proxy profiles and routing rules.

## Multi-transport architecture

The product uses a provider-neutral `KCSmartTransportManager`.

Planned transport adapters:
- VK
- Yandex
- MAX
- Custom/private transport

The selector only ranks transports that are explicitly configured by a concrete adapter. Provider-specific endpoints and credentials are not hard-coded in the routing policy layer.

Ranking inputs:
- reachability
- latency
- consecutive failures
- later: packet loss, handshake time, recent stability and route cost

Failover principle:
- use the highest-scoring configured transport;
- degrade the score when failures repeat;
- switch only to a transport that its adapter has reported as configured and reachable;
- keep manual selection available for diagnostics.

## K&C design language

- Light smoke-grey background rather than a black UI.
- White/translucent surfaces with restrained contrast.
- Graphite text instead of pure black.
- Soft cold-blue accent for active/protected state.
- Main K&C control is the visual focus.
- When connected, the K&C control gets a soft blue glow.
- Large readable typography and generous spacing.
- Minimal technical noise on the main screen.
- `Kavoikoff&CO.` appears subtly at the lower-right of the primary screen.

## v1 implementation order

- [x] Add new K&C Smart Proxy home screen.
- [x] Preserve existing tunnel connect/disconnect engine.
- [x] Preserve Settings, Logs, Speed Test and connection-link import.
- [x] Add real Network Health screen.
- [x] Add provider-neutral Smart Transport selection core.
- [x] Show active transport and AUTO/MANUAL state on home screen.
- [ ] Feed live VK transport health into the selector.
- [ ] Add concrete Yandex adapter after protocol/endpoint verification.
- [ ] Add concrete MAX adapter after protocol/endpoint verification.
- [ ] Add latency/loss history and hysteresis to prevent route flapping.
- [ ] Add controlled failover between healthy configured transports.
- [ ] Add Assistant backed by diagnostics context.
- [ ] Add proxy profile support.
- [ ] Rebrand app/widget display names and visible legacy labels.
- [ ] Prepare signing/build pipeline and IPA release artifact.

## Safety rule

The Assistant must never silently change network configuration. It may diagnose and recommend changes; configuration changes require an explicit user action. Automatic failover is limited to transports the user has enabled/configured and can be disabled from the UI.
