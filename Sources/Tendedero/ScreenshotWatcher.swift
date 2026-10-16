import Foundation

/// Watches the folder macOS saves screenshots to and reports new ones.
/// Tendedero never takes screenshots itself: you keep your usual shortcut
/// (or CleanShot, or anything else) and the line just picks them up.
final class ScreenshotWatcher {
    let folder: URL
    /// On the Desktop we only accept real screenshots, tagged by macOS with an
    /// extended attribute. In a dedicated folder, any image counts.
    private let onlyTaggedScreenshots: Bool
    private var known = Set<String>()
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "app.tendedero.screenshot-watcher", qos: .utility)
    // Accessed only on the main queue; stale background scans cannot deliver captures.
    private var activeID: UUID?
    private let onNew: (URL) -> Void
    private let onChange: () -> Void

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp"]

    static let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

    /// Watches the folder macOS saves screenshots to, or a given folder.
    init(folder: URL? = nil, onNew: @escaping (URL) -> Void, onChange: @escaping () -> Void) {
        self.onNew = onNew
        self.onChange = onChange
        self.folder = folder ?? Self.screenshotFolder()
        onlyTaggedScreenshots = self.folder.standardizedFileURL.path == Self.desktop.standardizedFileURL.path
    }

    static func screenshotFolder() -> URL {
        let fm = FileManager.default
        // Read fresh through cfprefsd: inbox mode changes this value at runtime.
        CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)
        // macOS 27 keeps it in "location-screenshot"; earlier versions in "location".
        let domain = "com.apple.screencapture" as CFString
        let raw = (CFPreferencesCopyAppValue("location-screenshot" as CFString, domain) as? String)
            ?? (CFPreferencesCopyAppValue("location" as CFString, domain) as? String)
        if let raw, !raw.isEmpty {
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url }
        }
        return fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Anything created after the app launched counts as new, even if it
    /// landed before the watcher was ready (macOS may be asking for Desktop
    /// access at that moment).
    private let launchDate = Date()

    func start() {
        let id = UUID()
        activeID = id
        queue.async { [weak self] in self?.startWatching(id: id) }
    }

    private func startWatching(id: UUID) {
        pending?.cancel()
        source?.cancel()
        let files = listing()
        known = Set(files.filter { creationDate($0) < launchDate }.map(\.path))
        deliver(files.filter { !known.contains($0.path) && isCandidate($0) }, id: id)
        known = Set(files.map(\.path))
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Tendedero: cannot watch \(folder.path)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        src.setEventHandler { [weak self] in self?.scheduleScan(id: id) }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        activeID = nil
        queue.async { [weak self] in
            self?.pending?.cancel()
            self?.source?.cancel()
            self?.source = nil
        }
    }

    private func scheduleScan(id: UUID) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan(id: id) }
        pending = work
        // macOS writes a hidden temp file and renames it; give it a moment.
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func scan(id: UUID) {
        let files = listing()
        deliver(files.filter { !known.contains($0.path) && isCandidate($0) }, id: id, changed: true)
        known = Set(files.map(\.path))
    }

    private func deliver(_ files: [URL], id: UUID, changed: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activeID == id else { return }
            files.forEach(self.onNew)
            if changed { self.onChange() }
        }
    }

    private func listing() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        return urls.sorted { creationDate($0) < creationDate($1) }
    }

    private func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    private func isCandidate(_ url: URL) -> Bool {
        guard Self.imageExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return onlyTaggedScreenshots ? isScreenCapture(url) : true
    }

    private func isScreenCapture(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
        }
    }
}
