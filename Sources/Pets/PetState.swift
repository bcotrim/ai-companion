import Foundation

struct HookEvent: Decodable {
    let session_id: String?
    let hook_event_name: String?
    let notification_type: String?
    let permission_mode: String?
    let tool_name: String?
    let message: String?
    let prompt: String?
    let title: String?
    let session_title: String?
    let conversation_title: String?
    let thread_title: String?
    let cwd: String?
    let transcript_path: String?

    var toolName: String? { tool_name?.nilIfEmpty }
    var detail: String? { toolName ?? message?.nilIfEmpty ?? notification_type?.nilIfEmpty }
    var sessionTitle: String? {
        for value in [title, session_title, conversation_title, thread_title, prompt] {
            if let title = value?.sessionTitle { return title }
        }
        if let title = transcript_path.flatMap(transcriptTitle) { return title }
        if let title = cwd.flatMap(workingFolderTitle) { return title }
        return nil
    }
}

struct EventSummary {
    let name: String
    let sessionID: String
    let detail: String?
    let date: Date
}

struct SessionSummary {
    let id: String
    let state: String
    let title: String?
    let plan: Bool
    let lastSeen: Date
    let lastTool: String?
    let note: String?
}

// Main-thread-only by construction: HTTP callbacks and timers all land on the main run loop.
final class StateModel {
    private enum SessionState { case idle, working, waiting }
    private struct Session {
        var state: SessionState
        var lastSeen: Date
        var title: String?
        var plan: Bool
        var lastTool: String?
        var note: String?
    }

    private var sessions: [String: Session] = [:]
    private var celebrateUntil: Date = .distantPast
    private var celebrateTimer: Timer?
    private var failedUntil: Date = .distantPast
    private var failedTimer: Timer?
    private var stalenessTimer: Timer?
    private(set) var display: DisplayState = .asleep
    private(set) var lastEvent: EventSummary?
    var onChange: ((DisplayState) -> Void)?

    // Codex-style ambient decay: a state that stops receiving events winds down
    // instead of sticking forever (covers missed Stop events and dead sessions).
    private static let workingDecay: TimeInterval = 3 * 60    // working → idle
    private static let idleDecay: TimeInterval = 10 * 60      // idle → evicted (asleep)
    private static let waitingDecay: TimeInterval = 30 * 60   // waiting → evicted

