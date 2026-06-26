import AppKit

final class OnboardingWindowController: NSWindowController {
    var snapshotProvider: (() -> DiagnosticSnapshot)?
    var onInstalledHooks: (() -> Void)?

    private let status = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Set Up AI Companion"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        refresh()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupUI() {
        let title = NSTextField(labelWithString: "Connect Claude Code")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: """
        AI Companion listens on 127.0.0.1 and sees Claude Code through local hooks. \
        The installer backs up your existing settings and only appends missing hook entries.
        """)
        body.textColor = .secondaryLabelColor

        status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        let install = NSButton(title: "Install/Repair Hooks", target: self, action: #selector(installHooks))
        let copy = NSButton(title: "Copy Diagnostics", target: self, action: #selector(copyDiagnostics))
        let later = NSButton(title: "Later", target: self, action: #selector(closeLater))
        let buttons = NSStackView(views: [install, copy, later])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, body, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let content = window?.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
        ])
    }

    func refresh() {
        status.stringValue = hooksInstalled()
            ? "Hooks: installed · Port: \(serverPort)"
            : "Hooks: missing · Port: \(serverPort)"
    }

    @objc private func installHooks() {
        let result = runHooksInstaller()
        refresh()
        onInstalledHooks?()
        showAlert(result.ok ? "Hooks installed" : "Hook install failed",
                  result.output.nilIfEmpty ?? "No output.")
        if result.ok {
            AppSettings.onboardingDismissed = true
        }
    }

    @objc private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshotProvider?().text ?? "", forType: .string)
    }

    @objc private func closeLater() {
        AppSettings.onboardingDismissed = true
        close()
    }

    private func showAlert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
