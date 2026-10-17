# Tasks (orchestrator: Claude · implementer: Pi)

Read `docs/SPEC.md` first. Do one task at a time. When done, the build+test command in
the spec must pass. Do NOT commit — the orchestrator reviews and commits.
Never write the API key into any file.

## T1 — Data layer (no UI beyond a placeholder)
1. `StrataMonitor/Sources/App/StrataMonitorApp.swift`: `@main` app showing a placeholder `Text("Strata")`.
2. `Models/Metrics.swift`, `Models/Health.swift`: lenient Codable models for every key
   in the fixtures (all optional, numbers as `Double?`, `LenientString` helper for
   fields that may be number-or-string). `Request` must be `Identifiable` (id = `time`).
3. `Networking/StrataClient.swift` and `Networking/MetricsPoller.swift` per spec.
4. `Settings/Keychain.swift` (Security framework, generic password) + `Settings/AppSettings.swift`
   (`@Observable`; baseURL in UserDefaults, apiKey via Keychain).
5. `Views/Format.swift`: port `fmt`, `gb`, `kfmt`, `ctxfmt`, `since` from `docs/reference-app.js`.
6. Tests in `StrataMonitorTests/`: decode both fixtures (load via `Bundle(for:)` — add the
   Fixtures folder as test resources in `project.yml`), decode a payload where every
   `live` field is null, decode `{}`, and unit tests for Format helpers.
7. Run `xcodegen generate` then the build+test command. Fix until green.

T1 ✅ done (commit after 031488d).

Answers to T1 questions: projection Bool? is right (JS only tests truthiness). String(time) id: OK.
Keep History.ramUsed. "–" for non-finite: OK. Keep `.decoding(String)`. Settings: never fall back
silently — show an inline error and disable Save while `isValidBaseURL` is false.

## T2 — App shell + Settings (makes the app runnable)
1. `App/StrataMonitorApp.swift`: create one `AppSettings` and one `MetricsPoller` (from
   `settings.makeClient()`), put them in the environment, start polling, and wire
   `scenePhase` → `poller.setActive(phase == .active)`.
2. `Views/RootView.swift`: `TabView` with Monitor (SF Symbol `waveform.path.ecg`), About
   (`info.circle`), Settings (`gearshape`). Monitor/About can be placeholders that show
   `poller.status.text` and `lastUpdated` for now.
3. `Views/SettingsView.swift`: `Form` with server URL field (URL keyboard, no autocorrect /
   autocapitalisation), API key `SecureField` with show/hide toggle, Save button (disabled +
   inline red error when URL invalid), and "Test connection" (calls `health()` then `metrics()`,
   shows ✓ model name or the error in plain words: unauthorized → "Wrong or missing API key").
   On save → `poller.update(client: settings.makeClient())`.
4. If no API key is stored on first launch, open on the Settings tab.
5. Build + test green. Then launch it in the simulator (`xcrun simctl install booted …` +
   `xcrun simctl launch booted com.jacou.StrataMonitor`) and take a screenshot with
   `xcrun simctl io booted screenshot docs/screens/t2-settings.png`.

T2 ✅ done. Answers: (1) fallback client is fine. (2) yes, test the draft values. (3) keep
Save-both, no autosave. (4) placeholder notes go away in T3/T4.

## T3 — Monitor screen
Mirror `renderMonitor` / `renderConvCache` / `renderTotals` in docs/reference-app.js. Put
the derivation logic (labels, sub-lines, percentages) in a testable `MonitorViewModel`
(plain struct built from `Metrics`), and keep views thin. Use Swift Charts for sparklines.
Order, top to bottom, in a ScrollView:
1. Toolbar: `StatusPill` (colour by state: idle grey, reading blue, generating green,
   queued orange, error red) + "updated Xs ago".
2. Live state card: label, detail, progress bar.
3. Metric tiles, `LazyVGrid` 2 columns (1 column at accessibility text sizes):
   Speed (decode + prefill values, two sparklines), GPU load, VRAM, GPU temp, Power,
   PCIe, CPU, Disk read: value + unit + sub-line + sparkline (area + line, max as in JS).
