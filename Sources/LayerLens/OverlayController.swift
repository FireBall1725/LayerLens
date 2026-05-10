import AppKit
import SwiftUI

/// Owns the always-on-top floating overlay panel that mirrors the keyboard's
/// active layer in real time. The panel is a non-activating NSPanel hosting
/// a SwiftUI view, configured to float above other windows and ignore
/// keyboard focus so it doesn't steal events from whatever you're typing in.
///
/// Two modes:
///   - **Pinned**: user picked "Show Overlay" from the menu bar. The panel
///     stays visible until they pick "Hide Overlay" or close the window.
///   - **Flash**: a layerlens_notify event arrived. The panel fades in,
///     stays visible briefly, then fades out. Each new event resets the
///     fade-out timer, so holding a momentary layer keeps it visible.
/// Cross-actor escape hatch for AppKit callbacks. The strict-concurrency
/// checker can't see that NSWindowDelegate hops are main-actor-safe, so
/// we mark the carrier `@unchecked Sendable` ourselves.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

@MainActor
final class OverlayController {
    private var panel: NSPanel?
    /// Separate transparent panel used while Settings is open and the user is
    /// on an overlay-affecting tab. Renders a synthesized demo keyboard so the
    /// user can see the actual position, transparency, font, and theme on
    /// their wallpaper instead of guessing from a flat thumbnail.
    private var previewPanel: NSPanel?
    private weak var appState: AppState?
    private weak var preferences: Preferences?
    private var fadeOutTask: Task<Void, Never>?
    private var isPinned: Bool = false
    /// Set while `applyPlacement()` is calling `setFrameOrigin`, so the
    /// `windowDidMove` delegate doesn't mistake our own programmatic move
    /// for a user drag and flip placement back to `.custom`.
    private var isApplyingPlacement: Bool = false
    /// Token for the screen-parameters observer. Held so we can deregister
    /// in deinit / on app termination if needed (currently the controller
    /// lives for the app's lifetime, so this is mostly belt-and-braces).
    private var screenObserver: NSObjectProtocol?

    private static let fadeInDuration: Double = 0.15
    private static let fadeOutDuration: Double = 0.60

    /// Whether the user has Reduce Motion enabled in System Settings →
    /// Accessibility → Display. Read on every animation so changes apply
    /// without an app restart.
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Fade-in duration, collapsed to zero when Reduce Motion is on.
    private var effectiveFadeInDuration: Double {
        reduceMotion ? 0 : Self.fadeInDuration
    }

    /// Fade-out duration, collapsed to zero when Reduce Motion is on.
    private var effectiveFadeOutDuration: Double {
        reduceMotion ? 0 : Self.fadeOutDuration
    }

    /// User-configurable hold duration before the overlay fades. Reads
    /// `Preferences.overlayHoldDuration` at fire time so a slider change
    /// in Settings takes effect on the next flash without re-init.
    private var holdDuration: Duration {
        let seconds = preferences?.overlayHoldDuration ?? 2.5
        return .milliseconds(Int(seconds * 1000))
    }

