import AppKit

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
    private let petLabel = NSTextField(labelWithString: "")
    private let petImageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "❗")
    private var timer: Timer?
    private var frameIndex = 0
    private var sessionDisplay: DisplayState = .asleep
    private var shownState: DisplayState = .asleep
    private var hovering = false
    private var dragDirection = 0
    private var codexRefs: [CodexPetRef]
    private var iconCache: [String: NSImage] = [:]
    private var pet: Pet
    private var showStatus: Bool

    override init() {
        codexRefs = scanCodexPets()
        let savedID = UserDefaults.standard.string(forKey: "petID")
        pet = builtinPets.first { $0.id == savedID }
            ?? codexRefs.first { $0.id == savedID }.flatMap(loadCodexPet)
            ?? builtinPets[0]
        showStatus = UserDefaults.standard.object(forKey: "showStatus") as? Bool ?? true
        super.init()
        let names = builtinPets.map(\.id) + codexRefs.map(\.id)
        print("pets available: \(names.joined(separator: ", ")) — active: \(pet.id)")
        setupUI()
        refresh()
    }

    private func setupUI() {
        petLabel.font = .systemFont(ofSize: 84)
        petLabel.alignment = .center
        petImageView.imageScaling = .scaleProportionallyUpOrDown
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center

        let stack = NSStackView(views: [petLabel, petImageView, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.font = .systemFont(ofSize: 28)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView = petView
        petView.addSubview(stack)
        petView.addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: petView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: petView.centerYAnchor),
            petImageView.heightAnchor.constraint(equalToConstant: petDisplayHeight),
            petImageView.widthAnchor.constraint(equalToConstant: petDisplayHeight),
            badgeLabel.centerXAnchor.constraint(equalTo: petImageView.trailingAnchor, constant: -6),
            badgeLabel.centerYAnchor.constraint(equalTo: petImageView.topAnchor, constant: 10),
        ])

        let menu = NSMenu()
        menu.delegate = self
        petView.menu = menu
        petView.onClick = { [weak self] in self?.openClaude() }
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
        panel.orderFrontRegardless()
    }

    func apply(state: DisplayState) {
        sessionDisplay = state
        refresh()
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
        let text = showStatus ? statusText : ""
        statusLabel.stringValue = text
        statusLabel.isHidden = text.isEmpty
        // Sprite pets get an attention badge regardless of the text toggle.
        badgeLabel.isHidden = !(pet.isSprite && sessionDisplay == .waiting)
    }

    private var statusText: String {
        switch sessionDisplay {
        case .asleep: return "zzz"
        case .idle, .hover, .dragLeft, .dragRight: return ""
        case .working: return "working…"
        case .waiting: return "needs you!"
        case .celebrating: return "done!"
        case .failed: return "oops!"
        }
    }

    private func openClaude() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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
        let reload = NSMenuItem(title: "Reload Pets", action: #selector(reloadPets), keyEquivalent: "")
        reload.target = self
        petMenu.addItem(reload)

        let petItem = NSMenuItem(title: "Pet", action: nil, keyEquivalent: "")
        menu.addItem(petItem)
        menu.setSubmenu(petMenu, for: petItem)

        let statusItem = NSMenuItem(title: "Show Text", action: #selector(toggleStatus), keyEquivalent: "")
        statusItem.target = self
        statusItem.state = showStatus ? .on : .off
        menu.addItem(statusItem)

        menu.addItem(.separator())
        let info = NSMenuItem(title: "Listening on 127.0.0.1:\(serverPort)", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        let quit = NSMenuItem(title: "Quit Pets", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func selectPet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let selected = builtinPets.first { $0.id == id }
            ?? codexRefs.first { $0.id == id }.flatMap(loadCodexPet)
        guard let selected else { return }
        pet = selected
        UserDefaults.standard.set(id, forKey: "petID")
        refresh()
    }

    @objc private func reloadPets() {
        codexRefs = scanCodexPets()
        iconCache.removeAll()
        if pet.isSprite {
            pet = codexRefs.first { $0.id == pet.id }.flatMap(loadCodexPet) ?? builtinPets[0]
        }
        refresh()
    }

    @objc private func toggleStatus() {
        showStatus.toggle()
        UserDefaults.standard.set(showStatus, forKey: "showStatus")
        render()
    }
}