4. Resources card: context ring (`Gauge` circular or custom ring) "used / max", expert cache
   bar, RAM bar (red > 92%), GPU temp bar.
5. Conversation cache card (hidden when `conversation_cache` is nil).
6. Recent requests: a list of compact rows (time · finish badge · prompt/reused/out tokens ·
   tok/s · hit rate (+PCIe) · duration). "Show all (N)" button → `poller.setAllRequests`.
   Totals line under it.
7. Pull to refresh → `poller.pollOnce()`.
Tests: view-model tests against both fixtures (idle + generating) for every label/sub-line.
Debug convenience (DEBUG builds only): if env var `STRATA_API_KEY` is set at launch and
no key is stored, save it to the Keychain. Then screenshot live data with
`SIMCTL_CHILD_STRATA_API_KEY=<key from the user> xcrun simctl launch booted com.jacou.StrataMonitor`.
The orchestrator will run that launch — you take screenshots with
`docs/screens/t3-monitor-*.png` only if the key is already stored; otherwise say so.
Support dark mode; check both.
T3 ✅ done. Verified on LIVE data (docs/screens/t3-monitor-live-*.png). The key is now
stored in the booted simulator's Keychain, so you can screenshot live data yourself from now on.

## T3.1 — Monitor polish (from orchestrator review of the screenshots)
1. Metric grid: tiles in the same row have different heights and tops (Speed vs GPU load,
   VRAM vs GPU temp). Make every tile in a row the same height and top-aligned
   (`.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)` inside a
   `Grid`/`GridRow`, or a fixed tile layout), with sparklines pinned to the bottom.
2. Live-state progress bar shows a blue sliver at 0%; draw nothing when the value is 0.
3. Context ring: at 2% it draws a round-cap blob. Mirror the JS: hide the arc when it's
   shorter than about 1% of the circumference. Also mirror the JS geometry, a 270° gauge
   open at the bottom (235.6 of 314.2), instead of a full circle.
4. Conversation cache facts: multi-line values are centre-aligned. Make values
   leading-aligned, in a 2-column `Grid` with labels in the first column.
5. Status pill: Idle should be grey (secondary) per the spec, not green. Green is for generating.
6. Hide `updated just now` when status is unreachable/unauthorized; show "last data Xs ago" instead.
Screenshot top + bottom in light and dark after the fix (`docs/screens/t31-*.png`).

T3.1 ✅ done. Keep the DEBUG `--scroll-to` launch arg; it's useful.

## T4 — About screen + polish
0. Bug from review (t31-monitor-resources-dark.png): the context gauge is rotated 90°. The gap
   is on the RIGHT, and it must be at the BOTTOM: the arc starts at about 7:30, runs clockwise over
   the top and ends at about 4:30, with the fill starting at 7:30. (A trim of 0…0.75 on a Circle
   needs `.rotationEffect(.degrees(135))`.)
1. `AboutView`: mirror `renderAbout` in docs/reference-app.js, as grouped `List` sections:
   Engine (model, engine version, context, KV cache, experts in VRAM, speculation, images,
   experimental speed projection if any), Hardware (GPU(s), CPU, RAM), API (OpenAI base URL
   `<base>/v1`, Anthropic base URL, model name; each with a copy button → UIPasteboard).
   Plus a footer link to https://github.com/Niko1221/Strata. Logic in a testable view model.
2. App icon: a simple generated 1024×1024 PNG (draw it with a small Swift/CoreGraphics script,
   or Python if PIL is available): dark rounded background with a teal/blue pulse line.
   Add it via an asset catalog `StrataMonitor/Assets.xcassets/AppIcon.appiconset`, single-size.
