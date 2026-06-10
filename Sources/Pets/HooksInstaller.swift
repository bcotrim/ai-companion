import AppKit

// First-run nicety for the .app distribution: offer to install the Claude Code
// hooks if they're missing. Runs the bundled install-hooks.sh (only present in
// the app bundle; from-source users have `make install-hooks`).
func maybeOfferHooksInstall() {
    let settings = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    if let data = try? Data(contentsOf: settings),
       String(decoding: data, as: UTF8.self).contains("127.0.0.1:\(serverPort)/event") {
        return
    }
    guard let script = Bundle.main.path(forResource: "install-hooks", ofType: "sh") else { return }

    let alert = NSAlert()
    alert.messageText = "Install Claude Code hooks?"
    alert.informativeText = """
    The pet sees Claude Code activity through hooks in ~/.claude/settings.json. \
    Your settings are backed up first, and existing entries are never replaced.
    """
    alert.addButton(withTitle: "Install Hooks")
    alert.addButton(withTitle: "Later")
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script]
    let launched = (try? process.run()) != nil
    if launched { process.waitUntilExit() }

    let done = NSAlert()
    if launched, process.terminationStatus == 0 {
        done.messageText = "Hooks installed"
        done.informativeText = "Claude Code sessions will reach the pet from their next turn."
    } else {
        done.messageText = "Hook install failed"
        done.informativeText = "Run install-hooks.sh from the repo to see the error."
    }
    done.runModal()
}
