import SwiftUI
import AppKit
import ClaudyCore

// A small window that floats over everything and can be put anywhere: the dropdown's compact card (sky, Clawd,
// the 5h number, the week) that folds into a bubble with the two rings, and back. It shows what the menu bar
// shows. On macOS 26 and later it is drawn in Liquid Glass and the card and the bubble morph into each other;
// before that, or when switched off in the settings, it uses the theme's own background.

@MainActor @Observable
final class FloatingState {
    var expanded = Prefs.shared.floatExpanded
    var appeared = false                // false: a bubble that has not inflated yet / has shrunk back into the bar
    var cardHeight: CGFloat = 330
}

@MainActor
final class FloatingWidget {
    static let shared = FloatingWidget()
    static let cardWidth: CGFloat = 300
    static let bubbleBox: CGFloat = 92         // the bubble plus room for its glass edge and shadow

    let state = FloatingState()
    private var panel: NSPanel?
    private var shrinkWork: DispatchWorkItem?
    private var programmatic = false           // our own moves must not be saved as the user's choice
    private var anchor = CGPoint.zero          // where the bubble comes from and goes back to

    var isOpen: Bool { panel?.isVisible == true && state.appeared }
    private var prefs: Prefs { Prefs.shared }

    // MARK: show / hide

    /// `anchor`: the frame of the window it comes from (the dropdown); nil: the top right of the main screen.
    func show(model: AppModel, from source: NSRect? = nil, animated: Bool = true) {
        if panel == nil { makePanel(model) }
        guard let panel, !isOpen else { return }
        anchor = source.map { CGPoint(x: $0.midX, y: $0.maxY - 24) } ?? defaultAnchor()
        let final = frame(expanded: state.expanded)
        applyLevel(); panel.alphaValue = CGFloat(prefs.floatOpacity) / 100
        prefs.floatOpen = true

        if animated {
            state.appeared = false
            programmatic = true
            panel.setFrame(final.offsetBy(dx: anchor.x - final.midX, dy: anchor.y - final.midY), display: false)
            panel.orderFrontRegardless()
            move(panel, to: final, duration: 0.6, timing: CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.12))
            DispatchQueue.main.async { withAnimation(.spring(duration: 0.65, bounce: 0.35)) { self.state.appeared = true } }
        } else {
            programmatic = true
            panel.setFrame(final, display: true)
            panel.orderFrontRegardless()
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { state.appeared = true }
            programmatic = false
        }
    }

    /// Shrinks back into the bar and goes.
    func hide(animated: Bool = true) {
        prefs.floatOpen = false
        guard let panel, panel.isVisible else { return }
        guard animated else { panel.orderOut(nil); state.appeared = false; return }
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) { state.appeared = false }
        let f = panel.frame
        programmatic = true
        move(panel, to: f.offsetBy(dx: anchor.x - f.midX, dy: anchor.y - f.midY), duration: 0.45,
             timing: CAMediaTimingFunction(controlPoints: 0.5, 0, 0.8, 0.4)) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.programmatic = false
        }
    }

    func toggle(model: AppModel, from source: NSRect? = nil) {
        if isOpen { hide() } else { show(model: model, from: source) }
    }

    // MARK: card <-> bubble

    func toggleExpanded() {
        withAnimation(.spring(duration: 0.55, bounce: 0.28)) { state.expanded.toggle() }
        prefs.floatExpanded = state.expanded
        resizeForState()
    }

    /// The window is made big enough before the card opens, and small only after the bubble has formed.
    private func resizeForState() {
        guard let panel else { return }
        shrinkWork?.cancel()
        let target = frame(expanded: state.expanded, keepingTopLeftOf: panel.frame)
        if state.expanded { programmatic = true; panel.setFrame(target, display: true); programmatic = false; return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel, !self.state.expanded else { return }
            self.programmatic = true; panel.setFrame(self.frame(expanded: false, keepingTopLeftOf: panel.frame), display: true); self.programmatic = false
        }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func heightChanged() {
        guard state.expanded, let panel, state.appeared || panel.isVisible else { return }
        let target = frame(expanded: true, keepingTopLeftOf: panel.frame)
        guard abs(target.height - panel.frame.height) > 0.5 else { return }
        programmatic = true; panel.setFrame(target, display: true); programmatic = false
    }

    func applyLevel() {
        panel?.level = prefs.floatOnTop ? .floating : .normal
        panel?.alphaValue = CGFloat(prefs.floatOpacity) / 100
    }

    // MARK: the window

    private func makePanel(_ model: AppModel) {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.cardWidth, height: 330),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false                       // the glass and the plain card draw their own
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.animationBehavior = .none
        let host = NSHostingView(rootView: FloatingRoot(model: model, controller: self))
        host.sizingOptions = []
        p.contentView = host
        panel = p
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.programmatic, let f = self.panel?.frame else { return }
                UserDefaults.standard.set([f.minX, f.maxY], forKey: "floatTopLeft")      // top-left corner, y up
            }
        }
    }

    private func move(_ p: NSPanel, to f: NSRect, duration: TimeInterval, timing: CAMediaTimingFunction,
                      done: (@MainActor @Sendable () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            p.animator().setFrame(f, display: true)
        } completionHandler: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.programmatic = false; done?() } }
        }
    }

    private func size(expanded: Bool) -> NSSize {
        expanded ? NSSize(width: Self.cardWidth, height: state.cardHeight) : NSSize(width: Self.bubbleBox, height: Self.bubbleBox)
    }

    /// Where it sits: the saved top-left corner if there is one on a screen, else the top right corner.
    private func frame(expanded: Bool, keepingTopLeftOf current: NSRect? = nil) -> NSRect {
        let s = size(expanded: expanded)
        var tl: CGPoint
        if let c = current { tl = CGPoint(x: c.minX, y: c.maxY) }
        else if let saved = UserDefaults.standard.array(forKey: "floatTopLeft") as? [Double], saved.count == 2 {
            tl = CGPoint(x: saved[0], y: saved[1])
        } else {
            let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            tl = CGPoint(x: v.maxX - s.width - 16, y: v.maxY - 12)
        }
        // At least a corner of it must stay on some screen.
        let probe = CGRect(x: tl.x + 10, y: tl.y - 10, width: 1, height: 1)
        if !NSScreen.screens.contains(where: { $0.frame.contains(probe.origin) }) {
            let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            tl = CGPoint(x: v.maxX - s.width - 16, y: v.maxY - 12)
        }
        return NSRect(x: tl.x, y: tl.y - s.height, width: s.width, height: s.height)
    }

    private func defaultAnchor() -> CGPoint {
        let f = (NSScreen.main ?? NSScreen.screens[0]).frame
        return CGPoint(x: f.maxX - 140, y: f.maxY - 18)
    }
}

