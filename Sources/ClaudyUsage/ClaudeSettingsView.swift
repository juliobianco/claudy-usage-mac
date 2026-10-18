import SwiftUI
import AppKit
import ClaudyCore

/// The "Claude Code" tab: a picked set of ~/.claude/settings.json keys that are easy to miss.
/// toggle: yes/no with its default when the key is absent; choice: chips ("" removes the key, and a value in the file
/// that is not among the options gets a chip of its own); days: steps; attribution: both byline keys at once.
struct ClaudeSettingsView: View {
    private struct Item { var key: String; var kind: String; var opts: [String] = []; var def: Bool = false; var defText = ""; var head: String? = nil }

    private static let items: [Item] = [
        Item(key: "", kind: "head", head: "cc.hModel"),
        Item(key: "model", kind: "choice", opts: ["", "opusplan", "opus", "sonnet", "haiku", "fable"]),
        Item(key: "fastMode", kind: "toggle", def: false),
        Item(key: "language", kind: "choice", opts: ["", "english", "portuguese", "spanish", "french"]),
        Item(key: "permissions.defaultMode", kind: "choice", opts: ["default", "acceptEdits", "plan", "auto"], defText: "default"),
        Item(key: "", kind: "head", head: "cc.hWork"),
        Item(key: "autoCompactEnabled", kind: "toggle", def: true),
        Item(key: "autoMemoryEnabled", kind: "toggle", def: true),
        Item(key: "fileCheckpointingEnabled", kind: "toggle", def: true),
        Item(key: "awaySummaryEnabled", kind: "toggle", def: true),
        Item(key: "respondToBashCommands", kind: "toggle", def: true),
        Item(key: "attribution", kind: "attribution"),
        Item(key: "cleanupPeriodDays", kind: "days"),
        Item(key: "autoUpdatesChannel", kind: "choice", opts: ["latest", "stable"], defText: "latest"),
        Item(key: "", kind: "head", head: "cc.hTerminal"),
        Item(key: "theme", kind: "choice", opts: ["auto", "dark", "light", "dark-daltonized", "light-daltonized", "dark-ansi", "light-ansi"], defText: "dark"),
        Item(key: "tui", kind: "choice", opts: ["", "fullscreen", "default"]),
        Item(key: "outputStyle", kind: "choice", opts: ["", "Proactive", "Explanatory", "Learning"]),
        Item(key: "viewMode", kind: "choice", opts: ["", "default", "verbose", "focus"]),
        Item(key: "editorMode", kind: "choice", opts: ["normal", "vim"], defText: "normal"),
        Item(key: "spinnerTipsEnabled", kind: "toggle", def: true),
        Item(key: "showTurnDuration", kind: "toggle", def: true),
        Item(key: "showThinkingSummaries", kind: "toggle", def: false),
        Item(key: "terminalProgressBarEnabled", kind: "toggle", def: true),
        Item(key: "prefersReducedMotion", kind: "toggle", def: false),
        Item(key: "", kind: "head", head: "cc.hRemote"),
        Item(key: "remoteControlAtStartup", kind: "toggle", def: false),
        Item(key: "agentPushNotifEnabled", kind: "toggle", def: false),
        Item(key: "inputNeededNotifEnabled", kind: "toggle", def: false),
    ]
    private static let daySteps = [7, 14, 30, 60, 90, 180, 365]

    private let file = ClaudeSettingsFile()
    @State private var loaded = ClaudeSettingsFile().load()
    @State private var presets = DevFlags.demo ? [ClaudePreset?](repeating: nil, count: ClaudePresets.slots) : ClaudePresets.load()
    /// How the managed keys were when Settings first opened in this run: what "Revert" goes back to.
    nonisolated(unsafe) private static var initial: [String: String?]?

