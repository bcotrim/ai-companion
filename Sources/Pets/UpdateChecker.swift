import AppKit
import CryptoKit
import Foundation

final class UpdateChecker {
    static let shared = UpdateChecker()

    private struct Release: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int?
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
            case digest
        }
    }

    private let releaseURL = URL(string: "https://api.github.com/repos/bcotrim/ai-companion/releases/latest")!
    private var checking = false
    private var downloading = false

    func check() {
        guard !checking, !downloading else {
            showAlert("Update already running", "AI Companion is already checking or downloading an update.")
            return
        }
        checking = true

        var request = URLRequest(url: releaseURL)
        request.setValue("AICompanion", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false

                if let error {
                    self.showAlert("Update check failed", error.localizedDescription)
                    return
                }
                guard let data else {
                    self.showAlert("Update check failed", "GitHub did not return release data.")
                    return
                }

                do {
                    let release = try JSONDecoder().decode(Release.self, from: data)
                    self.offer(release)
                } catch {
                    self.showAlert("Update check failed", error.localizedDescription)
                }
            }
        }.resume()
    }

    private func offer(_ release: Release) {
        guard let asset = release.assets.first(where: { $0.name == "AICompanion.zip" })
            ?? release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
        else {
            showAlert("No download found", "\(release.tagName) does not include a zip build.")
            return
        }
        let checksumAsset = release.assets.first(where: { $0.name == "\(asset.name).sha256" })
            ?? release.assets.first(where: { $0.name.lowercased().hasSuffix(".sha256") })

        let current = currentVersion
        if isNewer(release.tagName, than: current) {
            let alert = NSAlert()
            alert.messageText = "AI Companion \(release.tagName) is available"
            alert.informativeText = canAutoInstall
                ? "You are running \(current)."
                : "You are running \(current). Auto-install is only available from the app bundle."
            if canAutoInstall {
                alert.addButton(withTitle: "Install and Restart")
                alert.addButton(withTitle: "Download Only")
                alert.addButton(withTitle: "Later")
                switch run(alert) {
                case .alertFirstButtonReturn:
                    download(asset, checksumAsset: checksumAsset, from: release, installAfterDownload: true)
                case .alertSecondButtonReturn:
                    download(asset, checksumAsset: checksumAsset, from: release, installAfterDownload: false)
                default:
                    break
                }
            } else {
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                if run(alert) == .alertFirstButtonReturn {
                    download(asset, checksumAsset: checksumAsset, from: release, installAfterDownload: false)
                }
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "AI Companion is up to date"
            alert.informativeText = canAutoInstall
                ? "\(release.tagName) is the latest release."
                : "\(release.tagName) is the latest release. Auto-install is only available from the app bundle."
            alert.addButton(withTitle: "OK")
            if canAutoInstall {
                alert.addButton(withTitle: "Reinstall Latest")
                alert.addButton(withTitle: "Download Anyway")
                switch run(alert) {
                case .alertSecondButtonReturn:
                    download(asset, checksumAsset: checksumAsset, from: release, installAfterDownload: true)
                case .alertThirdButtonReturn:
                    download(asset, checksumAsset: checksumAsset, from: release, installAfterDownload: false)
                default:
                    break
                }
            } else {
                alert.addButton(withTitle: "Download Anyway")
                if run(alert) == .alertSecondButtonReturn {
                    download(asset, checksumAsset: checksumAsset, from: release, installAfterDownload: false)
                }
            }
        }
    }

    private func download(_ asset: Asset, checksumAsset: Asset?, from release: Release, installAfterDownload: Bool) {
        guard !downloading else { return }
        downloading = true

        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("AICompanion", forHTTPHeaderField: "User-Agent")

        URLSession.shared.downloadTask(with: request) { [weak self] tempURL, _, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.downloading = false
                    self.showAlert("Download failed", error.localizedDescription)
                }
                return
            }
            guard let tempURL else {
                DispatchQueue.main.async {
                    self.downloading = false
                    self.showAlert("Download failed", "GitHub did not return a file.")
                }
                return
            }

            do {
                let destination = try self.destinationURL(for: release, asset: asset)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                try self.verifyChecksum(for: destination, asset: asset, checksumAsset: checksumAsset)
                DispatchQueue.main.async {
                    self.downloading = false
                    if installAfterDownload {
                        self.install(downloadedZip: destination)
                    } else {
                        self.showDownloaded(destination)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.downloading = false
                    self.showAlert("Download failed", error.localizedDescription)
                }
            }
        }.resume()
    }

    private func verifyChecksum(for file: URL, asset: Asset, checksumAsset: Asset?) throws {
        do {
            guard let expected = try expectedChecksum(for: asset, checksumAsset: checksumAsset) else {
                throw updateError("The release is missing a checksum for \(asset.name).")
            }
            let actual = try sha256Hex(of: file)
            guard actual == expected else {
                throw updateError("Checksum mismatch for \(asset.name).")
            }
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    private func expectedChecksum(for asset: Asset, checksumAsset: Asset?) throws -> String? {
        if let digest = asset.digest?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           digest.hasPrefix("sha256:") {
            let hash = String(digest.dropFirst("sha256:".count))
            if isSHA256(hash) { return hash }
        }
        guard let checksumAsset else { return nil }
        let text = try String(contentsOf: checksumAsset.browserDownloadURL, encoding: .utf8)
        return checksum(from: text, matching: asset.name)
    }

    private func checksum(from text: String, matching assetName: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let hash = parts.first?.lowercased(), isSHA256(hash) else { continue }
            if parts.count == 1 || parts.dropFirst().contains(where: { $0 == assetName || $0 == "*\(assetName)" }) {
                return hash
            }
        }
        return nil
    }

    private func sha256Hex(of file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isNumber || ("a"..."f").contains($0) }
    }

    private func install(downloadedZip: URL) {
        guard canAutoInstall else {
            showAlert("Update downloaded", "Auto-install only works when AI Companion is running from the app bundle.")
            NSWorkspace.shared.activateFileViewerSelecting([downloadedZip])
            return
        }

        do {
            let stagedApp = try unpackedApp(from: downloadedZip)
            try launchInstaller(stagedApp: stagedApp, targetApp: Bundle.main.bundleURL)
        } catch {
            showAlert("Install failed", error.localizedDescription)
            NSWorkspace.shared.activateFileViewerSelecting([downloadedZip])
        }
    }

    private func unpackedApp(from zipURL: URL) throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-companion-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, staging.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            throw updateError(String(decoding: data, as: UTF8.self).nilIfEmpty ?? "Could not unzip the update.")
        }

        guard let app = findApp(in: staging) else {
            throw updateError("The downloaded zip did not contain AICompanion.app.")
        }
        let executable = app.appendingPathComponent("Contents/MacOS/pets")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw updateError("The downloaded app is missing its executable.")
        }
        return app
    }

    private func findApp(in directory: URL) -> URL? {
        if directory.pathExtension == "app" { return directory }
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == "AICompanion.app" {
            return url
        }
        return nil
    }

    private func launchInstaller(stagedApp: URL, targetApp: URL) throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-companion-install-\(UUID().uuidString).sh")
        let sourceDir = stagedApp.deletingLastPathComponent().path
        let body = """
        #!/bin/bash
        set -euo pipefail

        NEW_APP="$1"
        TARGET_APP="$2"
        OLD_PID="$3"
        SOURCE_DIR="$4"
        BACKUP="${TARGET_APP}.previous"
        LOG="/tmp/ai-companion-update.log"

        {
          echo "Installing AI Companion update at $(date)"
          while kill -0 "$OLD_PID" 2>/dev/null; do sleep 0.2; done
          rm -rf "$BACKUP"
          if [ -e "$TARGET_APP" ]; then mv "$TARGET_APP" "$BACKUP"; fi
          if mv "$NEW_APP" "$TARGET_APP"; then
            xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
            open "$TARGET_APP"
            rm -rf "$BACKUP" "$SOURCE_DIR"
          else
            if [ -e "$BACKUP" ]; then mv "$BACKUP" "$TARGET_APP"; fi
            open "$TARGET_APP" || true
            exit 1
          fi
        } >>"$LOG" 2>&1
        """
        try body.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            script.path,
            stagedApp.path,
            targetApp.path,
            String(ProcessInfo.processInfo.processIdentifier),
            sourceDir,
        ]
        try process.run()

        NSApp.terminate(nil)
    }

    private var canAutoInstall: Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return false }
        return FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/MacOS/pets").path)
    }

    private func destinationURL(for release: Release, asset: Asset) throws -> URL {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
        throw NSError(domain: "AICompanion", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not find the Downloads folder.",
        ])
        }
        let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return downloads.appendingPathComponent("AICompanion-\(version)-\(asset.name)")
    }

    private func showDownloaded(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Update downloaded"
        alert.informativeText = url.path
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "OK")
        if run(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private func isNewer(_ latest: String, than current: String) -> Bool {
        let a = versionParts(latest)
        let b = versionParts(current)
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private func versionParts(_ value: String) -> [Int] {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }

    private func showAlert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        _ = run(alert)
    }

    private func updateError(_ message: String) -> Error {
        NSError(domain: "AICompanion", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