// MARK: the content

struct FloatingRoot: View {
    let model: AppModel
    let controller: FloatingWidget
    @Namespace private var ns
    private var state: FloatingState { controller.state }
    private var prefs: Prefs { Prefs.shared }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scaleEffect(state.appeared ? 1 : 0.12)
            .opacity(state.appeared ? 1 : 0)
            .blur(radius: state.appeared ? 0 : 14)
            .environment(\.colorScheme, .dark)
            .onChange(of: prefs.floatOnTop) { controller.applyLevel() }
            .onChange(of: prefs.floatOpacity) { controller.applyLevel() }
            .contextMenu {
                Button(state.expanded ? L.t("float.collapse") : L.t("float.expand")) { controller.toggleExpanded() }
                Toggle(L.t("float.top"), isOn: Binding(get: { prefs.floatOnTop }, set: { prefs.floatOnTop = $0 }))
                Toggle("Liquid Glass", isOn: Binding(get: { prefs.floatGlass }, set: { prefs.floatGlass = $0 }))
                Divider()
                Button(L.t("float.close")) { controller.hide() }
            }
    }

    /// Liquid Glass on macOS 26+ (the card and the bubble morph into each other), the theme's solid look otherwise.
    @ViewBuilder private var content: some View {
        let card = FloatingCard(model: model, controller: controller)
        let bubble = BubbleView(model: model)
            .overlay(DragHandle(onClick: { controller.toggleExpanded() }, tooltip: model.bubbleTip))
        if #available(macOS 26.0, *), prefs.floatGlass {
            // The glass takes the colour of what is behind it (grey over white, and the light text vanishes): a dark base keeps it readable.
            let tint = Glass.regular.tint(T.bg.opacity(0.88))
            GlassEffectContainer(spacing: 24) {
                if state.expanded {
                    card.background(T.bg.opacity(0.8), in: RoundedRectangle(cornerRadius: 26, style: .continuous)).glassEffect(tint, in: RoundedRectangle(cornerRadius: 26, style: .continuous)).glassEffectID("surface", in: ns)
                } else {
                    bubble.background(T.bg.opacity(0.8), in: Circle()).glassEffect(tint.interactive(), in: Circle()).glassEffectID("surface", in: ns).padding(8)
                }
            }
        } else if state.expanded {
            solid(card, RoundedRectangle(cornerRadius: 22, style: .continuous), radius: 14)
        } else {
            solid(bubble, Circle(), radius: 10).padding(8)
        }
    }

    private func solid<V: View, S: Shape>(_ v: V, _ shape: S, radius: CGFloat) -> some View {
        v.background(shape.fill(T.bg))
            .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: radius, y: 3)
            .transition(.scale(scale: 0.3, anchor: .topLeading).combined(with: .opacity))
    }
}

