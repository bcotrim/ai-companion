import AppKit
import ServiceManagement

final class PreferencesWindowController: NSWindowController {
    var onSettingsChanged: (() -> Void)?

    private let sizeSlider = NSSlider(value: Double(AppSettings.petSize),
                                      minValue: Double(AppSettings.minPetSize),
                                      maxValue: Double(AppSettings.maxPetSize),
                                      target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "")
    private let showText = NSButton(checkboxWithTitle: "Show status text", target: nil, action: nil)
    private let showBubbles = NSButton(checkboxWithTitle: "Show attention bubbles", target: nil, action: nil)
    private let clickAction = NSPopUpButton()
    private let portField = NSTextField(string: String(AppSettings.savedPort))
    private let portNote = NSTextField(labelWithString: "")
    private let hooksStatus = NSTextField(labelWithString: "")
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "AI Companion Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
        refresh()
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
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.numberOfTickMarks = 6
        sizeSlider.allowsTickMarkValuesOnly = false

        for button in [showText, showBubbles, launchAtLogin] {
            button.target = self
        }
        showText.action = #selector(toggleShowText)
        showBubbles.action = #selector(toggleShowBubbles)
        launchAtLogin.action = #selector(toggleLaunchAtLogin)

        clickAction.addItems(withTitles: ClickAction.allCases.map(\.title))
        clickAction.target = self
        clickAction.action = #selector(clickActionChanged)

        portField.alignment = .right
        portField.target = self
        portField.action = #selector(savePort)
        portField.maximumNumberOfLines = 1

        portNote.textColor = .secondaryLabelColor
        portNote.font = .systemFont(ofSize: 11)
        hooksStatus.textColor = .secondaryLabelColor
        hooksStatus.font = .systemFont(ofSize: 11)

        let savePort = NSButton(title: "Save Port", target: self, action: #selector(savePort))
        let installHooks = NSButton(title: "Install Hooks", target: self, action: #selector(installHooks))

        let sizeRow = labeledRow("Size", NSStackView(views: [sizeSlider, sizeLabel]))
        let clickRow = labeledRow("Click", clickAction)
        let portControls = NSStackView(views: [portField, savePort])
        portControls.orientation = .horizontal
        portControls.spacing = 8
        let portRow = labeledRow("Port", portControls)
        let hooksRow = labeledRow("Hooks", NSStackView(views: [hooksStatus, installHooks]))

        let stack = NSStackView(views: [
            sizeRow,
            showText,
            showBubbles,
            clickRow,
            portRow,
            portNote,
            hooksRow,
            launchAtLogin,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        window?.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 24),
            sizeSlider.widthAnchor.constraint(equalToConstant: 220),
            sizeLabel.widthAnchor.constraint(equalToConstant: 48),
            portField.widthAnchor.constraint(equalToConstant: 80),
        ])
    }

    private func refresh() {
        sizeSlider.doubleValue = Double(AppSettings.petSize)
        sizeLabel.stringValue = "\(Int(AppSettings.petSize)) px"
        showText.state = AppSettings.showStatus ? .on : .off
        showBubbles.state = AppSettings.showBubbles ? .on : .off
        clickAction.selectItem(withTitle: AppSettings.clickAction.title)
        portField.stringValue = String(AppSettings.savedPort)
        portNote.stringValue = AppSettings.savedPort == serverPort
            ? "The app is listening on this port."
            : "Restart the app to listen on this port."
        hooksStatus.stringValue = hooksInstalled(port: AppSettings.savedPort)
            ? "Installed for \(AppSettings.savedPort)"
            : "Missing for \(AppSettings.savedPort)"

        launchAtLogin.isEnabled = Bundle.main.bundleURL.pathExtension == "app"
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func labeledRow(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    @objc private func sizeChanged() {
        AppSettings.petSize = CGFloat(sizeSlider.doubleValue)
        sizeLabel.stringValue = "\(Int(AppSettings.petSize)) px"
        onSettingsChanged?()
    }

    @objc private func toggleShowText() {
        AppSettings.showStatus = showText.state == .on
        onSettingsChanged?()
    }

    @objc private func toggleShowBubbles() {
        AppSettings.showBubbles = showBubbles.state == .on
        onSettingsChanged?()
    }

    @objc private func clickActionChanged() {
        guard let title = clickAction.selectedItem?.title,
              let action = ClickAction.allCases.first(where: { $0.title == title })
        else { return }
        AppSettings.clickAction = action
        onSettingsChanged?()
    }

    @objc private func savePort() {
        guard let value = UInt16(portField.stringValue), value > 0 else {
            alert("Invalid port", "Use a port between 1 and 65535.")
            refresh()
            return
        }
        AppSettings.savedPort = value
        refresh()
        onSettingsChanged?()
    }

    @objc private func installHooks() {
        savePort()
        let result = runHooksInstaller(port: AppSettings.savedPort)
        refresh()
        alert(result.ok ? "Hooks installed" : "Hook install failed",
              result.output.nilIfEmpty ?? "No output.")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            alert("Launch at login failed", error.localizedDescription)
        }
        refresh()
    }

    private func alert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
