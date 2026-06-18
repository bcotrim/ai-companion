import AppKit

// Codex CLI pet format (codex-rs/tui/src/pets): a folder with pet.json + a webp
// spritesheet laid out as an 8x9 grid of 192x208 cells, row-major. Rows have
// fixed meanings; pet.json may override the grid and animation frame indices.
// We read these in place so they keep working in Codex untouched.
// Pets are scanned cheaply (JSON only); spritesheets decode lazily on selection.
// The app ships Wapuu (the default pet) in its resource bundle, scanned first —
// a same-id copy in the user dirs is ignored.

struct CodexPetRef {
    let id: String
    let name: String
    let dir: URL
}

enum PetInstallError: LocalizedError {
    case invalidSource([String])
    case duplicate(String)
    case extractionFailed(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidSource(let issues): return issues.joined(separator: "\n")
        case .duplicate(let id): return "A pet named \(id) is already installed."
        case .extractionFailed(let output): return output.nilIfEmpty ?? "The zip could not be extracted."
        case .notFound: return "No pet.json was found."
        }
    }
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
    "review": Array(64..<70),         // row 8
]

let defaultPetDisplayHeight: CGFloat = AppSettings.defaultPetSize

let codexPetDirs: [URL] = [
    Bundle.module.resourceURL,
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/pets"),
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/pets"),
].compactMap { $0 }

func scanCodexPets() -> [CodexPetRef] {
    var seen = Set<String>()
    return codexPetDirs.flatMap { dir -> [CodexPetRef] in
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return entries.compactMap { petDir in
            guard let file = readPetFile(petDir) else { return nil }
            let id = file.id ?? petDir.lastPathComponent
            return CodexPetRef(id: "codex:\(id)", name: file.displayName ?? id, dir: petDir)
        }
        .sorted { $0.name < $1.name }
    }
    .filter { seen.insert($0.id).inserted }
}

func loadCodexPet(_ ref: CodexPetRef, displayHeight: CGFloat = defaultPetDisplayHeight) -> Pet? {
    guard let sheet = loadSheet(ref.dir) else { return nil }
    var cache: [Int: NSImage] = [:]
    func frames(_ names: [String]) -> [PetFrame]? {
        for name in names {
            guard let indices = sheet.file.animations?[name]?.frames ?? defaultAnimations[name],
                  !indices.isEmpty else { continue }
            let images = indices.compactMap { sprite(sheet, index: $0, displayHeight: displayHeight, cache: &cache) }
            if !images.isEmpty { return images.map { .image($0) } }
        }
        return nil
    }
    guard let idle = frames(["idle"]) else { return nil }
    // Needs-you alternates a stretch of the waiting row with a couple of waves —
    // the wave is a much clearer "hey, over here!" than marching alone.
    let waitingRow = frames(["waiting"]) ?? idle
    var needsYou = waitingRow + waitingRow + waitingRow
    if let wave = frames(["waving"]) { needsYou += wave + wave }
    return Pet(id: ref.id, name: ref.name, isSprite: true, frames: [
        .asleep: [idle[0]],
        .idle: idle,
        .working: frames(["running"]) ?? idle,
        .reviewing: frames(["review", "running"]) ?? idle,
        .subagent: frames(["running", "review"]) ?? idle,
        .tasking: frames(["review", "waving"]) ?? idle,
        .compacting: frames(["jumping", "running"]) ?? idle,
        .waiting: needsYou,
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

func validateCodexPet(at dir: URL) -> [String] {
    var issues: [String] = []
    guard let file = readPetFile(dir) else {
        return ["Missing or invalid pet.json."]
    }

    let sheetURL = dir.appendingPathComponent(file.spritesheetPath ?? "spritesheet.webp")
    guard FileManager.default.fileExists(atPath: sheetURL.path) else {
        return ["Missing spritesheet: \(sheetURL.lastPathComponent)."]
    }
    guard let image = NSImage(contentsOf: sheetURL),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        return ["Could not decode spritesheet: \(sheetURL.lastPathComponent)."]
    }

    let cellW = file.frame?.width ?? 192
    let cellH = file.frame?.height ?? 208
    let columns = file.frame?.columns ?? 8
    let rows = file.frame?.rows ?? 9
    if cellW <= 0 || cellH <= 0 || columns <= 0 || rows <= 0 {
        issues.append("Frame width, height, columns, and rows must be positive.")
    } else {
        let expectedW = cellW * columns
        let expectedH = cellH * rows
        if cg.width < expectedW || cg.height < expectedH {
            issues.append("Spritesheet is \(cg.width)x\(cg.height), expected at least \(expectedW)x\(expectedH).")
        }
        let maxIndex = columns * rows
        for (name, animation) in file.animations ?? [:] {
            if animation.frames.isEmpty {
                issues.append("Animation \(name) has no frames.")
            }
            for index in animation.frames where index < 0 || index >= maxIndex {
                issues.append("Animation \(name) references frame \(index), outside 0...\(maxIndex - 1).")
            }
        }
    }
    return issues
}

func installCodexPet(from source: URL, replaceExisting: Bool = false) throws -> CodexPetRef {
    let prepared = try preparedPetDirectory(from: source)
    defer {
        if let temp = prepared.temp {
            try? FileManager.default.removeItem(at: temp)
        }
    }

    let issues = validateCodexPet(at: prepared.dir)
    guard issues.isEmpty, let file = readPetFile(prepared.dir) else {
        throw PetInstallError.invalidSource(issues)
    }

    let id = sanitizePetID(file.id ?? prepared.dir.lastPathComponent)
    let name = file.displayName ?? id
    let petsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/pets")
    let destination = petsDir.appendingPathComponent(id)

    if prepared.dir.standardizedFileURL == destination.standardizedFileURL {
        return CodexPetRef(id: "codex:\(id)", name: name, dir: destination)
    }

    try FileManager.default.createDirectory(at: petsDir, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: destination.path) {
        guard replaceExisting else { throw PetInstallError.duplicate(id) }
        try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: prepared.dir, to: destination)
    return CodexPetRef(id: "codex:\(id)", name: name, dir: destination)
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

private func preparedPetDirectory(from source: URL) throws -> (dir: URL, temp: URL?) {
    if readPetFile(source) != nil {
        return (source, nil)
    }

    if source.pathExtension.lowercased() == "zip" {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-companion-pet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        var keepTemp = false
        defer {
            if !keepTemp {
                try? FileManager.default.removeItem(at: temp)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", source.path, temp.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            throw PetInstallError.extractionFailed(String(decoding: data, as: UTF8.self))
        }
        guard let dir = findPetDirectory(in: temp) else {
            throw PetInstallError.notFound
        }
        keepTemp = true
        return (dir, temp)
    }

    guard let dir = findPetDirectory(in: source) else {
        throw PetInstallError.notFound
    }
    return (dir, nil)
}

private func findPetDirectory(in url: URL) -> URL? {
    if readPetFile(url) != nil { return url }
    guard let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    else { return nil }
    for case let item as URL in enumerator {
        guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        if readPetFile(item) != nil { return item }
    }
    return nil
}

private func sanitizePetID(_ id: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    let scalars = id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    return value.nilIfEmpty ?? "pet"
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
