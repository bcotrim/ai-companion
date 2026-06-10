import AppKit

enum DisplayState {
    case asleep, idle, working, waiting, celebrating, hover, dragLeft, dragRight
}

enum PetFrame {
    case text(String)
    case image(NSImage)
}

struct Pet {
    let id: String
    let name: String
    let isSprite: Bool
    let frames: [DisplayState: [PetFrame]]

    func frames(for state: DisplayState) -> [PetFrame] {
        frames[state] ?? frames[.idle] ?? [.text("❓")]
    }

    func interval(for state: DisplayState) -> TimeInterval {
        if state == .idle { return isSprite ? 1.0 : 2.0 }
        return isSprite ? 0.2 : 0.45
    }

    static func standard(_ name: String, _ base: String) -> Pet {
        func t(_ strings: [String]) -> [PetFrame] { strings.map { .text($0) } }
        return Pet(id: name, name: name, isSprite: false, frames: [
            .asleep: t(["\(base)💤"]),
            .idle: t([base]),
            .working: t(["\(base)⌨️", "\(base)💻"]),
            .waiting: t(["\(base)❗", base]),
            .celebrating: t(["\(base)🎉", "\(base)✨"]),
            .hover: t(["\(base)💖", "\(base)💕"]),
            .dragLeft: t(["💨\(base)"]),
            .dragRight: t(["\(base)💨"]),
        ])
    }
}

let builtinPets: [Pet] = [
    .standard("Cat", "🐱"),
]
