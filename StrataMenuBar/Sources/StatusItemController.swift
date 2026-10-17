import AppKit
import os.log
import StrataCore
import SwiftUI

/// Hover diagnostics, off unless `STRATA_HOVER_LOG=1` is in the environment:
/// `open --env STRATA_HOVER_LOG=1 build/DerivedData/Build/Products/Debug/StrataMenuBar.app`
private let hoverLog = Logger(subsystem: "com.jacou.StrataMenuBar", category: "hover")
private let hoverLogEnabled = ProcessInfo.processInfo.environment["STRATA_HOVER_LOG"] != nil

private func hoverLogLine(_ message: @escaping @autoclosure () -> String) {
    guard hoverLogEnabled else { return }
    hoverLog.log("\(message(), privacy: .public)")
}

/// The menu bar item, owned by AppKit.
///
/// `MenuBarExtra` has no mouse-enter hook and `.help()` arrives late as plain text, so the item is
/// an `NSStatusItem`: hover shows a small read-only card, a click toggles the full popover,
/// right-click gives Settings… and Quit. Every view inside it is still SwiftUI.
///
/// An `NSTrackingArea` on `NSStatusBarButton` never delivers enter/exit — the status bar window
/// swallows the pointer, so the tracking area sits there registered and silent (T7.7). The hover is
/// driven instead from mouse-move monitors plus a slow pointer check, comparing `NSEvent.mouseLocation`
/// with the button's rect in screen coordinates and deriving the transitions from that.
///
/// The item must not shift while a card is open: the label view puts the icon on the item's right edge
/// (macOS lays status items out from the right, so that edge is the stable one), both cards anchor to
/// the icon's rect rather than the whole button, and `statusItem.length` is pinned while either card
/// is on screen — see `MenuBarItemWidth`.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    /// Long enough to ignore the pointer crossing the menu bar, short enough to feel instant.
    static let hoverOpenDelay: TimeInterval = 0.12
    /// Long enough to cross the gap between the icon and the card.
    static let hoverCloseDelay: TimeInterval = 0.25

    #if DEBUG
    /// `--show-popover` / `--show-hover` open a card two seconds after launch and keep it open, so a
    /// screenshot can be taken without a pointer on the item.
    private let debugShowsPopover = ProcessInfo.processInfo.arguments.contains("--show-popover")
    private let debugHoldsHover = ProcessInfo.processInfo.arguments.contains("--show-hover")
    #endif
    /// Backstop for the mouse-move monitors: the pointer is checked this often.
    static let pointerCheckInterval: TimeInterval = 0.2
    /// The menu bar item is small; a point or two of slack keeps the edge from counting as a leave.
    static let pointerSlack: CGFloat = 2
    /// The slice of the item the icon occupies, and therefore the rect both cards anchor to.
    static let iconAnchorWidth: CGFloat = 18

    private let model: MenuBarModel

    private var statusItem: NSStatusItem?
    private var labelHosting: PassthroughHostingView<AnyView>?
    private var pendingShow: Task<Void, Never>?
    private var pendingHide: Task<Void, Never>?
    private var localPointerMonitor: Any?
    private var globalPointerMonitor: Any?
    private var pointerCheck: Timer?
    /// The transition state: the card opens on false → true and closes on true → false.
    private var pointerOnItem = false
    private var loggedFirstSample = false
    /// Non-nil while a card is on screen: the item's length is pinned at this and any width the label
    /// now wants waits in `pendingLength` until the card closes.
    private var pinnedLength: CGFloat?
    private var pendingLength: CGFloat?
    /// Whether the label view is currently allowed to draw its digits.
    private var labelShowsText = true
    /// True during the click that swaps the hover card for the full popover, so the width stays pinned
    /// across the handoff instead of resizing between the two cards.
    private var cardHandoff = false

    private let fullPopover = NSPopover()
    private let hoverPopover = NSPopover()

    init(model: MenuBarModel) {
        self.model = model
        super.init()

        fullPopover.behavior = .transient
        fullPopover.animates = true
        fullPopover.delegate = self

        // The hover card is not a menu: it must not take focus, and only we close it.
        hoverPopover.behavior = .applicationDefined
        hoverPopover.animates = false
        hoverPopover.delegate = self
    }

    // MARK: - the item

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        statusItem = item

        button.title = ""
        button.image = nil
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Strata Monitor")

        let hosting = PassthroughHostingView(rootView: labelRootView(showsText: true))
        // Only the height is AppKit's: the width and the flush-right origin are ours (placeLabel).
        hosting.autoresizingMask = [.height]
        button.addSubview(hosting)
        labelHosting = hosting

        refreshLabel()
        observeModel()
        watchPointer()
        hoverLogLine("install: bounds=\(String(describing: button.bounds)) length=\(item.length)")

        #if DEBUG
        if debugShowsPopover || debugHoldsHover {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                if self.debugShowsPopover { self.toggleFullPopover() } else { self.openHoverCard() }
            }
        }
        #endif
    }

    /// Where the pointer is, in screen coordinates: the item's rect in its own window, pushed out
    /// to the screen. nil while the item has no window yet.
    private var itemScreenRect: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Mouse-move monitors (the status bar window is ours, so the local one sees it; the global one
    /// covers the pointer arriving from another app) plus a slow check in case neither fires.
    private func watchPointer() {
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.checkPointer(source: "local") }
            return event
        }
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer(source: "global") }
        }
        let timer = Timer(timeInterval: Self.pointerCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer(source: "timer") }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerCheck = timer
    }

    /// One pointer sample: inside / outside the item (or the open card), and the transition it makes.
    private func checkPointer(source: String) {
        guard let item = itemScreenRect else { return }
        let mouse = NSEvent.mouseLocation
        let slack = Self.pointerSlack
        var inside = item.insetBy(dx: -slack, dy: -slack).contains(mouse)
        // The card sits a step away from the icon: while it is open, the pointer resting on it counts
        // as still being on the item.
        if !inside, let card = hoverPopover.contentViewController?.view.window {
            inside = card.frame.insetBy(dx: -slack, dy: -slack).contains(mouse)
        }
        if !loggedFirstSample {
            loggedFirstSample = true
            hoverLogLine("first sample (\(source)): item=\(String(describing: item)) mouse=\(String(describing: mouse)) inside=\(inside)")
        }
        guard inside != pointerOnItem else { return }
        pointerOnItem = inside
        hoverLogLine("pointer \(inside ? "entered" : "left") (\(source)) mouse=\(String(describing: mouse)) item=\(String(describing: item))")
        if inside { pointerEntered() } else { pointerLeft() }
    }

    private func labelRootView(showsText: Bool) -> AnyView {
        AnyView(MenuBarStatusLabel(model: model, showsText: showsText).strataTheme())
    }

    /// The item's width follows the label — the icon alone when idle, `104 t/s` when busy — except
    /// while a card is on screen, when it is pinned so the icon and the neighbours under the pointer
    /// stay put. See `MenuBarItemWidth` for the decision itself.
    private func refreshLabel() {
        guard let button = statusItem?.button, let hosting = labelHosting else { return }

        // Always measure the label at full size first, whatever the item is pinned to right now.
        setLabel(hosting, showsText: true)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let decision = MenuBarItemWidth(wanted: ceil(size.width), pinned: pinnedLength)
        let oldLength = statusItem?.length ?? -1
        if decision.length == nil, decision.wanted != oldLength {
            hoverLogLine("refreshLabel: pinned at \(oldLength), label wants \(decision.wanted), applying when the card closes")
        } else if let length = decision.length, length != oldLength {
            hoverLogLine("refreshLabel: length \(oldLength) -> \(length)")
        }
        if let length = decision.length {
            pendingLength = nil
            statusItem?.length = length
        } else {
            pendingLength = decision.wanted
        }
        setLabel(hosting, showsText: decision.showsText)
        placeLabel(hosting, in: button, maxWidth: decision.pinned)
    }

    private func setLabel(_ hosting: PassthroughHostingView<AnyView>, showsText: Bool) {
        guard showsText != labelShowsText else { return }
        labelShowsText = showsText
        hosting.rootView = labelRootView(showsText: showsText)
    }

    /// Flush-right inside the button, vertically centred: the icon rides the item's right edge, which
    /// is the edge macOS keeps fixed, so the text is what grows leftward. `maxWidth` is the pinned
    /// length, so while a card is open the label can only shrink to fit the item, never spill out of it.
    private func placeLabel(_ hosting: NSView, in button: NSStatusBarButton, maxWidth: CGFloat?) {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var width = ceil(size.width)
        if let maxWidth, maxWidth > 0 { width = min(width, maxWidth) }
        hosting.frame = CGRect(
            x: button.bounds.maxX - width,
            y: ((button.bounds.height - size.height) / 2).rounded(),
            width: width,
            height: ceil(size.height)
        )
    }

    /// Pin the item's width for as long as a card is on screen.
    private func pinLength() {
        guard pinnedLength == nil, let button = statusItem?.button else { return }
        let pinned = max(ceil(statusItem?.length ?? 0), ceil(button.bounds.width))
        pinnedLength = pinned
        hoverLogLine("pinLength: \(pinned)")
    }

    /// A card closed: if nothing else is on screen, let the item take the width it wanted meanwhile.
    private func releasePinnedLength() {
        guard pinnedLength != nil else { return }
        guard !cardHandoff, !fullPopover.isShown, !hoverPopover.isShown else { return }
        let pending = pendingLength
        pinnedLength = nil
        pendingLength = nil
        hoverLogLine("releasePinnedLength: pending=\(String(describing: pending))")
        refreshLabel()
    }

    /// The icon's rect in button coordinates: the rightmost slice of the item. Anchoring a card here
    /// instead of `button.bounds` is what stops it sliding sideways when the label changes length.
    private func iconRect(in button: NSStatusBarButton) -> NSRect {
        let width = min(Self.iconAnchorWidth, button.bounds.width)
        return NSRect(
            x: button.bounds.maxX - width,
            y: button.bounds.minY,
            width: width,
            height: button.bounds.height
        )
    }

    /// Re-measure the label whenever a poll changes the state, and refresh an open hover card.
    private func observeModel() {
        withObservationTracking {
            _ = model.status
            _ = model.modelName
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshLabel()
                self.observeModel()
            }
        }
    }

    // MARK: - clicks

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // A paused poller (the backoff gave up) starts again on any click.
        model.resumeIfPaused()
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(in: sender)
            return
        }
        pendingShow?.cancel()
        // Hold the width across the handoff from the hover card to the full popover.
        cardHandoff = true
        pinLength()
        closeHoverCard()
        toggleFullPopover()
        cardHandoff = false
        if !fullPopover.isShown, !hoverPopover.isShown { releasePinnedLength() }
    }

    private func toggleFullPopover() {
        guard let button = statusItem?.button else { return }

        if fullPopover.isShown {
            fullPopover.close()
        } else {
            // The popover follows the SwiftUI content as it reflows (a longer pill, more request
            // rows): `preferredContentSize` is what NSPopover animates to.
            let controller = NSViewController()
            let hosting = NSHostingView(rootView: MenuBarPopover(model: model).strataTheme()
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { [weak controller] size in
                    guard size.width > 0, size.height > 0 else { return }
                    controller?.preferredContentSize = size
                })
            controller.view = hosting
            controller.preferredContentSize = hosting.fittingSize
            fullPopover.contentViewController = controller

            pinLength()
            NSApp.activate(ignoringOtherApps: true)
            fullPopover.show(relativeTo: iconRect(in: button), of: button, preferredEdge: .minY)
        }
        applyCadence()
    }

    private func showMenu(in button: NSStatusBarButton) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        let quit = NSMenuItem(title: "Quit Strata Monitor", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(settings)
        menu.addItem(quit)
        let icon = iconRect(in: button)
        menu.popUp(positioning: nil, at: NSPoint(x: icon.minX, y: button.bounds.height + 6), in: button)
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // macOS 14 renamed the action; try the new one, then the old one.
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) { return }
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - hover

    /// The pointer settled on the item: open the card after a beat.
    private func pointerEntered() {
        let fullShown = fullPopover.isShown
        let hoverShown = hoverPopover.isShown
        hoverLogLine("pointerEntered: fullShown=\(fullShown) hoverShown=\(hoverShown)")
        // The full popover already says all of this; do not stack a card on top of it.
        guard !fullPopover.isShown else {
            hoverLogLine("pointerEntered: ignored, the full popover is open")
            return
        }
        pendingHide?.cancel()
        pendingShow?.cancel()
        pendingShow = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.hoverOpenDelay * 1_000_000_000))
            guard !Task.isCancelled else {
                hoverLogLine("pendingShow cancelled before opening")
                return
            }
            self.openHoverCard()
        }
    }

    /// The pointer left the item and the card: close after the crossing grace.
    private func pointerLeft() {
        let hoverShown = hoverPopover.isShown
        hoverLogLine("pointerLeft: hoverShown=\(hoverShown)")
        pendingShow?.cancel()
        scheduleHoverClose()
    }

    private func openHoverCard() {
        guard let button = statusItem?.button else {
            hoverLogLine("openHoverCard: no button")
            return
        }
        guard !fullPopover.isShown else {
            hoverLogLine("openHoverCard: refused, full popover open")
            return
        }
        guard !hoverPopover.isShown else {
            hoverLogLine("openHoverCard: refused, already shown")
            return
        }

        // The card's text changes while it is open (Idle → Reading prompt → Generating · thinking);
        // the SwiftUI content reports its new size and the popover follows at once, instead of
        // keeping the size it opened with.
        let controller = NSViewController()
        let hosting = PassthroughHostingView(rootView: AnyView(HoverCardView(model: model).strataTheme()
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { [weak controller] size in
                guard size.width > 0, size.height > 0 else { return }
                controller?.preferredContentSize = size
            }))
        let wrapper = TrackingHostView(frame: NSRect(origin: .zero, size: hosting.fittingSize))
        hosting.frame = wrapper.bounds
        hosting.autoresizingMask = [.width, .height]
        wrapper.addSubview(hosting)
        wrapper.onEnter = { [weak self] in self?.pendingHide?.cancel() }
        wrapper.onExit = { [weak self] in self?.scheduleHoverClose() }

        controller.view = wrapper
        controller.preferredContentSize = wrapper.frame.size
        hoverPopover.contentViewController = controller
        let fitting = String(describing: hosting.fittingSize)
        let wrapperFrame = String(describing: wrapper.frame)
        let buttonBounds = String(describing: button.bounds)
        let buttonWindow = String(describing: button.window)
        hoverLogLine("openHoverCard: hostingFitting=\(fitting) wrapper=\(wrapperFrame) buttonBounds=\(buttonBounds) buttonWindow=\(buttonWindow)")
        pinLength()
        hoverPopover.show(relativeTo: iconRect(in: button), of: button, preferredEdge: .minY)
        let shown = hoverPopover.isShown
        hoverLogLine("openHoverCard: show called, isShown=\(shown)")
        if let window = hoverPopover.contentViewController?.view.window {
            let frame = String(describing: window.frame)
            let screen = String(describing: window.screen)
            hoverLogLine("openHoverCard: popover window=\(frame) screen=\(screen)")
        } else {
            hoverLogLine("openHoverCard: popover has no window")
        }
        applyCadence()
    }

    private func scheduleHoverClose() {
        #if DEBUG
        if debugHoldsHover { return }
        #endif
        pendingHide?.cancel()
        pendingHide = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.hoverCloseDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.closeHoverCard()
        }
    }

    private func closeHoverCard() {
        guard hoverPopover.isShown else { return }
        hoverLogLine("closeHoverCard")
        hoverPopover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        let full = fullPopover.isShown
        let hover = hoverPopover.isShown
        hoverLogLine("popoverDidClose: full=\(full) hover=\(hover)")
        releasePinnedLength()
        applyCadence()
    }

    /// 1 s while either card is on screen, the chosen cadence when neither is.
    private func applyCadence() {
        let fast = fullPopover.isShown || hoverPopover.isShown
        hoverLogLine("applyCadence: fast=\(fast)")
        model.setFastPolling(fast)
    }
}

