import AppKit
import UniformTypeIdentifiers

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 190),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }
}

final class PetView: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onDrag: ((Int) -> Void)?      // -1 = moving left, 1 = moving right
    var onDragEnd: (() -> Void)?
    private var dragged = false
    private var downMouse = NSPoint.zero
    private var downOrigin = NSPoint.zero
    private var lastX: CGFloat = 0

    // Route every click (image, labels) to this view so drag/click/menu behave uniformly.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) != nil ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        dragged = false
        downMouse = NSEvent.mouseLocation
        downOrigin = window?.frame.origin ?? .zero
        lastX = downMouse.x
    }

    // Move the window ourselves (no performDrag): it keeps mouseDragged events
    // flowing so the pet can face the direction it is being carried.
    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        if !dragged, hypot(now.x - downMouse.x, now.y - downMouse.y) <= 3 { return }
        dragged = true
        window?.setFrameOrigin(NSPoint(x: downOrigin.x + now.x - downMouse.x,
                                       y: downOrigin.y + now.y - downMouse.y))
        if abs(now.x - lastX) > 1 {
            onDrag?(now.x > lastX ? 1 : -1)
            lastX = now.x
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragged { onDragEnd?() } else { onClick?() }
    }
}

final class PetController: NSObject, NSMenuDelegate {
    private let panel = PetPanel()
    private let petView = PetView()
    private let bubbleLabel = NSTextField(labelWithString: "")
    private let petLabel = NSTextField(labelWithString: "")
    private let petImageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var imageHeightConstraint: NSLayoutConstraint?
    private var imageWidthConstraint: NSLayoutConstraint?
    private var timer: Timer?
    private var frameIndex = 0
    private var spriteReloadTimer: Timer?
    private var sessionDisplay: DisplayState = .asleep
    private var shownState: DisplayState = .asleep
    private var hovering = false
    private var dragDirection = 0
    private var codexRefs: [CodexPetRef]
    private var iconCache: [String: NSImage] = [:]
    private var pet: Pet
    private var displayHeight: CGFloat
    private var preferencesWindow: PreferencesWindowController?
    var sessionProvider: (() -> [SessionSummary])?
    var lastEventProvider: (() -> EventSummary?)?
    var detailProvider: (() -> String?)?

    override init() {
        let refs = scanCodexPets()
        let height = AppSettings.petSize
        codexRefs = refs
        displayHeight = height
        let savedID = AppSettings.petID
        pet = builtinPets.first { $0.id == savedID }
            ?? refs.first { $0.id == savedID }.flatMap { loadCodexPet($0, displayHeight: height) }
            ?? builtinPets[0]
        super.init()
        let names = builtinPets.map(\.id) + codexRefs.map(\.id)
        print("pets available: \(names.joined(separator: ", ")) — active: \(pet.id)")
        setupUI()
        refresh()
    }

    private func setupUI() {
        bubbleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        bubbleLabel.textColor = .labelColor
        bubbleLabel.alignment = .center
        bubbleLabel.lineBreakMode = .byTruncatingTail
        bubbleLabel.maximumNumberOfLines = 1
        bubbleLabel.isHidden = true
        bubbleLabel.wantsLayer = true
        bubbleLabel.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        bubbleLabel.layer?.cornerRadius = 8
        bubbleLabel.layer?.borderWidth = 1
        bubbleLabel.layer?.borderColor = NSColor.separatorColor.cgColor

        petLabel.font = .systemFont(ofSize: displayHeight * 0.62)
        petLabel.alignment = .center
        petImageView.imageScaling = .scaleProportionallyUpOrDown
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        let stack = NSStackView(views: [bubbleLabel, petLabel, petImageView, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView = petView
        petView.addSubview(stack)
        imageHeightConstraint = petImageView.heightAnchor.constraint(equalToConstant: displayHeight)
        imageWidthConstraint = petImageView.widthAnchor.constraint(equalToConstant: displayHeight)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: petView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: petView.centerYAnchor),
            bubbleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
            bubbleLabel.heightAnchor.constraint(equalToConstant: 26),
            imageHeightConstraint!,
            imageWidthConstraint!,
        ])

        let menu = NSMenu()
        menu.delegate = self
        petView.menu = menu
        petView.onClick = { [weak self] in self?.handleClick() }
        petView.onHover = { [weak self] inside in
            self?.hovering = inside
            self?.refresh()
        }
        petView.onDrag = { [weak self] direction in
            guard let self, self.dragDirection != direction else { return }
            self.dragDirection = direction
            self.refresh()
        }
        petView.onDragEnd = { [weak self] in
            self?.dragDirection = 0
            self?.refresh()
        }

