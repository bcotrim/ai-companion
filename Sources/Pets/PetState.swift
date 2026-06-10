import Foundation

struct HookEvent: Decodable {
    let session_id: String?
    let hook_event_name: String?
}

// Main-thread-only by construction: HTTP callbacks and timers all land on the main run loop.
final class StateModel {
    private enum SessionState { case idle, working, waiting }

    private var sessions: [String: (state: SessionState, lastSeen: Date)] = [:]
    private var celebrateUntil: Date = .distantPast
    private var celebrateTimer: Timer?
    private var stalenessTimer: Timer?
    private(set) var display: DisplayState = .asleep
    var onChange: ((DisplayState) -> Void)?

    private static let staleAfter: TimeInterval = 30 * 60

    func handle(_ event: HookEvent) {
        guard let name = event.hook_event_name, let id = event.session_id else { return }
        let now = Date()
        switch name {
        case "SessionStart":
            sessions[id] = (.idle, now)
        case "UserPromptSubmit", "PreToolUse", "PostToolUse":
            sessions[id] = (.working, now)
        case "Notification":
            sessions[id] = (.waiting, now)
        case "Stop":
            sessions[id] = (.idle, now)
            celebrateUntil = now.addingTimeInterval(2.5)
            celebrateTimer?.invalidate()
            celebrateTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { [weak self] _ in
                self?.recompute()
            }
        case "SessionEnd":
            sessions[id] = nil
        default:
            sessions[id] = (sessions[id]?.state ?? .idle, now)
        }
        syncStalenessTimer()
        recompute()
    }

    private func recompute() {
        let states = sessions.values.map(\.state)
        let new: DisplayState
        if states.contains(.working) { new = .working }
        else if states.contains(.waiting) { new = .waiting }
        else if Date() < celebrateUntil { new = .celebrating }
        else if !sessions.isEmpty { new = .idle }
        else { new = .asleep }
        if new != display {
            display = new
            onChange?(new)
        }
    }

    private func syncStalenessTimer() {
        if sessions.isEmpty {
            stalenessTimer?.invalidate()
            stalenessTimer = nil
        } else if stalenessTimer == nil {
            let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.evictStale()
            }
            t.tolerance = 10
            stalenessTimer = t
        }
    }

    var debugJSON: String {
        let items = sessions.map { id, s in
            "\"\(id)\": {\"state\": \"\(s.state)\", \"idleSeconds\": \(Int(-s.lastSeen.timeIntervalSinceNow))}"
        }
        return "{\"display\": \"\(display)\", \"sessions\": {\(items.joined(separator: ", "))}}\n"
    }

    private func evictStale() {
        let cutoff = Date().addingTimeInterval(-Self.staleAfter)
        sessions = sessions.filter { $0.value.lastSeen > cutoff }
        syncStalenessTimer()
        recompute()
    }
}
