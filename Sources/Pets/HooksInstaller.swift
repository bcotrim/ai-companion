import AppKit

private let requiredHookEvents = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PostToolUseFailure", "PermissionRequest", "PermissionDenied",
    "PostToolBatch", "Notification", "SubagentStart", "SubagentStop",
    "TaskCreated", "TaskCompleted", "Stop", "StopFailure",
    "PreCompact", "PostCompact", "Elicitation", "ElicitationResult",
    "SessionEnd",
]
private let matcherRequiredEvents = Set([
    "PreToolUse", "PostToolUse", "PostToolUseFailure",
    "PermissionRequest", "PermissionDenied",
])

func claudeSettingsURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
}

func hooksInstalled(port: UInt16 = serverPort) -> Bool {
    let url = "http://127.0.0.1:\(port)/event"
    guard let data = try? Data(contentsOf: claudeSettingsURL()),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hooks = root["hooks"] as? [String: Any]
    else { return false }

    for event in requiredHookEvents {
        guard let groups = hooks[event] as? [[String: Any]] else { return false }
        var hasURL = false
        for group in groups {
            if matcherRequiredEvents.contains(event), group["matcher"] == nil { continue }
            guard let items = group["hooks"] as? [[String: Any]] else { continue }
            if items.contains(where: { $0["url"] as? String == url }) {
                hasURL = true
                break
            }
        }
        if !hasURL { return false }
    }
    return true
}

@discardableResult
func runHooksInstaller(port: UInt16 = serverPort, remove: Bool = false) -> (ok: Bool, output: String) {
    guard let script = hooksInstallerScript() else {
        return (false, "install-hooks.sh was not found.")
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = remove ? [script, "--remove"] : [script]
    var environment = ProcessInfo.processInfo.environment
    environment["PETS_PORT"] = String(port)
    process.environment = environment

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return (false, error.localizedDescription)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(decoding: data, as: UTF8.self)
    return (process.terminationStatus == 0, output)
}

func maybeShowOnboarding(snapshotProvider: @escaping () -> DiagnosticSnapshot,
                         onInstalledHooks: @escaping () -> Void) -> OnboardingWindowController? {
    guard !hooksInstalled(), !AppSettings.onboardingDismissed, hooksInstallerScript() != nil else {
        return nil
    }
    let window = OnboardingWindowController()
    window.snapshotProvider = snapshotProvider
    window.onInstalledHooks = onInstalledHooks
    window.show()
    return window
}

private func hooksInstallerScript() -> String? {
    if let bundled = Bundle.main.path(forResource: "install-hooks", ofType: "sh") {
        return bundled
    }
    let local = FileManager.default.currentDirectoryPath + "/scripts/install-hooks.sh"
    return FileManager.default.isExecutableFile(atPath: local) ? local : nil
}