/// A hosting view that refuses hit-testing, so the status bar button keeps getting its clicks.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The menu bar item's width decision, kept free of AppKit so it can be reasoned about on its own.
///
/// Two things fight over the item's width: the label wants to grow and shrink with the text, while a
/// card that is open on screen needs the item — and therefore the icon both cards are anchored to — to
/// hold still, and the neighbouring items not to shuffle under the pointer.
struct MenuBarItemWidth {
    /// The width the label wants right now.
    let wanted: CGFloat
    /// Non-nil while the hover card or the full popover is on screen: the item is pinned at this width
    /// and nothing may change it until the card closes.
    let pinned: CGFloat?

    /// The length to put on the status item, or nil to leave it exactly as it is.
    var length: CGFloat? { pinned == nil ? wanted : nil }

    /// The width the item actually has.
    var effectiveLength: CGFloat { pinned ?? wanted }

    /// Whether the digits fit in the width the item actually has. When the item is pinned narrower than
    /// the label needs, the icon alone beats clipped digits — the card on screen already spells the
    /// state out.
    var showsText: Bool { pinned.map { wanted <= $0 } ?? true }
}

/// A plain container that reports the pointer entering and leaving it, which is how the hover card
/// survives the trip from the icon to the card.
private final class TrackingHostView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hoverLogLine("card mouseEntered")
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        hoverLogLine("card mouseExited")
        onExit?()
    }
}