    func attach(appState: AppState, preferences: Preferences) {
        self.appState = appState
        self.preferences = preferences
        // Remember the user's pinned preference but don't materialise the
        // panel yet. The SwiftUI overlay needs a focused connection to
        // render anything but a tiny placeholder, which trips an AppKit
        // constraint-loop on first-frame layout. The first show()/flash()
        // call after a connection is established creates the panel lazily.
        isPinned = preferences.overlayVisible
        observePlacementChanges()
        observeFocusChanges()

        // Resolution change / monitor unplug: re-anchor any live panels so
        // "Bottom Centre" stays on the new visibleFrame instead of off
        // somewhere on the previous screen layout.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let panel = self.panel { self.applyPlacement(to: panel) }
                if let preview = self.previewPanel { self.applyPlacement(to: preview) }
            }
        }
    }

    /// Re-apply placement when the focused keyboard changes. Switching from
    /// a Micro Pad to a Q1 Pro grows the panel's content but doesn't
    /// reposition it, so without this the wider panel ends up off-centre,
    /// anchored at the smaller panel's origin.
    private func observeFocusChanges() {
        guard let appState else { return }
        withObservationTracking {
            _ = appState.focusedKeyboardPath
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                // SwiftUI lays out the new focused connection's keymap on the
                // next runloop tick. Wait one tick before reading fittingSize
                // so applyPlacement sees the new size, not the old one.
                try? await Task.sleep(for: .milliseconds(20))
                if let panel = self.panel { self.applyPlacement(to: panel) }
                self.observeFocusChanges()  // re-register
            }
        }
    }

    /// Re-apply geometry/opacity when the relevant preferences change.
    private func observePlacementChanges() {
        guard let preferences else { return }
        withObservationTracking {
            _ = preferences.overlayPlacement
            _ = preferences.overlayScale
            _ = preferences.overlayOpacity
            _ = preferences.labelFontSize
            _ = preferences.labelFontName
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let panel = self.panel {
                    self.applyPlacement(to: panel)
                    if self.isPinned {
                        panel.alphaValue = self.preferences?.overlayOpacity ?? 1.0
                    }
                }
                if let preview = self.previewPanel {
                    // Preview tracks every overlay-shaping pref so the user sees
                    // their changes in real time. SwiftUI inside it will rebuild
                    // automatically; we just need to re-position the panel.
                    self.applyPlacement(to: preview)
                }
                self.observePlacementChanges()  // re-register
            }
        }
    }

    private var maxAlpha: CGFloat {
        CGFloat(preferences?.overlayOpacity ?? 1.0)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Manual show, pins the overlay. It will stay visible until `hide()` or
    /// the user closes the window. The panel is held at alpha 0 until
    /// SwiftUI has re-rendered for any focus change (Micro Pad → Q1 Pro,
    /// say). That way the user never sees the panel flash in at the
    /// previous keyboard's position before the new keymap fills it.
    func show() {
        isPinned = true
        cancelFadeOut()
        ensurePanel(initialAlpha: 0)
        guard let panel else { return }
        panel.alphaValue = 0
        applyPlacement(to: panel)
        panel.orderFrontRegardless()
        preferences?.overlayVisible = true

        // After one runloop tick SwiftUI's content reflects the latest
        // focused connection's keymap, the hosting view's fittingSize is
        // accurate, and applyPlacement will land at the correct origin.
        // Then we reveal.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard let self, let panel = self.panel, self.isPinned else { return }
            self.applyPlacement(to: panel)
            panel.alphaValue = self.maxAlpha
        }
    }

    func hide() {
        cancelFadeOut()
        isPinned = false
        preferences?.overlayVisible = false

        guard let panel else { return }
        // Capture the panel reference so a re-show during the fade doesn't
        // get its panel closed in the completion handler.
        let panelToClose = panel
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = effectiveFadeOutDuration
            panel.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.panel === panelToClose else { return }
                panelToClose.close()
                self.panel = nil
            }
        }
    }

    /// Tear the panel down immediately, skipping any fade animation. Called
    /// when the connection the overlay was showing has gone away (USB pull,
    /// auto-disconnect).
    ///
    /// Detaches the SwiftUI hosting view from the panel before hiding.
    /// otherwise the hosting view keeps observing AppState, and the disconnect
    /// state mutation triggers a layout invalidation while AppKit is still
    /// running its constraint pass, looping forever and crashing with
    /// "needing another Update Constraints in Window pass."
    func dismissImmediately() {
        cancelFadeOut()
        if let panel {
            // Swap in an empty contentView so the SwiftUI hosting view (and
            // its environment subscriptions) drop out of the responder chain
            // before any further state mutations happen.
            panel.contentView = NSView(frame: .zero)
            panel.alphaValue = 0
            panel.orderOut(nil)
            panel.delegate = nil
        }
        delegate = nil
        panel = nil
        // Don't touch isPinned or overlayVisible. The user's preference for
        // the panel coming back when they reconnect should survive a transient
        // unplug.
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    // MARK: - Settings preview

    /// Show a transparent overlay panel rendering the demo keyboard at
    /// the user's chosen placement. Safe to call repeatedly. The Settings
    /// window calls this when the user is on the Overlay/Display/Theme tab.
    func showPreview() {
        guard let preferences else { return }
        if let panel = previewPanel {
            applyPlacement(to: panel)
            panel.orderFrontRegardless()
            return
        }

        let host = NSHostingView(
            rootView: DemoOverlayView()
                .environment(preferences)
        )

        let initialSize = host.intrinsicContentSize == .zero
            ? NSSize(width: 720, height: 360)
            : host.intrinsicContentSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Preview sits at .normal (not .floating) so other apps can cover
        // it when they take focus. Users complained the preview hovered
        // over everything while they were trying to read the Settings
        // window or use another app side-by-side. The live overlay still
        // uses .floating below; this only affects the in-Settings preview.
        panel.level = .normal
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true   // preview is non-interactive
        panel.contentView = host
        panel.alphaValue = 1.0
        panel.isReleasedWhenClosed = false
        previewPanel = panel
        applyPlacement(to: panel)
        panel.orderFrontRegardless()
    }

    func hidePreview() {
        guard let panel = previewPanel else { return }
        panel.contentView = NSView(frame: .zero)
        panel.orderOut(nil)
        previewPanel = nil
    }

    /// Flash the overlay in for a layerlens_notify event. No-op while pinned
    /// (the panel is already visible and shouldn't auto-hide). Lazily creates
    /// the panel if it doesn't exist yet, since the user might have launched
    /// with `overlayVisible` set in preferences but we deferred panel
    /// creation until a connection was ready to render.
    ///
    /// `activeLayer` is the layer the firmware just reported. When non-zero
    /// (i.e. the user is holding a momentary layer key) we suppress the
    /// auto-fade so the panel stays visible for the entire hold; the next
    /// notify event with `activeLayer == 0` (release) re-arms the fade.
    func flash(activeLayer: Int = 0) {
        if isPinned {
            ensurePanel(initialAlpha: maxAlpha)
            if let panel { applyPlacement(to: panel) }
            panel?.alphaValue = maxAlpha
            panel?.orderFrontRegardless()
            return
        }

        ensurePanel(initialAlpha: panel == nil ? 0.0 : (panel?.alphaValue ?? 0.0))
        guard let panel else { return }

        // Re-anchor the panel on every flash. The panel's content size
        // can change (theme/font changes, first-launch sizing race), and
        // AppKit doesn't re-run our placement logic on resize; without
        // this the panel ends up off-centre.
        applyPlacement(to: panel)

        cancelFadeOut()

        // Fade in to max alpha (or snap to full if already partway).
        let target = maxAlpha
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = effectiveFadeInDuration
            panel.animator().alphaValue = target
        }
        panel.orderFrontRegardless()

        // Hold open while a non-base layer is active; only re-arm the fade
        // when we're back on layer 0.
        guard activeLayer == 0 else { return }

        let hold = holdDuration
        fadeOutTask = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run { self.fadeOut() }
        }
    }

    // MARK: - Internals

    private func ensurePanel(initialAlpha: CGFloat) {
        if panel != nil { return }
        guard let appState, let preferences else { return }

        let host = NSHostingView(
            rootView: OverlayView()
                .environment(appState)
                .environment(preferences)
        )

        let initialSize = host.intrinsicContentSize == .zero
            ? NSSize(width: 320, height: 200)
            : host.intrinsicContentSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // HUD-style transparent overlay: no chrome, no opaque background, drag
        // the panel by clicking anywhere on it. The shadow stays so keys read
        // even on a busy wallpaper.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.contentView = host
        panel.alphaValue = initialAlpha
        // Force the SwiftUI hosting view to lay out *now* so its fittingSize
        // reflects the real keyboard width before applyPlacement reads it.
        // Without this the very first show() can fall back to the 320×200
        // initialSize and centre the panel on a too-narrow box.
        host.layoutSubtreeIfNeeded()
        // Don't release on close; we control the lifetime via our `panel`
        // property; AppKit deallocating it mid-update can leave the constraint
        // engine pointing at a dead view, which crashes during the next
        // runloop's display cycle.
        panel.isReleasedWhenClosed = false

        let delegate = OverlayWindowDelegate(
            onClose: { [weak self] in
                self?.isPinned = false
                self?.preferences?.overlayVisible = false
                self?.panel = nil
            },
            onMove: { [weak self] origin in
                // User dragged the overlay → switch to custom placement and
                // remember exactly where it landed. Ignore moves that came
                // from our own applyPlacement() so presets actually stick.
                guard let self, !self.isApplyingPlacement,
                      let prefs = self.preferences else { return }
                prefs.overlayCustomOrigin = origin
                if prefs.overlayPlacement != .custom {
                    prefs.overlayPlacement = .custom
                }
            }
        )
        panel.delegate = delegate
        self.delegate = delegate

        self.panel = panel
        applyPlacement(to: panel)
    }

    /// Position the given panel according to `preferences.overlayPlacement`.
    /// Sized to the SwiftUI content's intrinsic size before placement.
    private func applyPlacement(to panel: NSPanel) {
        guard let preferences else { return }

        isApplyingPlacement = true
        defer { isApplyingPlacement = false }

        // Size to content first so placement can use the right dimensions.
        if let host = panel.contentView as? NSHostingView<OverlayView> {
            let fitting = host.fittingSize
            if fitting.width > 0 && fitting.height > 0 {
                var frame = panel.frame
                frame.size = fitting
                panel.setFrame(frame, display: false)
            }
        } else if let demoHost = panel.contentView as? NSHostingView<DemoOverlayView> {
            let fitting = demoHost.fittingSize
            if fitting.width > 0 && fitting.height > 0 {
                var frame = panel.frame
                frame.size = fitting
                panel.setFrame(frame, display: false)
            }
        }

        // For preset placements, always anchor to the main display. `panel.screen`
        // is nil before the first `orderFront`, and on resolution changes it
        // can return a stale screen object whose `visibleFrame` is wrong.
        // For `.custom` we honour wherever the user dragged the panel to.
        let screen: NSScreen? = preferences.overlayPlacement == .custom
            ? (panel.screen ?? NSScreen.main)
            : NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let margin: CGFloat = 24

        let origin: NSPoint
        switch preferences.overlayPlacement {
        case .bottomCentre:
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + margin
            )
        case .topCentre:
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - margin
            )
        case .centre:
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
        case .bottomLeft:
            origin = NSPoint(x: visible.minX + margin, y: visible.minY + margin)
        case .bottomRight:
            origin = NSPoint(
                x: visible.maxX - size.width - margin,
                y: visible.minY + margin
            )
        case .topLeft:
            origin = NSPoint(
                x: visible.minX + margin,
                y: visible.maxY - size.height - margin
            )
        case .topRight:
            origin = NSPoint(
                x: visible.maxX - size.width - margin,
                y: visible.maxY - size.height - margin
            )
        case .custom:
            let saved = preferences.overlayCustomOrigin
            // First-launch fallback if the saved point is (0,0) or off-screen.
            if saved == .zero || !visible.contains(NSPoint(x: saved.x, y: saved.y)) {
                origin = NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.minY + margin
                )
            } else {
                origin = NSPoint(x: saved.x, y: saved.y)
            }
        }

        panel.setFrameOrigin(origin)
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = effectiveFadeOutDuration
            panel.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            // Animation completion fires on the main run loop but the closure
            // is typed as @Sendable; hop back onto the actor to touch state.
            Task { @MainActor [weak self] in
                guard let self, !self.isPinned else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func cancelFadeOut() {
        fadeOutTask?.cancel()
        fadeOutTask = nil
    }

    // Strong reference to keep delegate alive as long as the panel.
    private var delegate: OverlayWindowDelegate?
}

