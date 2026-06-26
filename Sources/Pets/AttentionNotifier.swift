import Foundation
import UserNotifications

final class AttentionNotifier {
    static let shared = AttentionNotifier()

    private var requestedAuthorization = false
    private var lastKey: String?

    func note(state: DisplayState, detail: String?) {
        guard AppSettings.attentionMode == .loud else { return }

        let title: String
        switch state {
        case .waiting:
            title = "AI Companion needs you"
        case .failed:
            title = "AI Companion saw a failure"
        case .celebrating:
            title = "Claude finished"
        default:
            return
        }

        let key = "\(state):\(detail ?? "")"
        guard key != lastKey else { return }
        lastKey = key

        requestAuthorizationIfNeeded {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = detail ?? ""
            content.sound = state == .waiting ? .default : nil
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func requestAuthorizationIfNeeded(_ completion: @escaping () -> Void = {}) {
        guard !requestedAuthorization else {
            completion()
            return
        }
        requestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            if allowed {
                completion()
            }
        }
    }
}