3. Haptics/accessibility pass: VoiceOver labels on the metric tiles ("Speed, 98.5 tokens per
   second, decode last request") and the status pill. No sparkline noise for VoiceOver.
4. Write a short README.md: what it is, screenshots (docs/screens), how to build
   (xcodegen + xcodebuild), and how to set the server URL/key; set DEVELOPMENT_TEAM in Xcode to
   run on a device. No key in the README.
5. Tests green. Screenshots: `docs/screens/t4-about-{light,dark}.png` and
   `docs/screens/t4-gauge.png`.

T4 ✅ done. Repo pushed to GitHub.

## T5 — iPad layout
The app already runs on iPad (TARGETED_DEVICE_FAMILY 1,2) but was never designed for it.
See `docs/screens/t5-ipad-before.png` (iPad Pro 13" portrait, live data). Fix:
1. Metric tiles: on a regular horizontal size class, show **4 columns** (2 rows of 4). Today the
   adaptive grid gives 5 + 3 with a gap. Keep 2 columns on iPhone, and 1 column at accessibility
   text sizes. In iPad landscape, 4 columns is still right.
2. Recent requests: in regular width, render a real table like the web page: columns Time, Status,
   Prompt, Reused, Output, tok/s, Hit rate (+PCIe), Duration, right-aligned numbers, and
   monospaced digits (`.monospacedDigit()`). SwiftUI `Grid` is fine. Keep the compact rows on iPhone.
3. Wide-screen composition: in regular width, put the Resources card and the Conversation cache
   card **side by side** (an equal-height `HStack`), and cap the content width so the cards don't
   stretch absurdly on a 13" landscape screen (e.g. `.frame(maxWidth: 1200)` centred).
4. Sparklines look flat and thin at iPad tile size: give tiles a slightly taller chart area on
   regular width.
5. About and Settings: cap the form/list width on iPad (readable width), not full-bleed.
6. Info.plist: add `UISupportedInterfaceOrientations~ipad` with all 4 orientations (including
   PortraitUpsideDown) so the app supports iPad multitasking (Split View, Stage Manager). Check that
   the layout adapts in a narrow Split View, where the size class becomes compact and it should
   fall back to the iPhone layout.
7. Tests green (`-collect-test-diagnostics never`). Put the column-count / layout-mode decision in
   a small testable function and test it.
8. Screenshots on the **iPad Pro 13-inch (M5)** simulator (UDID C0029454-A211-4A0E-B2F6-C8DA48BBC3DB,
   already booted, key already stored): `docs/screens/t5-ipad-{portrait,landscape}-{top,bottom}.png`
   (rotate with your DEBUG helpers or `xcrun simctl`; say so if rotation can't be scripted), plus
   one iPhone screenshot to prove nothing regressed: `docs/screens/t5-iphone-top.png`.

T5 ✅ done (installed on the user's iPad).

## T6 — "Mission control" theme
The user picked a dark-first, glowing-cyan look. Mockup reference: the orchestrator's canvas
(not in the repo); the spec below is the source of truth. Keep every screen's structure and all
the T5 layout rules; this task only changes the visual layer. Follow the system colour scheme
(no forced dark mode); dark is the showcase, light is a clean variant of the same tokens.

### Tokens — `Sources/Theme/Theme.swift`, injected via `@Environment(\.theme)`, resolved per colour scheme
| token | dark | light |
|---|---|---|
| background | #070B14 | #F3F6FB |
| headerGlow (radial, top centre, 60% height) | rgba(31,184,221,.22) → clear | rgba(10,143,181,.12) → clear |
| card fill | linear #121B2E → #0B111F (92% opacity) | #FFFFFF |
| card border (1 pt hairline) | rgba(79,227,255,.14) | rgba(10,143,181,.16) |
| card radius | 16 | 16 |
| text primary / secondary / tertiary | #E6EDF7 / #8FA3BF / #6E82A0 | #0E1726 / #5B6B82 / #7B8AA0 |
| accent | #4FE3FF | #0A8FB5 |
| accentDim (gradient start) | #1FB8DD | #0B7A9C |
| warn (temperature) | #FFB454 | #C77A14 |
| danger | #FF5C7A | #C8324F |
| track (bar/gauge background) | #162034 | #E3E9F2 |
| separator | rgba(255,255,255,.06) | rgba(0,0,0,.07) |
Glow = `.shadow(color: accent.opacity(0.55), radius: 6)` in dark; **no glow in light**.

### Type
- System font (SF). Metric values: `.system(size: 26, weight: .semibold, design: .monospaced)`
  + `.monospacedDigit()`. All numbers anywhere: monospaced digits.
- Tile labels: 12 pt, uppercase, `.tracking(0.5)`, text secondary.
- Title "Monitor": 30 pt semibold, tracking -0.5.

### Components
1. **Background**: `background` colour + `headerGlow` radial gradient behind the whole scroll
   view. Set the tab bar / nav bar to match (dark: translucent over #070B14, tint = accent).
2. **Status pill**: outlined capsule, 1 pt border in the state colour at 35% opacity, fill at 8%,
   text in the state colour, weight 600. State colours: idle = text secondary, reading = accent,
   generating = accent + an 8 pt dot that pulses (scale/opacity ring, 1.6 s, `repeatForever`,
   stop when not generating; respect `accessibilityReduceMotion`), queued = warn, error = danger.
3. **Cards**: fill + hairline border + radius, inner top highlight `rgba(255,255,255,.04)` 1 pt.
4. **Metric tiles**: headline value in text primary, except Speed decode in accent with glow and
   GPU temp in warn with glow. Sub-line text tertiary 11 pt.
5. **Sparklines**: line 1.8 pt in accent (warn for temp) with glow; area fill linear gradient
   accent 35% → 0%. If the 1 s redraw drops frames on the iPad simulator, wrap the chart in
   `.drawingGroup()` and/or drop the glow to radius 3.
6. **Bars** (progress, resources, conv cache): 6 pt, radius 3, track = `track`, fill = linear
   gradient accentDim → accent, glow in dark. RAM > 92 % uses danger. Temp bar uses warn.
7. **Context gauge**: track = `track`, fill = accent with glow; centre value 22 pt mono.
8. **Requests list / table**: separators = `separator`; numbers mono; finish badges: outlined
   capsules in accent (Done), warn (Max tokens / Stopped / Closed), danger (Error), 11 pt.
9. **About & Settings**: `.scrollContentBackground(.hidden)`, themed background, each section as
   a card (use `.listRowBackground` with the card fill or a custom Form look). Inputs keep system
   controls. The red error line uses danger.
10. **App icon**: regenerate with `tools/make-icon.swift` using background #070B14 and the cyan
    accent with glow (same pulse motif).
11. Status bar: light content on dark.

### Rules
- No new dependencies, no custom fonts, no hex literals outside `Theme.swift`.
- `MonitorStatus.tint` now comes from the theme (update MonitorChromeTests accordingly).
- Contrast: every text/background pair ≥ 4.5:1 (tertiary on card in dark is ~5:1 — keep it).
- Tests green with `-collect-test-diagnostics never`. Add a small `ThemeTests` (dark/light
  token resolution, status → colour mapping).
- Screenshots: `docs/screens/t6-{iphone,ipad}-{dark,light}-top.png`, `t6-iphone-dark-bottom.png`,
  `t6-about-dark.png`, `t6-settings-dark.png`. Update README screenshots to the new ones.

T6 ✅ done (d98586b, installed on the iPad).

## T7 — Strata extras (small batch, queued after T6)
0. **Fix from T6 review**: with the nav bar hidden, scrolled content shows through under the
   status bar clock (see t6-iphone-dark-bottom.png). Add a top safe-area overlay: a thin
   `.ultraThinMaterial`-free gradient of the theme background (opaque at the top edge → clear
   over ~24 pt) pinned with `.safeAreaInset(edge: .top)` or an overlay ignoring the safe area,
   on all three screens, both colour schemes. iPad too.
1. **Session card** (replaces the totals line under requests): since <time> · uptime · requests ·
   prompt tokens read (+reused %) at X tok/s · written at Y tok/s · **speculative acceptance**
   `drafts_accepted / drafts_offered` as a % with a small bar · tool calls recovered from
   reasoning. Per-request acceptance % also appears in the detail sheet.
2. **Per-request detail sheet**: tap a request row → sheet with time, finish, duration, prompt /
   reused / read / output tokens, prefill ms + tok/s, decode ms + tok/s, drafts offered/accepted
   (+%), expert hit rate, PCIe share, reasoning recoveries, repeat coverage, images (ram_blobs,
   file_blobs, file_mb), projection on/off. Facts grid, same style as the conv-cache card.
3. **Model loaded state** from `/health` (`loaded`): when false, the pill shows "Model unloaded"
   (text secondary) and the live card says "Waiting for the first request to load the model".
   Poll `/health` every 10 s alongside `/metrics` (like the web page's mcpTick cadence).
Tests for the derivations; screenshots `docs/screens/t7-*.png`.

T7 ✅ done.

## T7.5 — Shared core package + macOS menu bar app (before T8)
0. Nit from T7 review: the Session card prints the uptime twice (corner badge and headline); keep
   only the corner badge.
**Refactor first (no behaviour change):** create a local Swift package `Packages/StrataCore`
(iOS 18 / macOS 15) and move into it: `Models/`, `Networking/`, `Settings/` (Keychain works on
both), `Views/Format.swift`, `Theme/`, `Support/MonitorLayout.swift`, and the platform-neutral
views: `StatusPill`, `Sparkline`, `ProgressBar`, `MetricTileView`, `ResourcesCard` (gauge),
`ConversationCacheCard`, `MonitorViewModel`, `AboutViewModel`. Guard UIKit-only bits with
`#if canImport(UIKit)` (pasteboard → `NSPasteboard` on macOS, debug launch args stay in the iOS
app). Move the matching tests into the package's test target; the iOS target depends on the
package (`packages:` + `dependencies: - package: StrataCore` in project.yml). All 140+ tests
still green on iOS before the Mac work starts.

**Mac target `StrataMenuBar`** (macOS 15, `LSUIElement: true`, App Sandbox with
`com.apple.security.network.client`, same `DEVELOPMENT_TEAM`, bundle id `com.jacou.StrataMenuBar`,
own Keychain entry but same `AppSettings` code):
1. `MenuBarExtra` with `.window` style. **Label**: an SF Symbol per state (`pause.circle` idle,
   `text.magnifyingglass` reading, `bolt.fill` generating, `exclamationmark.triangle` error) plus
   text: generating → `104 t/s`, reading → `42%`, idle → nothing, unreachable → `—`. Update every
   poll; keep the label width stable with monospaced digits.
2. **Popover content (≈ 360 × 520, Mission control tokens, follows system appearance)**: status
   pill + "updated Xs ago"; live state card; a 2-column grid of the 8 metric tiles (compact
   variant: smaller value, 28 pt sparkline); the context gauge + expert cache / RAM / temp bars;
   the last 5 requests as compact rows; footer with the model name, "Open Strata web page"
   (opens `<baseURL>` in the browser), Settings…, Quit.
3. **Settings window** (`Settings` scene): server URL + API key (Keychain) + Test connection,
   same `ConnectionTester`; a "Launch at login" toggle via `SMAppService.mainApp`.
4. Polling runs continuously (menu bar apps have no scene phase); 1 s while the popover is
   open, **5 s when closed** (label only needs that) — add an `interval` setter to `MetricsPoller`.
5. Optional: a hover tooltip on the label with the model name and last request summary.
Build: `xcodebuild -scheme StrataMenuBar -destination 'platform=macOS' build`; run it with
`open build/DerivedData/Build/Products/Debug/StrataMenuBar.app`; screenshot the popover with
`screencapture -x docs/screens/t75-menubar.png` (the orchestrator can also do this).
Tests: package tests green on both platforms (`-destination 'platform=macOS'` for the package),
label-text derivation tests. README gains a macOS section.

T7.5 ✅ done (af311ab).

## T7.6 — Hover card on the menu bar icon (macOS)
Hovering the menu bar icon must show the current state and the decode / prefill speeds without
clicking. SwiftUI `MenuBarExtra` gives no mouse-enter hook and `.help()` tooltips appear late
and as plain text, so swap the plumbing for AppKit while keeping every SwiftUI view:
1. Replace `MenuBarExtra` with an `NSStatusItem` owned by an `@MainActor` `StatusItemController`
   (created from the `App` via `NSApplicationDelegateAdaptor`). Its button hosts the existing
   label view through `NSHostingView` (icon + monospaced text, same derivation and tests).
2. **Hover card**: an `NSTrackingArea` on the button (`.mouseEnteredAndExited, .activeAlways`).
   On enter, after 120 ms, show an `NSPopover` (`behavior = .applicationDefined`, non-activating,
   no arrow highlight needed) anchored to the button; on exit (and when the pointer leaves the
   card itself after 250 ms) close it. Content, ~260 pt wide, Mission control tokens:
   - status pill (Idle / Reading prompt · 42 % / Generating · thinking / N queued / Model
     unloaded / Server not reachable / API key needed)
   - two big mono values side by side: **Decode** and **Prefill** in t/s. While generating:
     live `tok_s` and `prefill_tok_s_mean`, captioned "now"; while reading: prefill now, decode
     "–"; idle: the last request's values, captioned "last request". Nil → "–".
   - one small line: model name · "updated Xs ago".
   No buttons in the hover card; it is read-only.
3. **Click** toggles the full popover (existing content), closes the hover card first, and the
   hover card must not reappear while the full popover is open. Right-click opens a minimal
   `NSMenu` with Settings… and Quit.
4. While the hover card is open, poll at 1 s (same as the full popover); 5 s otherwise.
5. `Settings` scene stays; open it with `NSApp.sendAction(Selector(("showSettingsWindow:")))`
   or the macOS 14+ `SettingsLink`-equivalent that works from AppKit — whichever is reliable;
   activate the app first so the window comes to the front.
6. Tests: hover-card derivation (state → pill text, decode/prefill text + caption per state) in
   the package or the app test target. Build, relaunch with `open`, and say when it's running;
   the orchestrator/user will check the hover by hand (no screenshot possible).

T7.6 ✅ done (228603e).

## T7.7 — HOTFIX: hover card does not appear
Hovering the menu bar icon shows nothing although the live label updates. Instrument with
`os_log` (subsystem `com.jacou.StrataMenuBar`, category `hover`) on every step of the hover path,
relaunch, read `log stream` while the user hovers, and fix from evidence. Candidate fixes: (a) no
enter events → global + local mouse-moved monitors testing `NSEvent.mouseLocation` against the
button's screen frame (no Accessibility permission needed); (b) zero-size card → measure after
`layoutSubtreeIfNeeded()` / fixed 260 pt width; (c) popover refuses to show while inactive →
non-activating borderless `NSPanel` at `.statusBar` level. Also add a Mac setting
"Refresh when closed": 5 s (default) / 15 s / 30 s. Instrumentation out (or DEBUG env-gated),
package tests green, relaunch, report what the log showed.

## T8 — Request trends + Config viewer
1. **Trends card** on Monitor, between the resources row and the requests list: Swift Charts,
   last N requests from `metrics?requests=all` (poller already supports it; fetch "all" once on
   appear and every 30 s, keep the 1 s poll on the normal payload). Two series toggled by a
   segmented control: **Decode tok/s** (line + points) and **Expert hit rate %** (line); x = time,
   oldest left. Tap a point → highlight the matching request row. Hide the card with < 3 requests.
   iPad: card spans the full width. Also a third option **Prefill tok/s** = (prompt_tokens −
   reused) / (prompt_ms / 1000).
2. **Config screen** (new tab "Config", SF Symbol `slider.horizontal.3`): `GET /config` → file
   name + one row per key: key, current value (or "default"), kind, Strata's help text as the
   footnote. Group by prefix (`sampling.*` together). **Editable**: tap a row → sheet with the
   right control per `kind` (number → decimal field, bool → toggle, enum → picker from the
   server's options if present, names → text). Save → `POST /config` with `{"set": {key: value}}`
   (see `docs/reference-app.js` ~line 478 for the exact body and reply handling) then re-fetch.
   Clearing a value sends null. Show the server's error message on failure. Models for every
   `kind` value in the payload must be lenient.
Tests for the trend derivations and config decoding/encoding; screenshots `docs/screens/t8-*.png`.

## T9 — Chat (after T8)
A streaming chat tab (SF Symbol `bubble.left.and.text.bubble.right`) against
`POST /v1/chat/completions`, mirroring `send()` in `docs/reference-app.js` (~line 760).
1. **Request**: `{model: health.model, messages, stream: true, reasoning_effort, temperature,
   top_p, top_k, max_tokens, seed}`; defaults as the web page's `DEFAULTS` (line ~557):
   thinking "high", temperature 0.6, top_p 0.95, top_k 20, no max/seed. temperature 0 → send
   only `temperature: 0` (greedy), like the JS. Settings sheet in the chat: thinking effort
   (the `data-v` values of the web page's thinking selector), temperature/top_p/top_k, max
   tokens, seed, system prompt.
2. **Streaming**: `URLSession.bytes(for:)` + `lines`; parse SSE `data:` lines, ignore `:` keep-alive
   comments, stop at `[DONE]`; `delta.reasoning_content` → a collapsible "Thinking…" block above
   the answer (collapsed by default once content starts; show thinking seconds); `delta.content`
   → the answer; `usage.completion_tokens` → meta line "N tokens · X tok/s" like the web page.
   A `j.error` mid-stream → show the message in the bubble. Stop button cancels the task.
3. **UI**: message list (user right-aligned accent-tinted card, assistant plain card), Markdown
   via `Text(AttributedString(markdown:))` with code blocks in a monospaced box; input bar with
   multi-line field, send/stop; "New chat" button; conversations persisted in
   `Application Support` as JSON (last 20); no images/files in v1 (note it in the UI if the
   server reports `images: true`).
4. While a chat request streams, the Monitor tab's live card should show it like any other
   request (it already will — just verify).
5. Theme: Mission control tokens; the assistant bubble uses the card style, user bubble uses
   accent at 12 % fill + hairline accent border.
Tests: SSE line parser, request-body builder (field presence per settings), persistence
round-trip. Screenshots `docs/screens/t9-chat-{dark,light}.png` with a real exchange.

T8 ✅ done (a905fef).

## T8.1 — Menu bar item must not shift (macOS, independent of T8)
When the label changes (idle ↔ `104 t/s` ↔ `42%`) while the hover card or popover is open, the
card slides left/right because the item's width changes and the popover is anchored to the whole
button. Fix in `StrataMenuBar/Sources/` only (StatusItemController, MenuBarStatusLabel):
1. Put the **icon on the right** and the text to its left. macOS lays status items out from the
   right edge, so the icon's screen position is then stable while the text grows leftward.
2. Anchor `fullPopover.show(relativeTo:)` and `hoverPopover.show(relativeTo:)` to the **icon's
   rect** (the rightmost ~18 pt of the button, in button coordinates), not `button.bounds`.
3. While either card is shown, **freeze `statusItem.length`** (skip the resize in
   `refreshLabel`; apply the pending width when the card closes), so neighbouring items don't
   jump under the pointer either.
4. The mouse-moved hit test keeps using the full button frame.
5. Package/app tests green, rebuild, `pkill -f StrataMenuBar.app`, relaunch with `open`, short
   summary. Don't touch iOS files or anything another session is editing.

T8.1 ✅ done.

## T9.1 — Hover card must resize immediately when its text changes (macOS)
Observed: the hover card opens at the size of its first content; when the pill changes (Idle →
Reading prompt → Generating · thinking) the SwiftUI content reflows but the NSPopover keeps the
old size until reopened. Fix in `StrataMenuBar/Sources/` only:
1. Host the card in an `NSHostingView` with `sizingOptions = [.preferredContentSize]` (set
   `hoverPopover.contentViewController = NSHostingController(rootView:)` with the same option)
   so SwiftUI pushes size changes to the popover live; drop the manual `fittingSize` snapshot.
   Keep the `TrackingHostView` behaviour (pointer in/out of the card) — wrap or subclass so the
   tracking still works.
2. Make the layout state-stable so resizing is rare anyway: fixed card width (260 pt), the pill
   on its own line with `lineLimit(1)`, Decode / Prefill values in a two-column `Grid` with a
   reserved minimum width for the largest value (`"9999.9"` in the mono font, measured once),
   captions always present ("now" / "last request" / "–").
3. Same `sizingOptions` treatment for the full popover.
4. Package tests green, rebuild, `pkill -f StrataMenuBar.app`, relaunch with `open`, short
   summary.

T9 ✅ done (views finished by the orchestrator while Pi was offline).