    func handle(_ event: HookEvent) {
        guard let name = event.hook_event_name, let id = event.session_id else { return }
        let now = Date()
        lastEvent = EventSummary(name: name, sessionID: id, detail: event.detail, date: now)

        func set(_ state: SessionState) {
            var session = sessions[id] ?? Session(state: state, lastSeen: now, title: nil, plan: false,
                                                  lastTool: nil, note: nil)
            session.state = state
            session.lastSeen = now
            if let title = event.sessionTitle {
                session.title = title
            } else if session.title?.isInternalClaudeTitle == true {
                session.title = nil
            }
            if let mode = event.permission_mode { session.plan = (mode == "plan") }
            if let tool = event.toolName { session.lastTool = tool }
            if let note = event.message?.nilIfEmpty ?? event.notification_type?.nilIfEmpty {
                session.note = note
            }
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
            if let tool = event.toolName {
                sessions[id]?.note = "\(tool) failed"
            }
            failedUntil = now.addingTimeInterval(3)
            failedTimer?.invalidate()
            failedTimer = Timer.scheduledTimer(withTimeInterval: 3.1, repeats: false) { [weak self] _ in
                self?.recompute()
            }
        case "PermissionRequest":
            // Fires the instant a permission prompt appears — no notification lag.
            set(.waiting)
            sessions[id]?.note = event.message?.nilIfEmpty ?? "Permission needed"
        case "PermissionDenied":
            set(.working)
            sessions[id]?.note = "Permission denied"
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
            sessions[id]?.note = "Done"
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
        recompute(notifyAlways: true)
    }

    private func recompute(notifyAlways: Bool = false) {
        let active = sessions.values
        let workers = active.filter { $0.state == .working }
        let new: DisplayState
        if Date() < failedUntil { new = .failed }
        else if !workers.isEmpty { new = workers.allSatisfy(\.plan) ? .reviewing : .working }
        else if active.contains(where: { $0.state == .waiting }) { new = .waiting }
        else if Date() < celebrateUntil { new = .celebrating }
        else if !sessions.isEmpty { new = .idle }
        else { new = .asleep }
        if new != display || notifyAlways {
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
        var sessionItems: [String: Any] = [:]
        for (id, s) in sessions {
            var item: [String: Any] = [
                "state": stateName(s.state),
                "plan": s.plan,
                "idleSeconds": Int(-s.lastSeen.timeIntervalSinceNow),
            ]
            if let title = s.title { item["title"] = title }
            if let tool = s.lastTool { item["lastTool"] = tool }
            if let note = s.note { item["note"] = note }
            sessionItems[id] = item
        }
        var root: [String: Any] = [
            "display": "\(display)",
            "sessions": sessionItems,
        ]
        if let lastEvent {
            var event: [String: Any] = [
                "name": lastEvent.name,
                "sessionID": lastEvent.sessionID,
                "secondsAgo": Int(-lastEvent.date.timeIntervalSinceNow),
            ]
            if let detail = lastEvent.detail { event["detail"] = detail }
            root["lastEvent"] = event
        }
        let data = (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    var sessionSummaries: [SessionSummary] {
        sessions.map { id, s in
            SessionSummary(id: id, state: stateName(s.state), title: s.title, plan: s.plan,
                           lastSeen: s.lastSeen, lastTool: s.lastTool, note: s.note)
        }
        .sorted { $0.lastSeen > $1.lastSeen }
    }

    var displayDetail: String? {
        switch display {
        case .waiting:
            return sessions.values.first { $0.state == .waiting }
                .flatMap { $0.note ?? $0.lastTool.map { "Waiting on \($0)" } }
        case .failed:
            return lastEvent?.detail.map { "\($0) failed" } ?? "Tool failed"
        case .celebrating:
            return "Done"
        case .working:
            return sessions.values.first { $0.state == .working }?.lastTool.map { "Using \($0)" }
        case .reviewing:
            return "Planning"
        default:
            return nil
        }
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

    private func stateName(_ state: SessionState) -> String {
        switch state {
        case .idle: return "idle"
        case .working: return "working"
        case .waiting: return "waiting"
        }
    }
}

private extension String {
    var sessionTitle: String? {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty, !text.isInternalClaudeTitle else { return nil }
        return text.count > 48 ? String(text.prefix(45)) + "..." : text
    }

    var isInternalClaudeTitle: Bool {
        let lower = lowercased()
        if lower.hasPrefix("<command-message>") { return true }
        if lower.hasPrefix("<system-reminder>") { return true }
        if lower.hasPrefix("<local-command-") { return true }
        if lower.hasPrefix("### /") { return true }
        if lower.hasPrefix("/") && lower.split(separator: " ").first?.contains("-") == true { return true }
        if lower.hasPrefix("<") && lower.contains("</") && lower.contains(">") && count < 160 {
            return true
        }
        return false
    }
}

private func workingFolderTitle(_ path: String) -> String? {
    let name = URL(fileURLWithPath: path).lastPathComponent.nilIfEmpty
    guard let name, !name.looksGeneratedSessionName else { return nil }
    return name
}

private func transcriptTitle(_ path: String) -> String? {
    guard let path = path.nilIfEmpty,
          let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 512 * 1024),
          let text = String(data: data, encoding: .utf8)
    else { return nil }

    for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(200) {
        guard let data = String(line).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let title = firstUserText(in: object)?.sessionTitle
        else { continue }
        return title
    }
    return nil
}

private func firstUserText(in object: Any) -> String? {
    guard let dict = object as? [String: Any] else { return nil }
    if let message = dict["message"] as? [String: Any],
       message["role"] as? String == "user" {
        return textContent(message["content"])
    }
    if dict["role"] as? String == "user" {
        return textContent(dict["content"])
    }
    if dict["type"] as? String == "user" {
        return textContent(dict["content"] ?? (dict["message"] as? [String: Any])?["content"])
    }
    return nil
}

private func textContent(_ value: Any?) -> String? {
    if let string = value as? String { return string.nilIfEmpty }
    if let dict = value as? [String: Any] {
        return (dict["text"] as? String)?.nilIfEmpty
    }
    if let items = value as? [Any] {
        let parts = items.compactMap { item -> String? in
            if let string = item as? String { return string.nilIfEmpty }
            guard let dict = item as? [String: Any] else { return nil }
            if let type = dict["type"] as? String, type != "text" { return nil }
            return (dict["text"] as? String)?.nilIfEmpty
        }
        return parts.joined(separator: " ").nilIfEmpty
    }
    return nil
}

private extension String {
    var looksGeneratedSessionName: Bool {
        let parts = split(separator: "-")
        guard parts.count >= 3,
              parts.dropLast().allSatisfy({ $0.allSatisfy(\.isLetter) }),
              parts.last?.allSatisfy({ $0.isNumber || ("a"..."f").contains(String($0).lowercased()) }) == true
        else { return false }
        return parts.last!.count >= 6
    }
}