        if !panel.setFrameUsingName("PetWindow"), let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - 320, y: v.minY + 24))
        }
        panel.setFrameAutosaveName("PetWindow")
        resizePanel()
        clampPanelToVisibleScreen()
        panel.orderFrontRegardless()
    }

    func apply(state: DisplayState) {
        sessionDisplay = state
        refresh()
    }

    func settingsChanged() {
        let oldSize = displayHeight
        displayHeight = AppSettings.petSize
        petLabel.font = .systemFont(ofSize: displayHeight * 0.62)
        imageHeightConstraint?.constant = displayHeight
        imageWidthConstraint?.constant = displayHeight
        resizePanel()
        if oldSize != displayHeight, pet.isSprite {
            scheduleSpriteReload()
        }
        refresh()
    }

    private func scheduleSpriteReload() {
        spriteReloadTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.reloadSelectedPet()
            self.refresh()
        }
        timer.tolerance = 0.05
        spriteReloadTimer = timer
    }

    private func resizePanel() {
        let width = max(300, displayHeight + 150)
        let height = max(190, displayHeight + 96)
        var frame = panel.frame
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: false)
        clampPanelToVisibleScreen()
    }

    private func clampPanelToVisibleScreen() {
        guard let screen = bestScreen(for: panel.frame) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        var frame = panel.frame
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: false)
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            area(a.visibleFrame.intersection(frame)) < area(b.visibleFrame.intersection(frame))
        }
    }

    private func area(_ rect: NSRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private func refresh() {
        shownState = dragDirection > 0 ? .dragRight
            : dragDirection < 0 ? .dragLeft
            : hovering ? .hover
            : sessionDisplay
        frameIndex = 0
        render()
        timer?.invalidate()
        timer = nil
        guard pet.frames(for: shownState).count > 1 else { return }
        let interval = pet.interval(for: shownState)
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex += 1
            self.render()
        }
        t.tolerance = interval * 0.3
        timer = t
    }

    private func render() {
        let frames = pet.frames(for: shownState)
        switch frames[frameIndex % frames.count] {
        case .text(let string):
            petLabel.stringValue = string
            petLabel.isHidden = false
            petImageView.isHidden = true
        case .image(let image):
            petImageView.image = image
            petImageView.isHidden = false
            petLabel.isHidden = true
        }
        let bubble = AppSettings.showBubbles ? bubbleText : ""
        bubbleLabel.stringValue = bubble
        bubbleLabel.isHidden = bubble.isEmpty

        let text = AppSettings.showStatus ? statusText : ""
        statusLabel.stringValue = text
        statusLabel.isHidden = text.isEmpty
    }

    private var statusText: String {
        switch sessionDisplay {
        case .asleep: return "zzz"
        case .idle, .hover, .dragLeft, .dragRight: return ""
        case .working: return "working…"
        case .reviewing: return "planning…"
        case .waiting: return "needs you!"
        case .celebrating: return "done!"
        case .failed: return "oops!"
        }
    }

    private var bubbleText: String {
        switch sessionDisplay {
        case .waiting, .celebrating, .failed:
            return detailProvider?() ?? statusText
        default:
            return ""
        }
    }

    private func openClaude() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func handleClick() {
        switch AppSettings.clickAction {
        case .openClaude:
            openClaude()
        case .none:
            break
        }
    }

    // MARK: - Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let petMenu = NSMenu()
        for p in builtinPets {
            let item = NSMenuItem(title: "", action: #selector(selectPet(_:)), keyEquivalent: "")
            if case .text(let glyph) = p.frames(for: .idle)[0] {
                item.title = "\(glyph)  \(p.name)"
            } else {
                item.title = p.name
            }
            item.target = self
            item.representedObject = p.id
            item.state = p.id == pet.id ? .on : .off
            petMenu.addItem(item)
        }
        if !codexRefs.isEmpty {
            petMenu.addItem(.separator())
            let header = NSMenuItem(title: "Codex Pets", action: nil, keyEquivalent: "")
            header.isEnabled = false
            petMenu.addItem(header)
            for ref in codexRefs {
                let item = NSMenuItem(title: ref.name, action: #selector(selectPet(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ref.id
                item.state = ref.id == pet.id ? .on : .off
                if iconCache[ref.id] == nil, let icon = codexPetIcon(ref) {
                    iconCache[ref.id] = icon
                }
                item.image = iconCache[ref.id]
                petMenu.addItem(item)
            }
        }
        petMenu.addItem(.separator())
        let install = NSMenuItem(title: "Install Pet…", action: #selector(installPet), keyEquivalent: "")
        install.target = self
        petMenu.addItem(install)

        let reload = NSMenuItem(title: "Reload Pets", action: #selector(reloadPets), keyEquivalent: "")
        reload.target = self
        petMenu.addItem(reload)

        let petItem = NSMenuItem(title: "Pet", action: nil, keyEquivalent: "")
        menu.addItem(petItem)
        menu.setSubmenu(petMenu, for: petItem)

        let statusItem = NSMenuItem(title: "Show Text", action: #selector(toggleStatus), keyEquivalent: "")
        statusItem.target = self
        statusItem.state = AppSettings.showStatus ? .on : .off
        menu.addItem(statusItem)

        let bubblesItem = NSMenuItem(title: "Show Bubbles", action: #selector(toggleBubbles), keyEquivalent: "")
        bubblesItem.target = self
        bubblesItem.state = AppSettings.showBubbles ? .on : .off
        menu.addItem(bubblesItem)

        let prefs = NSMenuItem(title: "Settings…", action: #selector(showPreferences), keyEquivalent: "")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let sessionsItem = NSMenuItem(title: "Sessions", action: nil, keyEquivalent: "")
        let sessionsMenu = NSMenu()
        let sessions = sessionProvider?() ?? []
        if sessions.isEmpty {
            let empty = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sessionsMenu.addItem(empty)
        } else {
            for session in sessions {
                let item = NSMenuItem(title: sessionTitle(session), action: nil, keyEquivalent: "")
                item.isEnabled = false
                sessionsMenu.addItem(item)
            }
        }
        menu.addItem(sessionsItem)
        menu.setSubmenu(sessionsMenu, for: sessionsItem)

        if let event = lastEventProvider?() {
            let title = "Last Event: \(event.name) · \(relative(event.date))"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            if let detail = event.detail {
                let detailItem = NSMenuItem(title: "Detail: \(detail)", action: nil, keyEquivalent: "")
                detailItem.isEnabled = false
                menu.addItem(detailItem)
            }
        } else {
            let item = NSMenuItem(title: "Last Event: none", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        let info = NSMenuItem(title: "Listening on 127.0.0.1:\(serverPort)", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        let hooks = NSMenuItem(title: hooksInstalled() ? "Hooks: installed" : "Hooks: missing", action: nil, keyEquivalent: "")
        hooks.isEnabled = false
        menu.addItem(hooks)

        let installHooks = NSMenuItem(title: "Install/Repair Hooks", action: #selector(installHooks), keyEquivalent: "")
        installHooks.target = self
        menu.addItem(installHooks)

        menu.addItem(.separator())

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let quit = NSMenuItem(title: "Quit AI Companion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func selectPet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let selected = loadPet(id: id)
        guard let selected else { return }
        pet = selected
        AppSettings.petID = id
        refresh()
    }

    @objc private func reloadPets() {
        codexRefs = scanCodexPets()
        iconCache.removeAll()
        reloadSelectedPet()
        refresh()
    }

    @objc private func toggleStatus() {
        AppSettings.showStatus.toggle()
        render()
    }

    @objc private func toggleBubbles() {
        AppSettings.showBubbles.toggle()
        render()
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            let window = PreferencesWindowController()
            window.onSettingsChanged = { [weak self] in self?.settingsChanged() }
            preferencesWindow = window
        }
        preferencesWindow?.show()
    }

    @objc private func installHooks() {
        let result = runHooksInstaller()
        showAlert(result.ok ? "Hooks installed" : "Hook install failed",
                  result.output.nilIfEmpty ?? "No output.")
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.check()
    }

    @objc private func installPet() {
        let panel = NSOpenPanel()
        panel.title = "Install Pet"
        panel.prompt = "Install"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let ref = try installCodexPet(from: url)
            useInstalledPet(ref)
            showAlert("Pet installed", "\(ref.name) is ready.")
        } catch PetInstallError.duplicate(let id) {
            let alert = NSAlert()
            alert.messageText = "Replace existing pet?"
            alert.informativeText = "A pet named \(id) already exists in ~/.claude/pets."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do {
                let ref = try installCodexPet(from: url, replaceExisting: true)
                useInstalledPet(ref)
                showAlert("Pet replaced", "\(ref.name) is ready.")
            } catch {
                showAlert("Pet install failed", error.localizedDescription)
            }
        } catch {
            showAlert("Pet install failed", error.localizedDescription)
        }
    }

    private func loadPet(id: String) -> Pet? {
        builtinPets.first { $0.id == id }
            ?? codexRefs.first { $0.id == id }.flatMap { loadCodexPet($0, displayHeight: displayHeight) }
    }

    private func reloadSelectedPet() {
        pet = loadPet(id: pet.id) ?? builtinPets[0]
    }

    private func useInstalledPet(_ ref: CodexPetRef) {
        codexRefs = scanCodexPets()
        iconCache.removeAll()
        if let selected = loadPet(id: ref.id) {
            pet = selected
            AppSettings.petID = ref.id
        }
        refresh()
    }

    private func sessionTitle(_ session: SessionSummary) -> String {
        let name = session.title ?? shortSessionID(session.id)
        var parts = ["\(name): \(session.state)"]
        if session.title != nil { parts.append(shortSessionID(session.id)) }
        if session.plan { parts.append("plan") }
        if let tool = session.lastTool { parts.append(tool) }
        if let note = session.note, note != session.lastTool { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    private func shortSessionID(_ id: String) -> String {
        id.count > 10 ? String(id.suffix(10)) : id
    }

    private func relative(_ date: Date) -> String {
        let seconds = max(0, Int(-date.timeIntervalSinceNow))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    private func showAlert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
