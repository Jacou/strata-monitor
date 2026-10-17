# Strata Monitor — iOS app spec

Native SwiftUI iPhone app that shows the live stats of a Strata LLM server
(the "Monitor" tab of `http://<host>:8081`). No WebView.

## Server API (verified against the real server)

- `GET /health` — no auth. Sample: `StrataMonitorTests/Fixtures/health.json`.
- `GET /metrics` — needs header `Authorization: Bearer <api key>`; 401 without it.
  Sample: `StrataMonitorTests/Fixtures/metrics_idle.json`.
  `GET /metrics?requests=all` returns every kept request instead of the last 12.
- The web page polls `/metrics` every **1 s**. The app does the same while in the foreground.
- `docs/reference-app.js` is the web page's own JS. `render()`, `renderMonitor()`,
  `renderConvCache()`, `renderTotals()` (lines ~150–360) are the source of truth for
  which numbers are shown and how they are derived/formatted. Mirror them.

### /metrics top-level keys
`engine`, `live`, `requests` (newest first), `conversation_cache`, `requests_kept`,
`totals`, `hardware` (incl. `gpus[]`), `hardware_static`, `history` (arrays of ~60
samples per series: `tok_s`, `prefill_tok_s_mean`, `gpu_util`, `gpu_mem_used`,
`gpu_temp`, `gpu_power`, `gpu_pcie_rx_mb`, `cpu`, `disk_read_mb`), `time` (unix s).

**Decoding rule:** every field is optional (servers differ by version; `live.*` is
null when idle). Numbers may be int or float in JSON → decode numeric fields as
`Double?`. Some engine fields are strings that look like numbers (`pcie_frac`,
`spec_min_p`) and `cvec` can be int or string — be lenient. Unknown keys are ignored.
Never crash on a decode; a partial payload should still render.

`live.state` ∈ `idle | reading | generating`; `live.queued` is an int.
`requests[].finish` ∈ `stop | length | cancel | disconnect | error`.

## Screens

1. **Monitor** (main)
   - Header status pill: Idle / Reading prompt · N% / Generating · X tok/s / N queued
     / "Server not reachable" (after 3 consecutive failures) / "API key needed" (401).
   - Live state card: label, detail line, progress bar (same logic as `renderMonitor`).
   - 8 metric tiles in a 2-column grid, each with value, unit, subtitle and a sparkline
     from `history` (Swift Charts): Speed (decode + prefill), GPU load, VRAM, GPU temp,
     Power, PCIe, CPU, Disk read. Per-GPU subtitles when >1 GPU.
   - Context ring (used / max_context), expert cache bar, RAM bar (red > 92%), temp bar.
   - Conversation cache card (`conversation_cache`): slots bar, memory bar, summary, facts.
   - Recent requests list (time, finish badge, prompt, reused, output, tok/s,
     hit rate (+PCIe share), duration) + totals line. "Show all" toggles `?requests=all`.
2. **About**: engine / hardware facts (mirror `renderAbout`).
3. **Settings**: server base URL (default `http://192.168.1.10:8081`), API key
   (stored in Keychain, never in UserDefaults or source), "Test connection" button
   (calls /health then /metrics).

## Architecture

- `StrataMonitor/Sources/Models/` — `Codable` structs (`Metrics`, `Health`, …).
- `StrataMonitor/Sources/Networking/StrataClient.swift` — async/await `URLSession`
  client: `health()`, `metrics(allRequests:)`. Typed errors: `.unauthorized`,
  `.http(Int)`, `.unreachable`, `.decoding`. 5 s timeout.
- `StrataMonitor/Sources/Networking/MetricsPoller.swift` — `@Observable @MainActor`
  class; polls every 1 s while active; pauses on `scenePhase != .active`; tracks
  consecutive failures; exposes `metrics`, `status`, `lastUpdated`.
- `StrataMonitor/Sources/Settings/` — `Keychain` helper + `AppSettings`.
- `StrataMonitor/Sources/Views/` — SwiftUI views. `Format.swift` mirrors the JS
  helpers `fmt`, `gb`, `kfmt`, `ctxfmt`, `since`.
- iOS 18+, Swift 6 strict concurrency, no third-party packages.

## Build / test

```
xcodegen generate
xcodebuild -scheme StrataMonitor -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
  -derivedDataPath build/DerivedData -collect-test-diagnostics never build test
```
Without `-collect-test-diagnostics never`, xcodebuild hangs ~6 min after a failing run
collecting simulator diagnostics.

```
# failure details without rerunning:
xcrun xcresulttool get test-results tests --path build/DerivedData/Logs/Test/<latest>.xcresult
```
