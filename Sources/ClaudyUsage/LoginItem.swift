import ServiceManagement
import ClaudyCore

/// Launch at login through the system's login items. Needs the app to run from a normal location (~/Applications).
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { Log.write("launch at login: \(error.localizedDescription)") }
    }

    /// Once per install: turn it on, so the icon is there after a reboot. The user's later choice is never overridden.
    static func enableOnFirstRun() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "loginItemAsked") else { return }
        d.set(true, forKey: "loginItemAsked")
        set(true)
    }
}
