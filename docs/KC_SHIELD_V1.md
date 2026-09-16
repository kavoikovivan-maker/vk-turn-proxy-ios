# K&C Shield v1

## Product direction

K&C Shield is an iPhone-first private network companion built on the existing VPN/TURN tunnel engine.

### Core modules

1. **Connect** — one-tap VPN connection with a calm, readable status screen.
2. **Health** — connection diagnostics, latency/quality checks, DNS and tunnel health.
3. **Smart Route** — later phase: choose the most stable available route/server automatically.
4. **Assistant** — later phase: explain network problems in plain language and suggest safe fixes based on app diagnostics.
5. **Proxy** — later phase: user-provided/personal proxy profiles and routing rules.

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

- [x] Add new K&C Shield home screen.
- [x] Preserve existing tunnel connect/disconnect engine.
- [x] Preserve Settings, Logs, Speed Test and connection-link import.
- [ ] Rebrand app/widget display names and visible legacy labels.
- [ ] Add real network-health model (latency, loss, DNS, route state).
- [ ] Add Health screen with human-readable findings.
- [ ] Add safe auto-fix actions.
- [ ] Add Smart Route selection.
- [ ] Add Assistant backed by diagnostics context.
- [ ] Add proxy profile support.
- [ ] Prepare signing/build pipeline and IPA release artifact.

## Safety rule

The Assistant must never silently change network configuration. It may diagnose and recommend changes; configuration changes require an explicit user action.