/// Moves the window when it is dragged; a click that does not move it calls `onClick`. As a `.background` it catches
/// the mouse wherever the SwiftUI content above it does not (buttons and the sky keep their own clicks); as an
/// `.overlay` it takes the whole area (the bubble).
struct DragHandle: NSViewRepresentable {
    var onClick: (() -> Void)? = nil
    var tooltip: String? = nil

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ v: DragView, context: Context) { v.onClick = onClick; v.toolTip = tooltip }

    final class DragView: NSView {
        var onClick: (() -> Void)?
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let w = window else { return }
            let before = w.frame.origin
            w.performDrag(with: event)               // returns when the button is released
            if w.frame.origin == before { onClick?() }
        }
    }
}

/// The dropdown's compact card: what the menu bar shows, plus the sky and Clawd.
struct FloatingCard: View {
    let model: AppModel
    let controller: FloatingWidget
    private var prefs: Prefs { Prefs.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if model.alertWaiting || model.alertCelebrating { AlertBadge(model: model) }
                else { Text(L.t("app.title")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(T.muted) }
                Spacer()
                if let p = model.usage?.session?.percent { HeartsView(halves: Format.heartHalves(sessionPercent: p)).padding(.trailing, 12) }
                button("arrow.down.right.and.arrow.up.left", L.t("float.collapse")) { controller.toggleExpanded() }
                button("xmark", L.t("float.close")) { controller.hide() }.padding(.leading, 9)
            }
            .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 4) {
                HeroView(scene: model.scene, model: model)
                    .help(prefs.showSky ? model.skyTip : "")
                    .onAppear { model.scene.start() }
                    .onDisappear { model.scene.stop() }
                ProgressBar(percent: model.usage?.session?.percent, height: 7, color: model.usage?.session.map { T.level($0.percent) } ?? T.ok)
            }
            Text(model.resetText).font(.system(size: 12)).foregroundStyle(T.text2).padding(.top, 8)
            LimitRow(model: model, title: L.t("week"), line: model.usage?.week, color: T.accent).padding(.top, 9)
            if prefs.showFable, let f = model.usage?.fable { LimitRow(model: model, title: L.t("fableWeek"), line: f, color: T.purple).padding(.top, 7) }
            HStack {
                Text(L.t("sessions")).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.dim)
                Spacer()
                Text(model.sessionsText).font(.system(size: 11)).foregroundStyle(T.muted).lineLimit(1)
            }
            .padding(.top, 11)
            HStack(spacing: 6) {
                Circle().fill(model.statusColor).frame(width: 7, height: 7)
                Text(model.statusText).font(.system(size: 11.5)).foregroundStyle(T.muted).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.top, 9)
        }
        .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 13)
        .frame(width: FloatingWidget.cardWidth)
        .background(DragHandle())
        .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
        .onPreferenceChange(HeightKey.self) { h in controller.state.cardHeight = h; controller.heightChanged() }
    }

    private func button(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.muted) }
            .buttonStyle(.plain).help(help)
    }
}

/// The folded widget: two rings (5h outside, the week inside) around the 5h number.
struct BubbleView: View {
    let model: AppModel

    var body: some View {
        let s = model.usage?.session?.percent, w = model.usage?.week?.percent
        ZStack {
            ring(1, 5, 0, T.track)
            ring(CGFloat(s ?? 0) / 100, 5, 0, s.map { T.level($0) } ?? T.dim)
            ring(1, 2.5, 9, T.track)
            ring(CGFloat(w ?? 0) / 100, 2.5, 9, T.accent)
            VStack(spacing: -2) {
                Text(s.map { "\($0)" } ?? "--").font(.system(size: 21, weight: .light)).foregroundStyle(s.map { T.level($0) } ?? T.muted).monospacedDigit()
                Text("5h").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(T.dim)
            }
        }
        .frame(width: 76, height: 76)
        .overlay {                              // a session waits: the rim pulses yellow; a limit reset: confetti
            if model.alertWaiting {
                Circle().stroke(T.warn.opacity(model.alertTick % 2 == 0 ? 0.95 : 0.25), lineWidth: 3)
                    .overlay(alignment: .topTrailing) {
                        Text("?").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(Color.black.opacity(0.85))
                            .frame(width: 15, height: 15).background(Circle().fill(T.warn)).offset(x: 2, y: -2)
                    }
            }
            if model.alertCelebrating { Confetti(tick: model.alertTick).clipShape(Circle()) }
        }
        .allowsHitTesting(false)
    }

    private func ring(_ to: CGFloat, _ width: CGFloat, _ inset: CGFloat, _ color: Color) -> some View {
        Circle().inset(by: inset + width / 2 + 3).trim(from: 0, to: max(to, 0.001))
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round)).rotationEffect(.degrees(-90))
    }
}
