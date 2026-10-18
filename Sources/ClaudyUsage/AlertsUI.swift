import SwiftUI
import UserNotifications
import ClaudyCore

// What the app does to get your attention: a session that waits for you, a limit that starts over.
// The state lives in AppModel (alertWaiting, alertCelebrating, alertTick); these are the pieces that draw it.

enum Notifier {
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }       // not when run unbundled (dev tools)

    static func authorize() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        guard available else { return }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

/// In place of the card's title while something needs you: a pill that pulses.
struct AlertBadge: View {
    let model: AppModel

    var body: some View {
        let on = model.alertTick % 2 == 0
        if model.alertCelebrating {
            pill("✦ " + L.t(model.alertEarly ? "alert.resetEarly" : "alert.reset"), T.ok, on)
        } else if model.alertWaiting {
            pill("? " + L.t("waitingForYou"), T.warn, on)
        }
    }

    private func pill(_ text: String, _ c: Color, _ bright: Bool) -> some View {
        Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(c.opacity(bright ? 0.28 : 0.10)))
            .overlay(Capsule().stroke(c.opacity(bright ? 0.9 : 0.35), lineWidth: 1))
    }
}

/// A few coloured specks falling across `size`; `tick` moves them. Cheap enough to redraw twice a second.
struct Confetti: View {
    let tick: Int
    private static let colors: [UInt32] = [0xF87171, 0xFBBF24, 0x4ADE80, 0x60A5FA, 0xA78BFA, 0xD77757]

    var body: some View {
        Canvas { ctx, size in
            for i in 0..<14 {
                let x = (CGFloat((i * 53 + 17) % 100) / 100) * size.width + CGFloat((tick + i) % 3) * 1.5 - 1.5
                let fall = CGFloat((tick * 3 + i * 11) % 24) / 24
                let y = fall * (size.height + 6) - 3
                let s: CGFloat = (tick + i) % 2 == 0 ? 2.6 : 1.6
                ctx.fill(Path(CGRect(x: x, y: y, width: s, height: 2.6)),
                         with: .color(Color(hex: Self.colors[i % Self.colors.count], opacity: 0.95)))
            }
        }
        .allowsHitTesting(false)
    }
}
