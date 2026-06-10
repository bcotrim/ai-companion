import Foundation

struct HookEvent: Decodable {
    let session_id: String?
    let hook_event_name: String?
    let notification_type: String?
    let permission_mode: String?
}

// Main-thread-only by construction: HTTP callbacks and timers all land on the main run loop.
final class StateModel {
    private enum SessionState { case idle, working, waiting }
    private struct Session {
        var state: SessionState
        var lastSeen: Date
        var plan: Bool
    }

    private var sessions: [String: Session] = [:]
    private var celebrateUntil: Date = .distantPast
    private var celebrateTimer: Timer?
    private var failedUntil: Date = .distantPast
    private var failedTimer: Timer?
    private var stalenessTimer: Timer?
    private(set) var display: DisplayState = .asleep
    var onChange: ((DisplayState) -> Void)?

    // Codex-style ambient decay: a state that stops receiving events winds down
    // instead of sticking forever (covers missed Stop events and dead sessions).
    private static let workingDecay: TimeInterval = 3 * 60    // working → idle
    private static let idleDecay: TimeInterval = 10 * 60      // idle → evicted (asleep)
    private static let waitingDecay: TimeInterval = 30 * 60   // waiting → evicted

    func handle(_ event: HookEvent) {
        guard let name = event.hook_event_name, let id = event.session_id else { return }
        let now = Date()

        func set(_ state: SessionState) {
            var session = sessions[id] ?? Session(state: state, lastSeen: now, plan: false)
            session.state = state
            session.lastSeen = now
            if let mode = event.permission_mode { session.plan = (mode == "plan") }
            sessions[id] = session
        }

        switch name {
        case "SessionStart":
            set(.idle)
        case "UserPromptSubmit", "PreToolUse", "PostToolUse":
            set(.working)
        case "PostToolUseFailure":
            // Claude keeps going after a failed tool — brief "oops!", still working.
            set(.working)
            failedUntil = now.addingTimeInterval(3)
            failedTimer?.invalidate()
            failedTimer = Timer.scheduledTimer(withTimeInterval: 3.1, repeats: false) { [weak self] _ in
                self?.recompute()
            }
        case "PermissionRequest":
            // Fires the instant a permission prompt appears — no notification lag.
            set(.waiting)
        case "PermissionDenied":
            set(.working)
        case "Notification":
            // "needs you" only when blocked mid-task (permission prompt, question).
            // The post-Stop "waiting for your input" notification arrives while the
            // session is idle — that's just Claude being ready, not needing rescue.
            if sessions[id]?.state == .working || event.notification_type == "permission_prompt" {
                set(.waiting)
            } else {
                set(sessions[id]?.state ?? .idle)
            }
        case "Stop":
            set(.idle)
            celebrateUntil = now.addingTimeInterval(2.5)
            celebrateTimer?.invalidate()
            celebrateTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { [weak self] _ in
                self?.recompute()
            }
        case "SessionEnd":
            sessions[id] = nil
        default:
            set(sessions[id]?.state ?? .idle)
        }
        syncStalenessTimer()
        recompute()
    }

    private func recompute() {
        let active = sessions.values
        let workers = active.filter { $0.state == .working }
        let new: DisplayState
        if Date() < failedUntil { new = .failed }
        else if !workers.isEmpty { new = workers.allSatisfy(\.plan) ? .reviewing : .working }
        else if active.contains(where: { $0.state == .waiting }) { new = .waiting }
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
            let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.decay()
            }
            t.tolerance = 5
            stalenessTimer = t
        }
    }

    var debugJSON: String {
        let items = sessions.map { id, s in
            "\"\(id)\": {\"state\": \"\(s.state)\", \"plan\": \(s.plan), \"idleSeconds\": \(Int(-s.lastSeen.timeIntervalSinceNow))}"
        }
        return "{\"display\": \"\(display)\", \"sessions\": {\(items.joined(separator: ", "))}}\n"
    }

    private func decay() {
        for (id, s) in sessions {
            let quiet = -s.lastSeen.timeIntervalSinceNow
            switch s.state {
            case .working where quiet > Self.workingDecay:
                sessions[id]?.state = .idle
            case .idle where quiet > Self.idleDecay:
                sessions[id] = nil
            case .waiting where quiet > Self.waitingDecay:
                sessions[id] = nil
            default:
                break
            }
        }
        syncStalenessTimer()
        recompute()
    }
}