    /// Every key this page writes (the byline is two).
    private static let managedKeys: [String] = items.filter { !$0.key.isEmpty }.flatMap {
        $0.kind == "attribution" ? ["attribution.commit", "attribution.pr"] : [$0.key]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t("cc.note", shortPath)).font(.system(size: 10.5)).foregroundStyle(T.dim).fixedSize(horizontal: false, vertical: true)
            if let e = loaded.error {
                Text(L.t("cc.bad", e)).font(.system(size: 11)).foregroundStyle(T.crit).fixedSize(horizontal: false, vertical: true)
            } else {
                presetsBox
                ForEach(Array(Self.items.enumerated()), id: \.offset) { _, it in view(for: it) }
            }
            ActionButton(text: L.t("cc.edit"), systemImage: "doc.text") { NSWorkspace.shared.open(file.url) }
            Text(L.t("set.moreHint")).font(.system(size: 10)).foregroundStyle(T.faint)
        }
        .onAppear {
            loaded = file.load()
            if Self.initial == nil, loaded.error == nil { Self.initial = file.capture(Self.managedKeys) }
        }
    }

    // MARK: presets and revert
    private var current: [String: String?] { file.capture(Self.managedKeys) }

    private var presetsBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: L.t("cc.presets"))
            Text(L.t("cc.presets.hint")).font(.system(size: 10.5)).foregroundStyle(T.dim).fixedSize(horizontal: false, vertical: true)
            let changed = Self.initial.map { $0 != current } ?? false
            HStack(spacing: 8) {
                ActionButton(text: L.t("cc.revert"), systemImage: "arrow.uturn.backward") {
                    if let i = Self.initial { file.restore(i); loaded = file.load() }
                }
                .opacity(changed ? 1 : 0.4).disabled(!changed)
                if !changed { Text(L.t("cc.reverted")).font(.system(size: 10.5)).foregroundStyle(T.faint) }
            }
            ForEach(0..<ClaudePresets.slots, id: \.self) { i in slot(i) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(T.card))
    }

    private func slot(_ i: Int) -> some View {
        let p = presets[i]
        let active = p.map { $0.values == current } ?? false
        return HStack(spacing: 8) {
            if let p, DevFlags.offscreen {
                Text(p.name).font(.system(size: 12.5)).foregroundStyle(T.textHi).frame(maxWidth: .infinity, alignment: .leading)
            } else if p != nil {
                TextField(L.t("cc.slot", i + 1), text: Binding(get: { presets[i]?.name ?? "" }, set: { presets[i]?.name = $0; ClaudePresets.save(presets) }))
                    .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(T.textHi)
                    .padding(.horizontal, 8).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 6).fill(T.code))
            } else {
                Text("\(L.t("cc.slot", i + 1)) · \(L.t("cc.empty"))").font(.system(size: 12.5)).foregroundStyle(T.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if active { Text(L.t("cc.active")).font(.system(size: 10.5)).foregroundStyle(T.ok) }
            ActionButton(text: L.t("cc.save")) {
                let name = presets[i]?.name ?? L.t("cc.slot", i + 1)
                presets[i] = ClaudePreset(name: name, values: current); ClaudePresets.save(presets)
            }
            if let p {
                ActionButton(text: L.t("cc.apply")) { file.restore(p.values); loaded = file.load() }
                    .opacity(active ? 0.4 : 1).disabled(active)
                Button { presets[i] = nil; ClaudePresets.save(presets) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(T.dim).frame(width: 22, height: 26)
                }
                .buttonStyle(.plain).help(L.t("cc.delete"))
            }
        }
    }

    private var shortPath: String { file.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    private func write(_ changes: [(String, JSONValue?)]) {
        file.apply(changes)
        loaded = file.load()
    }

    @ViewBuilder private func view(for it: Item) -> some View {
        switch it.kind {
        case "head":
            SectionTitle(text: L.t(it.head!)).padding(.top, 6)
        case "toggle":
            let cur = loaded.root.get(it.key)?.bool ?? it.def
            SwitchRow(label: L.t("cc." + it.key), hint: tip(it.key), isOn: Binding(get: { cur }, set: { write([(it.key, .bool($0))]) }))
        case "attribution":
            // On unless the byline was emptied: both keys are written together.
            let c = loaded.root.get("attribution.commit")?.string
            let on = c == nil || c != ""
            SwitchRow(label: L.t("cc.attribution"), hint: tip("attribution"), isOn: Binding(get: { on }, set: {
                write($0 ? [("attribution.commit", nil), ("attribution.pr", nil)] : [("attribution.commit", .string("")), ("attribution.pr", .string(""))])
            }))
        case "days":
            let n = loaded.root.get(it.key)?.int ?? 30
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(L.t("cc." + it.key)).font(.system(size: 12.5)).foregroundStyle(T.text2)
                    Spacer()
                    stepButton("minus") { if let v = Self.daySteps.last(where: { $0 < n }) { write([(it.key, .number(String(v)))]) } }
                    Text(L.t("cc.days", n)).font(.system(size: 12.5, weight: .medium)).monospacedDigit().foregroundStyle(T.textHi).frame(width: 74)
                    stepButton("plus") { if let v = Self.daySteps.first(where: { $0 > n }) { write([(it.key, .number(String(v)))]) } }
                }
                if let t = tip(it.key) { Text(t).font(.system(size: 10.5)).foregroundStyle(T.dim) }
            }
        default:
            choice(it)
        }
    }

    private func choice(_ it: Item) -> some View {
        let cur = loaded.root.get(it.key)?.string
        let shown = cur ?? it.defText
        var opts = it.opts
        if let c = cur, !opts.contains(c) { opts.append(c) }         // a value Claude Code understands that we do not list
        return VStack(alignment: .leading, spacing: 6) {
            Text(L.t("cc." + it.key)).font(.system(size: 12.5)).foregroundStyle(T.text2)
            if let t = tip(it.key) { Text(t).font(.system(size: 10.5)).foregroundStyle(T.dim).fixedSize(horizontal: false, vertical: true) }
            FlowRow(spacing: 6) {
                ForEach(opts, id: \.self) { v in
                    Chip(text: optionLabel(it.key, v), selected: v == shown) { write([(it.key, v.isEmpty ? nil : .string(v))]) }
                }
            }
        }
    }

    private func optionLabel(_ key: String, _ v: String) -> String {
        if v.isEmpty { return L.t("cc.unset") }
        let k = "cc.\(key).\(v)"
        let t = L.t(k)
        return t == k ? v : t
    }

    private func tip(_ key: String) -> String? {
        let k = "cc.\(key).tip", t = L.t(k)
        return t == k ? nil : t
    }

    private func stepButton(_ symbol: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(T.muted)
                .frame(width: 24, height: 22).background(RoundedRectangle(cornerRadius: 6).fill(T.card))
        }
        .buttonStyle(.plain)
    }
}
