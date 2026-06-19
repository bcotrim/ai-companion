import AppKit
import Foundation

enum ClickAction: String, CaseIterable {
    case openClaude
    case none

    var title: String {
        switch self {
        case .openClaude: return "Open Claude Desktop"
        case .none: return "Do Nothing"
        }
    }
}

enum AttentionMode: String, CaseIterable {
    case quiet
    case normal
    case loud

    var title: String {
        switch self {
        case .quiet: return "Quiet"
        case .normal: return "Normal"
        case .loud: return "Loud"
        }
    }
}

enum AppSettings {
    static let defaultPort: UInt16 = 7387
    static let defaultPetID = "codex:wapuu"
    static let defaultPetSize: CGFloat = 136
    static let minPetSize: CGFloat = 96
    static let maxPetSize: CGFloat = 220

    private static let defaults = UserDefaults.standard
    private static let displayPetSizesKey = "displayPetSizes"
    private static let displayPetPositionsKey = "displayPetPositions"
    private static let lastPetDisplayKey = "lastPetDisplay"
    private static let onboardingDismissedKey = "onboardingDismissed"

    static var listenerPort: UInt16 {
        if let env = ProcessInfo.processInfo.environment["PETS_PORT"].flatMap(UInt16.init) {
            return env
        }
        let saved = defaults.integer(forKey: "serverPort")
        return saved > 0 ? UInt16(clamping: saved) : defaultPort
    }

    static var savedPort: UInt16 {
        get {
            let saved = defaults.integer(forKey: "serverPort")
            return saved > 0 ? UInt16(clamping: saved) : defaultPort
        }
        set { defaults.set(Int(newValue), forKey: "serverPort") }
    }

    static var petID: String {
        get { defaults.string(forKey: "petID") ?? defaultPetID }
        set { defaults.set(newValue, forKey: "petID") }
    }

    static var showStatus: Bool {
        get { defaults.object(forKey: "showStatus") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showStatus") }
    }

    static var showBubbles: Bool {
        get { defaults.object(forKey: "showBubbles") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showBubbles") }
    }

    static var attentionMode: AttentionMode {
        get { AttentionMode(rawValue: defaults.string(forKey: "attentionMode") ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "attentionMode") }
    }

    static var petSize: CGFloat {
        get {
            let saved = defaults.double(forKey: "petSize")
            guard saved > 0 else { return defaultPetSize }
            return min(max(CGFloat(saved), minPetSize), maxPetSize)
        }
        set { defaults.set(Double(min(max(newValue, minPetSize), maxPetSize)), forKey: "petSize") }
    }

    static var lastPetDisplayID: String? {
        get { defaults.string(forKey: lastPetDisplayKey) }
        set { defaults.set(newValue, forKey: lastPetDisplayKey) }
    }

    static func displayID(for screen: NSScreen?) -> String? {
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return String(number.uint32Value)
    }

    static func screen(matching id: String?) -> NSScreen? {
        guard let id else { return nil }
        return NSScreen.screens.first { displayID(for: $0) == id }
    }

    static func petSize(for screen: NSScreen?) -> CGFloat {
        guard let id = displayID(for: screen),
              let saved = displayPetSizes[id],
              saved > 0
        else { return petSize }
        return clampedPetSize(CGFloat(saved))
    }

    static func setPetSize(_ size: CGFloat, for screen: NSScreen?) {
        let value = clampedPetSize(size)
        petSize = value
        guard let id = displayID(for: screen) else { return }
        var sizes = displayPetSizes
        sizes[id] = Double(value)
        displayPetSizes = sizes
    }

    static func petPosition(for screen: NSScreen?) -> CGPoint? {
        guard let id = displayID(for: screen),
              let item = displayPetPositions[id],
              let x = item["x"], let y = item["y"]
        else { return nil }
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    static func setPetPosition(_ position: CGPoint, for screen: NSScreen?) {
        guard let id = displayID(for: screen) else { return }
        var positions = displayPetPositions
        positions[id] = [
            "x": Double(min(max(position.x, 0), 1)),
            "y": Double(min(max(position.y, 0), 1)),
        ]
        displayPetPositions = positions
        lastPetDisplayID = id
    }

    static var clickAction: ClickAction {
        get { ClickAction(rawValue: defaults.string(forKey: "clickAction") ?? "") ?? .openClaude }
        set { defaults.set(newValue.rawValue, forKey: "clickAction") }
    }

    static var onboardingDismissed: Bool {
        get { defaults.object(forKey: onboardingDismissedKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: onboardingDismissedKey) }
    }

    private static var displayPetSizes: [String: Double] {
        get {
            let raw = defaults.dictionary(forKey: displayPetSizesKey) ?? [:]
            return raw.reduce(into: [:]) { result, item in
                if let value = item.value as? NSNumber {
                    result[item.key] = value.doubleValue
                }
            }
        }
        set { defaults.set(newValue, forKey: displayPetSizesKey) }
    }

    private static var displayPetPositions: [String: [String: Double]] {
        get {
            let raw = defaults.dictionary(forKey: displayPetPositionsKey) ?? [:]
            return raw.reduce(into: [:]) { result, item in
                guard let values = item.value as? [String: Any] else { return }
                var parsed: [String: Double] = [:]
                for (key, value) in values {
                    if let number = value as? NSNumber {
                        parsed[key] = number.doubleValue
                    }
                }
                if parsed["x"] != nil, parsed["y"] != nil {
                    result[item.key] = parsed
                }
            }
        }
        set { defaults.set(newValue, forKey: displayPetPositionsKey) }
    }

    private static func clampedPetSize(_ value: CGFloat) -> CGFloat {
        min(max(value, minPetSize), maxPetSize)
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
