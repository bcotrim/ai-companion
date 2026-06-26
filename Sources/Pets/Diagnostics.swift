import AppKit
import Foundation

struct DiagnosticSnapshot {
    let sessions: [SessionSummary]
    let lastEvent: EventSummary?
    let recentEvents: [EventSummary]

    var text: String {
        var lines: [String] = [
            "AI Companion Diagnostics",
            "Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "source")",
            "Bundle: \(Bundle.main.bundleURL.path)",
            "Port: \(serverPort)",
            "Hooks: \(hooksInstalled() ? "installed" : "missing")",
            "Attention: \(AppSettings.attentionMode.title)",
            "Status text: \(AppSettings.showStatus ? "on" : "off")",
            "Bubbles: \(AppSettings.showBubbles ? "on" : "off")",
            "",
            "Sessions:",
        ]

        if sessions.isEmpty {
            lines.append("- none")
        } else {
            for session in sessions {
                var parts = [
                    "\(session.title ?? shortID(session.id))",
                    session.state,
                    "idle \(Int(-session.lastSeen.timeIntervalSinceNow))s",
                ]
                if session.plan { parts.append("plan") }
                if let tool = session.lastTool { parts.append(tool) }
                if let note = session.note { parts.append(note) }
                lines.append("- \(parts.joined(separator: " | "))")
            }
        }

        lines.append("")
        lines.append("Last Event:")
        if let lastEvent {
            lines.append("- \(eventLine(lastEvent))")
        } else {
            lines.append("- none")
        }

        lines.append("")
        lines.append("Recent Events:")
        if recentEvents.isEmpty {
            lines.append("- none")
        } else {
            for event in recentEvents.prefix(20) {
                lines.append("- \(eventLine(event))")
            }
        }

        return lines.joined(separator: "\n")
    }
}

final class DashboardWindowController: NSWindowController {
    var snapshotProvider: (() -> DiagnosticSnapshot)?

    private let textView = NSTextView()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "AI Companion Dashboard"
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
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        let copy = NSButton(title: "Copy Diagnostics", target: self, action: #selector(copyDiagnostics))
        let buttons = NSStackView(views: [refresh, copy])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        guard let content = window?.contentView else { return }
        content.addSubview(scroll)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    @objc private func refresh() {
        textView.string = snapshotProvider?().text ?? "No diagnostics available."
    }

    @objc private func copyDiagnostics() {
        let text = snapshotProvider?().text ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private func shortID(_ id: String) -> String {
    id.count > 10 ? String(id.suffix(10)) : id
}

private func eventLine(_ event: EventSummary) -> String {
    var parts = [
        event.name,
        shortID(event.sessionID),
        "\(Int(-event.date.timeIntervalSinceNow))s ago",
    ]
    if let detail = event.detail { parts.append(detail) }
    return parts.joined(separator: " | ")
}
