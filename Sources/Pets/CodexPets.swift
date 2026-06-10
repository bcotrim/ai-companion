import AppKit

// Codex CLI pet format (codex-rs/tui/src/pets): a folder with pet.json + a webp
// spritesheet laid out as an 8x9 grid of 192x208 cells, row-major. Rows have
// fixed meanings; pet.json may override the grid and animation frame indices.
// We read these in place so they keep working in Codex untouched.
// Pets are scanned cheaply (JSON only); spritesheets decode lazily on selection.

struct CodexPetRef {
    let id: String
    let name: String
    let dir: URL
}

private struct CodexPetFile: Decodable {
    var id: String?
    var displayName: String?
    var spritesheetPath: String?
    struct FrameSpec: Decodable { var width: Int?; var height: Int?; var columns: Int?; var rows: Int? }
    var frame: FrameSpec?
    struct Anim: Decodable { var frames: [Int] }
    var animations: [String: Anim]?
}

private let defaultAnimations: [String: [Int]] = [
    "idle": Array(0..<6),             // row 0
    "running-right": Array(8..<16),   // row 1
    "running-left": Array(16..<24),   // row 2
    "waving": Array(24..<28),         // row 3
    "jumping": Array(32..<37),        // row 4
    "failed": Array(40..<48),         // row 5
    "waiting": Array(48..<54),        // row 6
    "running": Array(56..<62),        // row 7
]

let petDisplayHeight: CGFloat = 136

let codexPetDirs: [URL] = [
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/pets"),
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/pets"),
]

func scanCodexPets() -> [CodexPetRef] {
    codexPetDirs.flatMap { dir -> [CodexPetRef] in
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return entries.compactMap { petDir in
            guard let file = readPetFile(petDir) else { return nil }
            let id = file.id ?? petDir.lastPathComponent
            return CodexPetRef(id: "codex:\(id)", name: file.displayName ?? id, dir: petDir)
        }
        .sorted { $0.name < $1.name }
    }
}

func loadCodexPet(_ ref: CodexPetRef) -> Pet? {
    guard let sheet = loadSheet(ref.dir) else { return nil }
    var cache: [Int: NSImage] = [:]
    func frames(_ names: [String]) -> [PetFrame]? {
        for name in names {
            guard let indices = sheet.file.animations?[name]?.frames ?? defaultAnimations[name],
                  !indices.isEmpty else { continue }
            let images = indices.compactMap { sprite(sheet, index: $0, displayHeight: petDisplayHeight, cache: &cache) }
            if !images.isEmpty { return images.map { .image($0) } }
        }
        return nil
    }
    guard let idle = frames(["idle"]) else { return nil }
    return Pet(id: ref.id, name: ref.name, isSprite: true, frames: [
        .asleep: [idle[0]],
        .idle: idle,
        .working: frames(["running"]) ?? idle,
        .waiting: frames(["waiting"]) ?? idle,
        .failed: frames(["failed", "sad"]) ?? idle,
        .celebrating: frames(["waving", "jumping"]) ?? idle,
        .hover: frames(["jumping", "bounce", "waving"]) ?? idle,
        .dragLeft: frames(["running-left", "move_left"]) ?? idle,
        .dragRight: frames(["running-right", "move_right"]) ?? idle,
    ])
}

func codexPetIcon(_ ref: CodexPetRef) -> NSImage? {
    guard let sheet = loadSheet(ref.dir),
          let first = (sheet.file.animations?["idle"]?.frames ?? defaultAnimations["idle"])?.first
    else { return nil }
    var cache: [Int: NSImage] = [:]
    return sprite(sheet, index: first, displayHeight: 18, cache: &cache)
}

// MARK: - Internals

private struct Sheet {
    let cg: CGImage
    let file: CodexPetFile
    let cellW: Int, cellH: Int, columns: Int, rows: Int
}

private func readPetFile(_ dir: URL) -> CodexPetFile? {
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("pet.json")) else { return nil }
    return try? JSONDecoder().decode(CodexPetFile.self, from: data)
}

private func loadSheet(_ dir: URL) -> Sheet? {
    guard let file = readPetFile(dir) else { return nil }
    let sheetURL = dir.appendingPathComponent(file.spritesheetPath ?? "spritesheet.webp")
    guard let image = NSImage(contentsOf: sheetURL),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let cellW = file.frame?.width ?? 192
    let cellH = file.frame?.height ?? 208
    let columns = file.frame?.columns ?? 8
    let rows = file.frame?.rows ?? 9
    guard cellW > 0, cellH > 0, cg.width >= cellW * columns, cg.height >= cellH * rows else { return nil }
    return Sheet(cg: cg, file: file, cellW: cellW, cellH: cellH, columns: columns, rows: rows)
}

// Copies each frame into a small standalone bitmap: a plain cropping(to:) would
// share the full decoded sheet's backing store and keep ~12MB alive per pet.
private func sprite(_ sheet: Sheet, index: Int, displayHeight: CGFloat, cache: inout [Int: NSImage]) -> NSImage? {
    if let cached = cache[index] { return cached }
    let scale: CGFloat = 2
    let pixelH = Int(displayHeight * scale)
    let pixelW = pixelH * sheet.cellW / sheet.cellH
    let col = index % sheet.columns, row = index / sheet.columns
    guard row < sheet.rows,
          let cropped = sheet.cg.cropping(to: CGRect(x: col * sheet.cellW, y: row * sheet.cellH,
                                                     width: sheet.cellW, height: sheet.cellH)),
          let ctx = CGContext(data: nil, width: pixelW, height: pixelH,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
    guard let small = ctx.makeImage() else { return nil }
    let img = NSImage(cgImage: small, size: NSSize(width: CGFloat(pixelW) / scale,
                                                   height: CGFloat(pixelH) / scale))
    cache[index] = img
    return img
}
