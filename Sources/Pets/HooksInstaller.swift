import AppKit

private let requiredHookEvents = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PostToolBatch",
    "PostToolUseFailure", "PermissionRequest", "PermissionDenied",
    "Notification", "Stop", "SessionEnd",
]
private let matcherRequiredEvents = Set([
    "PreToolUse", "PostToolUse", "PostToolUseFailure",
    "PermissionRequest", "PermissionDenied",
])

func claudeSettingsURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
}

private func petsHookCommand(port: UInt16) -> String {
    "/usr/bin/curl --silent --max-time 0.5 --connect-timeout 0.2 --header 'Content-Type: application/json' --data-binary @- 'http://127.0.0.1:\(port)/event' >/dev/null 2>&1 || true"
}

func hooksInstalled(port: UInt16 = serverPort) -> Bool {
    let command = petsHookCommand(port: port)
    guard let data = try? Data(contentsOf: claudeSettingsURL()),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hooks = root["hooks"] as? [String: Any]
    else { return false }

    for event in requiredHookEvents {
        guard let groups = hooks[event] as? [[String: Any]] else { return false }
        var hasCommand = false
        for group in groups {
            if matcherRequiredEvents.contains(event), group["matcher"] == nil { continue }
            guard let items = group["hooks"] as? [[String: Any]] else { continue }
            if items.contains(where: { $0["type"] as? String == "command" && $0["command"] as? String == command }) {
                hasCommand = true
                break
            }
        }
        if !hasCommand { return false }
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

// First-run nicety for the .app distribution: offer to install the Claude Code
// hooks if they're missing. Runs the bundled install-hooks.sh (only present in
// the app bundle; from-source users have `make install-hooks`).
func maybeOfferHooksInstall() {
    if hooksInstalled() {
        return
    }
    guard hooksInstallerScript() != nil else { return }

    let alert = NSAlert()
    alert.messageText = "Install Claude Code hooks?"
    alert.informativeText = """
    The pet sees Claude Code activity through local hooks. \
    Your existing hook settings are backed up first and never replaced.
    """
    alert.addButton(withTitle: "Install Hooks")
    alert.addButton(withTitle: "Later")
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    let result = runHooksInstaller()

    let done = NSAlert()
    if result.ok {
        done.messageText = "Hooks installed"
        done.informativeText = "Claude Code sessions will reach the pet from their next turn."
    } else {
        done.messageText = "Hook install failed"
        done.informativeText = result.output.nilIfEmpty ?? "Run install-hooks.sh from the repo to see the error."
    }
    done.runModal()
}

private func hooksInstallerScript() -> String? {
    if let bundled = Bundle.main.path(forResource: "install-hooks", ofType: "sh") {
        return bundled
    }
    let local = FileManager.default.currentDirectoryPath + "/scripts/install-hooks.sh"
    return FileManager.default.isExecutableFile(atPath: local) ? local : nil
}