@MainActor
private final class OverlayWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: @MainActor () -> Void
    private let onMove: @MainActor (CGPoint) -> Void

    init(
        onClose: @escaping @MainActor () -> Void,
        onMove:  @escaping @MainActor (CGPoint) -> Void
    ) {
        self.onClose = onClose
        self.onMove = onMove
    }

    // NSWindow delegate methods are dispatched on the main thread; assert the
    // isolation synchronously so the callback runs before AppKit returns control
    // to the caller of setFrameOrigin (otherwise our isApplyingPlacement flag
    // would already be reset by the time the handler fires).
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { self.onClose() }
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        // AppKit fires NSWindowDelegate callbacks synchronously on the main
        // thread; the handler must also run synchronously so it observes
        // `isApplyingPlacement == true` while applyPlacement is still in
        // setFrameOrigin (otherwise our own programmatic moves get
        // misinterpreted as user drags and flip placement to .custom).
        //
        // `MainActor.assumeIsolated` runs synchronously on the current
        // thread; the unchecked Sendable wrapper lets the closure capture
        // the non-Sendable NSWindow reference without tripping strict-
        // concurrency, which is safe given AppKit's documented main-thread
        // dispatch contract.
        let object = UncheckedSendable(notification.object)
        MainActor.assumeIsolated {
            guard let window = object.value as? NSWindow else { return }
            self.onMove(window.frame.origin)
        }
    }
}
