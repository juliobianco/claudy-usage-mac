import SwiftUI
import AppKit
import Carbon.HIToolbox

// One global shortcut that shows / hides the floating widget. Carbon's RegisterEventHotKey needs no permission
// (unlike an event tap) and works while another app is in front. Off until the user records one in Settings.

@MainActor
enum HotKey {
    static weak var model: AppModel?
    private static var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    /// (Re)registers the saved shortcut; call again whenever it changes.
    static func apply() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        let p = Prefs.shared
        guard p.hotkeyCode >= 0, !DevFlags.offscreen else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { if let m = HotKey.model { FloatingWidget.shared.toggle(model: m) } } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        // A shortcut another app already owns fails here and simply does nothing.
        RegisterEventHotKey(UInt32(p.hotkeyCode), UInt32(p.hotkeyMods), EventHotKeyID(signature: 0x434C4459, id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    static func carbonMods(_ f: NSEvent.ModifierFlags) -> Int {
        (f.contains(.command) ? cmdKey : 0) | (f.contains(.option) ? optionKey : 0)
            | (f.contains(.control) ? controlKey : 0) | (f.contains(.shift) ? shiftKey : 0)
    }

    /// "⌃⌥⌘C": the way the menus write it.
    static func label(_ e: NSEvent) -> String {
        let f = e.modifierFlags
        let key = e.keyCode == UInt16(kVK_Space) ? "Space" : (e.charactersIgnoringModifiers ?? "?").uppercased()
        return (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "") + (f.contains(.shift) ? "⇧" : "")
            + (f.contains(.command) ? "⌘" : "") + key
    }
}

/// A button that records the next key combination. Esc cancels, Delete clears; it needs ⌘, ⌥ or ⌃ so typing is not hijacked.
struct HotKeyRecorder: View {
    @State private var prefs = Prefs.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(L.t("hotkey.label")).font(.system(size: 12.5)).foregroundStyle(T.text2)
            Spacer()
            Button(action: toggle) {
                Text(recording ? L.t("hotkey.press") : prefs.hotkeyCode < 0 ? L.t("hotkey.none") : prefs.hotkeyLabel)
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(recording ? T.accent : T.textHi)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(T.off))
            }.buttonStyle(.plain)
        }
        .onDisappear { stop() }
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            switch Int(e.keyCode) {
            case kVK_Escape: break
            case kVK_Delete: set(-1, 0, "")
            default:
                let mods = e.modifierFlags.intersection([.command, .option, .control])
                if mods.isEmpty { return nil }   // keep listening
                set(Int(e.keyCode), HotKey.carbonMods(e.modifierFlags), HotKey.label(e))
            }
            stop()
            return nil
        }
    }

    private func set(_ code: Int, _ mods: Int, _ label: String) {
        prefs.hotkeyCode = code; prefs.hotkeyMods = mods; prefs.hotkeyLabel = label
        HotKey.apply()
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
