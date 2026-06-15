import CoreGraphics
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

enum AppSettings {
    static let defaultPort: UInt16 = 7387
    static let defaultPetID = "codex:wapuu"
    static let defaultPetSize: CGFloat = 136
    static let minPetSize: CGFloat = 96
    static let maxPetSize: CGFloat = 220

    private static let defaults = UserDefaults.standard

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

    static var petSize: CGFloat {
        get {
            let saved = defaults.double(forKey: "petSize")
            guard saved > 0 else { return defaultPetSize }
            return min(max(CGFloat(saved), minPetSize), maxPetSize)
        }
        set { defaults.set(Double(min(max(newValue, minPetSize), maxPetSize)), forKey: "petSize") }
    }

    static var clickAction: ClickAction {
        get { ClickAction(rawValue: defaults.string(forKey: "clickAction") ?? "") ?? .openClaude }
        set { defaults.set(newValue.rawValue, forKey: "clickAction") }
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
