import AppKit
import Combine
import os

let log = Logger(subsystem: "app.tendedero.Tendedero", category: "line")

/// One screenshot hanging on the line.
struct Pegged: Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var thumb: NSImage
    var note: String? = nil
    var noteStyle: NoteStyle? = nil
    var isPinned = false
    /// Every photo hangs a little crooked, like on a real line.
    let tilt = Double.random(in: -2.5...2.5)
    var falling = false
    /// Still flying in from where it was captured; the card waits hidden.
    var flying = false

    static func == (a: Pegged, b: Pegged) -> Bool {
        a.id == b.id && a.falling == b.falling && a.flying == b.flying
            && a.isPinned == b.isPinned && a.thumb === b.thumb
    }
}

struct RecentStowed: Codable, Identifiable, Equatable {
    let id: UUID
    let path: String
    let date: Date
    let wasPinned: Bool
    let title: String
}

struct UndoNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let canUndo: Bool
}

/// The line itself: what hangs on it and what you can do with each item.
/// The files never move. The line is only a view onto them.
@MainActor
final class Line: ObservableObject {
    @Published private(set) var items: [Pegged] = []
    @Published private(set) var pending: [Pegged] = []
    @Published private(set) var recentStowed: [RecentStowed] = []
    @Published private(set) var gust = 0
    @Published var copiedID: UUID?
    @Published var draggingID: UUID?
    @Published var reorderMarkerX: CGFloat?
    @Published var pressedID: UUID?
    @Published var hoveredID: UUID?
    @Published private(set) var replacementPendingID: UUID?
    @Published private(set) var undoNotice: UndoNotice?
    @Published private(set) var canUndo = false
    @Published var staysOpen: Bool
    /// Whether the line has slid down into view.
    @Published var revealed = false

    /// Card frames in window coordinates, reported by the views. The panel
    /// uses them to only catch clicks over photos and let the rest through.
    var hitRects: [UUID: CGRect] = [:]
    let pendingHitID = UUID()
    let recentHitID = UUID()
    let undoHitID = UUID()

    var maxItems = 12


    var soundOn: Bool {
        get { !defaults.bool(forKey: "soundOff") }
        set { defaults.set(!newValue, forKey: "soundOff") }
    }

    var liveCount: Int { items.filter { !$0.falling }.count }
    var pendingCount: Int { pending.count }
    var isEmpty: Bool { liveCount == 0 && pending.isEmpty }

    private let storeKey = "pegged"
    private let defaults: UserDefaults
    private let storeV2Key = "pegged.v2"
    private let pendingKey = "pending.v1"
    private let recentKey = "recentStowed.v1"
    private var undoStack: [UndoAction] = []
    private var noticeWorkItem: DispatchWorkItem?

    private struct StoredItem: Codable {
        let path: String
        let isPinned: Bool
    }

    private enum UndoAction {
        case stow(item: Pegged, index: Int, recentID: UUID)
        case delete(item: Pegged, index: Int, originalURL: URL, trashURL: URL)
        case replace(old: Pegged, index: Int, new: Pegged, recentID: UUID)
        case reorder(id: UUID, index: Int)
    }
    private static let notesFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("Tendedero/Notes", isDirectory: true)

    init(defaults: UserDefaults = .standard, startsBreeze: Bool = true) {
        self.defaults = defaults
        staysOpen = defaults.bool(forKey: "lineStaysOpen")
        restore()
        if startsBreeze { scheduleGust() }
    }

    func setStaysOpen(_ value: Bool) {
        staysOpen = value
        defaults.set(value, forKey: "lineStaysOpen")
    }

    @discardableResult
    func reorder(_ id: UUID, before targetID: UUID?) -> Bool {
        guard let from = items.firstIndex(where: { $0.id == id }), !items[from].falling,
              targetID != id,
              targetID == nil || items.contains(where: { $0.id == targetID && !$0.falling }) else { return false }
        var ordered = items
        let item = ordered.remove(at: from)
        let to = targetID.flatMap { target in ordered.firstIndex { $0.id == target } } ?? ordered.count
        guard from != to else { return true }
        ordered.insert(item, at: to)
        items = ordered
        save()
        pushUndo(.reorder(id: id, index: from),
                 message: L("Position changed", "Posición cambiada", "已调整位置"))
        return true
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false, flying: Bool = false) -> UUID? {
        guard !contains(url),
              let thumb = makeThumbnail(url) else { return nil }
        var item = Pegged(url: url, thumb: thumb)
        item.flying = flying
        let hung = addNewItem(item)
        save()
        if !quietly { play("Tink", volume: 0.35) }
        return hung ? item.id : nil
    }

    /// Accepts an image dragged from Finder, a browser or another app. File
    /// URLs stay as the original file; raw image data is persisted first so it
    /// remains available after the source app closes.
    func canImportDragged(_ info: NSDraggingInfo) -> Bool {
        let pasteboard = info.draggingPasteboard
        if let urls = draggedFileURLs(from: pasteboard),
           urls.contains(where: { makeThumbnail($0) != nil }) {
            return true
        }
        return [NSPasteboard.PasteboardType("public.png"), .tiff,
                NSPasteboard.PasteboardType("public.jpeg"),
                NSPasteboard.PasteboardType("public.webp")]
            .contains(where: { pasteboard.data(forType: $0) != nil })
    }

    func importDragged(_ info: NSDraggingInfo) -> Bool {
        let pasteboard = info.draggingPasteboard
        if let urls = draggedFileURLs(from: pasteboard) {
            let images = urls.filter { makeThumbnail($0) != nil }
            guard !images.isEmpty else { return false }
            for url in images { _ = hang(url) }
            return true
        }

        for type in [NSPasteboard.PasteboardType("public.png"), .tiff,
                     NSPasteboard.PasteboardType("public.jpeg"),
                     NSPasteboard.PasteboardType("public.webp")] {
            guard let data = pasteboard.data(forType: type), !data.isEmpty,
                  let url = saveImportedImage(data, type: type) else { continue }
            _ = hang(url)
            return true
        }
        return false
    }

    private func draggedFileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        guard let objects = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return nil }
        return objects.compactMap { object in
            if let url = object as? URL { return url }
            if let url = object as? NSURL { return url as URL }
            return nil
        }
    }

    private func saveImportedImage(_ data: Data, type: NSPasteboard.PasteboardType) -> URL? {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tendedero/Imported", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let ext: String
            switch type {
            case .tiff: ext = "tiff"
            case NSPasteboard.PasteboardType("public.jpeg"): ext = "jpg"
            case NSPasteboard.PasteboardType("public.webp"): ext = "webp"
            default: ext = "png"
            }
            let url = folder.appendingPathComponent("Imported-\(UUID().uuidString).\(ext)")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            log.error("Could not save dragged image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func createNote() {
        guard let draft = TextNoteEditor.prompt() else { return }
        let folder = Self.notesFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder
                .appendingPathComponent("\(draft.style.rawValue)-\(UUID().uuidString)")
                .appendingPathExtension("txt")
            try draft.text.write(to: url, atomically: true, encoding: .utf8)
            let item = Pegged(
                url: url,
                thumb: makeNoteThumbnail(draft.text, style: draft.style),
                note: draft.text,
                noteStyle: draft.style)
            _ = addNewItem(item)
            save()
            play("Tink", volume: 0.35)
        } catch {
            log.error("Could not create note: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    /// The capture has reached the line: the real card takes over.
    func land(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].flying = false
    }

    /// Called just before a photo starts falling, so the fall can be drawn
    /// over the whole screen.
    var onFall: ((Pegged) -> Void)?

    func drop(_ id: UUID, quietly: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        let item = items.remove(at: i)
        onFall?(item)
        hitRects[id] = nil
        save()
        if !quietly { play("Pop", volume: 0.25) }
    }

    func clear() {
        let live = items.filter { !$0.falling }
        for (n, item) in live.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(n)) { [weak self] in
                self?.stow(item.id, quietly: n > 0)
            }
        }
    }

    /// Photos whose file was deleted or moved away fall off by themselves.
    func prune() {
        for item in items where !item.falling && !FileManager.default.fileExists(atPath: item.url.path) {
            drop(item.id, quietly: true)
        }
    }

    // MARK: Actions on one photo

    func copy(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let note = item.note {
            // Write the standard text flavor directly. Some editors do not
            // read an NSPasteboardItem passed through writeObjects reliably.
            pb.setString(note, forType: .string)
            pb.setData(Data(note.utf8), forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
        } else {
            let entry = NSPasteboardItem()
            if let png = pngData(item.url) { entry.setData(png, forType: .png) }
            entry.setString(item.url.absoluteString, forType: .fileURL)
            pb.writeObjects([entry])
        }

        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
    }

    func primaryAction(_ id: UUID) {
        if replacementPendingID != nil {
            replaceWithPending(removing: id)
        } else {
            copy(id)
        }
    }

    func togglePinned(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isPinned.toggle()
        save()
        play("Tink", volume: 0.22)
    }

    func togglePendingChoice() {
        guard let next = pending.first else { return }
        if liveCount < maxItems {
            pending.removeFirst()
            var landed = next
            landed.flying = false
            items.append(landed)
            replacementPendingID = nil
            save()
            play("Tink", volume: 0.35)
            return
        }
        replacementPendingID = replacementPendingID == next.id ? nil : next.id
    }

    func cancelReplacement() {
        replacementPendingID = nil
    }

    private func replaceWithPending(removing id: UUID) {
        guard let pendingID = replacementPendingID,
              let pendingIndex = pending.firstIndex(where: { $0.id == pendingID }),
              let oldIndex = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[oldIndex].isPinned else {
            showNotice(L("Pinned items cannot be replaced", "Los elementos fijados no se pueden reemplazar", "已锁定的内容不能替换"), canUndo: false, seconds: 2.5)
            NSSound.beep()
            return
        }

        let old = items[oldIndex]
        var new = pending.remove(at: pendingIndex)
        new.flying = false
        items[oldIndex] = new
        let recentID = addRecent(old)
        replacementPendingID = nil
        pushUndo(.replace(old: old, index: oldIndex, new: new, recentID: recentID),
                 message: L("Replaced. Undo?", "Reemplazado. ¿Deshacer?", "已替换，可撤销"))
        save()
        play("Tink", volume: 0.35)
    }

    func stow(_ id: UUID, quietly: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        onFall?(item)
        hitRects[id] = nil
        let recentID = addRecent(item)
        pushUndo(.stow(item: item, index: index, recentID: recentID),
                 message: L("Taken down. Undo?", "Descolgado. ¿Deshacer?", "已收起，可撤销"))
        save()
        if !quietly { play("Pop", volume: 0.25) }
    }

    func open(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.note != nil {
            editNote(id)
            return
        }
        NSWorkspace.shared.open(item.url)
    }

    func editNote(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }),
              let current = items[i].note,
              let updated = TextNoteEditor.prompt(
                initial: current,
                style: items[i].noteStyle ?? NoteStyle.from(url: items[i].url)) else { return }
        do {
            let oldURL = items[i].url
            var targetURL = oldURL
            if NoteStyle.encoded(in: oldURL) != updated.style {
                targetURL = Self.notesFolder
                    .appendingPathComponent("\(updated.style.rawValue)-\(UUID().uuidString)")
                    .appendingPathExtension("txt")
            }
            try updated.text.write(to: targetURL, atomically: true, encoding: .utf8)
            if targetURL != oldURL {
                try? FileManager.default.removeItem(at: oldURL)
                items[i].url = targetURL
            }
            items[i].note = updated.text
            items[i].noteStyle = updated.style
            items[i].thumb = makeNoteThumbnail(updated.text, style: updated.style)
            save()
        } catch {
            log.error("Could not update note: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    /// Moves the file to the Trash and takes the photo off the line. When a
    /// drag ends on the Dock's Trash, macOS only reports it: deleting the file
    /// is the source app's job, as Finder does.
    func trash(_ id: UUID, quietly: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        do {
            var trashed: NSURL?
            try FileManager.default.trashItem(at: item.url, resultingItemURL: &trashed)
            guard let trashURL = trashed as URL? else {
                throw CocoaError(.fileWriteUnknown)
            }
            log.notice("Trashed \(item.url.lastPathComponent, privacy: .public)")
            if soundOn && !quietly { Line.trashSound?.play() }
            items.remove(at: index)
            hitRects[id] = nil
            pushUndo(.delete(item: item, index: index, originalURL: item.url, trashURL: trashURL),
                     message: L("Moved to Trash. Undo?", "Movido a la Papelera. ¿Deshacer?", "已移到废纸篓，可撤销"))
            save()
        } catch {
            log.error("Could not trash \(item.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private static let trashSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif",
        byReference: true)

    /// Whether the file lives in Tendedero's own folder. Those are discarded
    /// to the Trash, or the folder would fill up with forgotten screenshots.
    /// Files anywhere else, like the Desktop, stay where they are.
    func isInInbox(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return item.url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
    }

    /// Inbox mode: keep a screenshot by moving it to the Desktop.
    func saveToDesktop(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let target = uniqueURL(in: desktop, for: item.url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            item.url = target
            items.remove(at: index)
            let recentID = addRecent(item)
            pushUndo(.stow(item: item, index: index, recentID: recentID),
                     message: L("Saved and taken down. Undo?", "Guardado y descolgado. ¿Deshacer?", "已保存并收起，可撤销"))
            save()
        } catch {
            log.error("Could not save to Desktop: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Long press: open the photo in the system Markup editor.
    func markup(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.note != nil {
            editNote(id)
            return
        }
        Markup.shared.edit(item.url)
    }

    /// After editing, the photo on the line shows the new version.
    func reloadThumbnail(for url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url) else { return }
        items[i].thumb = thumb
    }

    func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: Undo and recent items

    func undo() {
        guard let action = undoStack.popLast() else { return }
        canUndo = !undoStack.isEmpty
        do {
            switch action {
            case let .reorder(id, index):
                guard let current = items.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
                let item = items.remove(at: current)
                items.insert(item, at: min(index, items.count))
            case let .stow(item, index, recentID):
                guard FileManager.default.fileExists(atPath: item.url.path) else { throw CocoaError(.fileNoSuchFile) }
                items.insert(item, at: min(index, items.count))
                removeRecent(recentID)

            case let .delete(item, index, originalURL, trashURL):
                guard FileManager.default.fileExists(atPath: trashURL.path) else { throw CocoaError(.fileNoSuchFile) }
                try FileManager.default.createDirectory(
                    at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let restoredURL = FileManager.default.fileExists(atPath: originalURL.path)
                    ? uniqueURL(in: originalURL.deletingLastPathComponent(), for: originalURL.lastPathComponent)
                    : originalURL
                try FileManager.default.moveItem(at: trashURL, to: restoredURL)
                var restored = item
                restored.url = restoredURL
                items.insert(restored, at: min(index, items.count))

            case let .replace(old, index, new, recentID):
                items.removeAll { $0.id == new.id }
                pending.insert(new, at: 0)
                items.insert(old, at: min(index, items.count))
                removeRecent(recentID)
                replacementPendingID = nil
            }
            save()
            showNotice(
                undoStack.isEmpty
                    ? L("Undone", "Deshecho", "已撤销")
                    : L("Undone. Press Command-Z again for the previous action", "Deshecho. Pulsa Comando-Z otra vez", "已撤销，再按 Command + Z 可继续撤销"),
                canUndo: !undoStack.isEmpty)
        } catch {
            log.error("Could not undo: \(error.localizedDescription, privacy: .public)")
            showNotice(L("Could not undo", "No se pudo deshacer", "无法撤销"), canUndo: false)
            NSSound.beep()
        }
    }

    func restoreRecent(_ id: UUID) {
        guard let recent = recentStowed.first(where: { $0.id == id }),
              !contains(URL(fileURLWithPath: recent.path)),
              var item = loadItem(path: recent.path, pinned: recent.wasPinned) else { return }
        item.flying = false
        if liveCount < maxItems {
            items.append(item)
        } else {
            pending.append(item)
        }
        undoStack.removeAll { action in
            switch action {
            case let .stow(_, _, recentID), let .replace(_, _, _, recentID):
                return recentID == id
            case .delete, .reorder:
                return false
            }
        }
        canUndo = !undoStack.isEmpty
        removeRecent(id)
        save()
        play("Tink", volume: 0.35)
    }

    func clearRecent() {
        recentStowed.removeAll()
        saveRecent()
    }

    private func pushUndo(_ action: UndoAction, message: String) {
        undoStack.append(action)
        if undoStack.count > 20 { undoStack.removeFirst(undoStack.count - 20) }
        canUndo = true
        showNotice(message, canUndo: true)
    }

    private func showNotice(_ message: String, canUndo: Bool, seconds: TimeInterval = 10) {
        noticeWorkItem?.cancel()
        let notice = UndoNotice(message: message, canUndo: canUndo)
        undoNotice = notice
        let work = DispatchWorkItem { [weak self] in
            guard self?.undoNotice?.id == notice.id else { return }
            self?.undoNotice = nil
        }
        noticeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    @discardableResult
    private func addRecent(_ item: Pegged) -> UUID {
        let record = RecentStowed(
            id: UUID(), path: item.url.path, date: Date(), wasPinned: item.isPinned,
            title: item.note?.prefix(24).description ?? item.url.lastPathComponent)
        recentStowed.removeAll { $0.path == record.path }
        recentStowed.insert(record, at: 0)
        pruneRecent()
        saveRecent()
        return record.id
    }

    private func removeRecent(_ id: UUID) {
        recentStowed.removeAll { $0.id == id }
        saveRecent()
    }

    // MARK: Breeze

    /// Every so often a little wind moves the line. It is the detail that
    /// makes it feel like an object and not a widget.
    private func scheduleGust() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 3...8)) { [weak self] in
            guard let self else { return }
            if !self.items.isEmpty && self.draggingID == nil { self.gust += 1 }
            self.scheduleGust()
        }
    }

    // MARK: Persistence

    private func save() {
        let encoder = JSONEncoder()
        let onLine = items.filter { !$0.falling }.map { StoredItem(path: $0.url.path, isPinned: $0.isPinned) }
        let waiting = pending.map { StoredItem(path: $0.url.path, isPinned: $0.isPinned) }
        defaults.set(try? encoder.encode(onLine), forKey: storeV2Key)
        defaults.set(try? encoder.encode(waiting), forKey: pendingKey)
        defaults.set(onLine.map(\.path), forKey: storeKey)
    }

    private func restore() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: storeV2Key),
           let stored = try? decoder.decode([StoredItem].self, from: data) {
            items = stored.compactMap { loadItem(path: $0.path, pinned: $0.isPinned) }
        } else {
            let paths = defaults.stringArray(forKey: storeKey) ?? []
            items = paths.compactMap { loadItem(path: $0, pinned: false) }
        }
        if let data = defaults.data(forKey: pendingKey),
           let stored = try? decoder.decode([StoredItem].self, from: data) {
            pending = stored.compactMap { loadItem(path: $0.path, pinned: $0.isPinned) }
                .filter { item in !items.contains(where: { $0.url == item.url }) }
        }
        if let data = defaults.data(forKey: recentKey),
           let stored = try? decoder.decode([RecentStowed].self, from: data) {
            recentStowed = stored
            pruneRecent()
        }
        save()
    }

    private func loadItem(path: String, pinned: Bool) -> Pegged? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        if url.standardizedFileURL.path.hasPrefix(Self.notesFolder.standardizedFileURL.path + "/"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let style = NoteStyle.from(url: url)
            return Pegged(url: url, thumb: makeNoteThumbnail(text, style: style),
                          note: text, noteStyle: style, isPinned: pinned)
        }
        guard let thumb = makeThumbnail(url) else { return nil }
        return Pegged(url: url, thumb: thumb, isPinned: pinned)
    }

    private func addNewItem(_ item: Pegged) -> Bool {
        if liveCount < maxItems {
            items.append(item)
            return true
        }
        var waiting = item
        waiting.flying = false
        pending.append(waiting)
        replacementPendingID = nil
        return false
    }

    private func contains(_ url: URL) -> Bool {
        items.contains(where: { $0.url == url && !$0.falling }) || pending.contains(where: { $0.url == url })
    }

    private func pruneRecent() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        recentStowed = Array(recentStowed
            .filter { $0.date >= cutoff && FileManager.default.fileExists(atPath: $0.path) }
            .prefix(20))
        saveRecent()
    }

    private func saveRecent() {
        defaults.set(try? JSONEncoder().encode(recentStowed), forKey: recentKey)
    }

    // MARK: Helpers

    private func play(_ name: String, volume: Float) {
        guard soundOn, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    private func pngData(_ url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

private func makeLegacyNoteThumbnail(_ text: String, style: NoteStyle) -> NSImage {
    // Retired clothing notes use the replacement artwork, even via this old path.
    if [.shirt, .tote, .paperbag, .clock, .screwdriver].contains(style) {
        return makeNoteThumbnail(text, style: style)
    }
    let size = NSSize(width: 140, height: 104)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.shouldAntialias = true
    let shape = NSBezierPath()
    var textRect: NSRect
    var textColor = NSColor(calibratedWhite: 0.16, alpha: 1)

    switch style {
    case .tote, .paperbag, .clock, .screwdriver:
        return makeNoteThumbnail(text, style: style)
    case .shirt:
        shape.move(to: NSPoint(x: 45, y: 96))
        shape.curve(to: NSPoint(x: 70, y: 84), controlPoint1: NSPoint(x: 50, y: 91), controlPoint2: NSPoint(x: 57, y: 85))
        shape.curve(to: NSPoint(x: 95, y: 96), controlPoint1: NSPoint(x: 83, y: 85), controlPoint2: NSPoint(x: 90, y: 91))
        shape.line(to: NSPoint(x: 116, y: 88))
        shape.line(to: NSPoint(x: 132, y: 67))
        shape.line(to: NSPoint(x: 113, y: 54))
        shape.line(to: NSPoint(x: 105, y: 64))
        shape.line(to: NSPoint(x: 105, y: 9))
        shape.curve(to: NSPoint(x: 35, y: 9), controlPoint1: NSPoint(x: 86, y: 5), controlPoint2: NSPoint(x: 54, y: 5))
        shape.line(to: NSPoint(x: 35, y: 64))
        shape.line(to: NSPoint(x: 27, y: 54))
        shape.line(to: NSPoint(x: 8, y: 67))
        shape.line(to: NSPoint(x: 24, y: 88))
        shape.close()
        NSColor(calibratedRed: 0.98, green: 0.48, blue: 0.49, alpha: 1).setFill()
        shape.fill()
        textRect = NSRect(x: 38, y: 19, width: 64, height: 53)
        textColor = NSColor.white.withAlphaComponent(0.96)

        let collar = NSBezierPath()
        collar.move(to: NSPoint(x: 51, y: 93))
        collar.curve(to: NSPoint(x: 70, y: 82), controlPoint1: NSPoint(x: 55, y: 83), controlPoint2: NSPoint(x: 62, y: 80))
        collar.curve(to: NSPoint(x: 89, y: 93), controlPoint1: NSPoint(x: 78, y: 80), controlPoint2: NSPoint(x: 85, y: 83))
        collar.lineWidth = 3
        NSColor.white.withAlphaComponent(0.7).setStroke()
        collar.stroke()

    case .house:
        shape.move(to: NSPoint(x: 18, y: 55))
        shape.line(to: NSPoint(x: 70, y: 99))
        shape.line(to: NSPoint(x: 122, y: 55))
        shape.line(to: NSPoint(x: 113, y: 55))
        shape.line(to: NSPoint(x: 113, y: 8))
        shape.line(to: NSPoint(x: 27, y: 8))
        shape.line(to: NSPoint(x: 27, y: 55))
        shape.close()
        NSColor(calibratedRed: 0.45, green: 0.82, blue: 0.73, alpha: 1).setFill()
        shape.fill()
        textRect = NSRect(x: 35, y: 16, width: 70, height: 48)

        let roof = NSBezierPath()
        roof.move(to: NSPoint(x: 13, y: 54))
        roof.line(to: NSPoint(x: 70, y: 102))
        roof.line(to: NSPoint(x: 127, y: 54))
        roof.lineWidth = 8
        roof.lineCapStyle = .round
        roof.lineJoinStyle = .round
        NSColor(calibratedRed: 0.98, green: 0.63, blue: 0.38, alpha: 1).setStroke()
        roof.stroke()

    case .apple:
        shape.move(to: NSPoint(x: 70, y: 82))
        shape.curve(to: NSPoint(x: 31, y: 83), controlPoint1: NSPoint(x: 53, y: 98), controlPoint2: NSPoint(x: 36, y: 91))
        shape.curve(to: NSPoint(x: 20, y: 44), controlPoint1: NSPoint(x: 16, y: 72), controlPoint2: NSPoint(x: 14, y: 56))
        shape.curve(to: NSPoint(x: 49, y: 8), controlPoint1: NSPoint(x: 25, y: 25), controlPoint2: NSPoint(x: 37, y: 9))
        shape.curve(to: NSPoint(x: 70, y: 14), controlPoint1: NSPoint(x: 58, y: 7), controlPoint2: NSPoint(x: 64, y: 13))
        shape.curve(to: NSPoint(x: 91, y: 8), controlPoint1: NSPoint(x: 76, y: 13), controlPoint2: NSPoint(x: 82, y: 7))
        shape.curve(to: NSPoint(x: 120, y: 44), controlPoint1: NSPoint(x: 103, y: 9), controlPoint2: NSPoint(x: 115, y: 25))
        shape.curve(to: NSPoint(x: 109, y: 83), controlPoint1: NSPoint(x: 126, y: 56), controlPoint2: NSPoint(x: 124, y: 72))
        shape.curve(to: NSPoint(x: 70, y: 82), controlPoint1: NSPoint(x: 104, y: 91), controlPoint2: NSPoint(x: 87, y: 98))
        shape.close()
        NSColor(calibratedRed: 0.96, green: 0.34, blue: 0.35, alpha: 1).setFill()
        shape.fill()
        textRect = NSRect(x: 34, y: 22, width: 72, height: 52)
        textColor = NSColor.white.withAlphaComponent(0.96)

        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 70, y: 84))
        stem.curve(to: NSPoint(x: 76, y: 101), controlPoint1: NSPoint(x: 70, y: 91), controlPoint2: NSPoint(x: 73, y: 98))
        stem.lineWidth = 4
        stem.lineCapStyle = .round
        NSColor(calibratedRed: 0.35, green: 0.24, blue: 0.14, alpha: 1).setStroke()
        stem.stroke()

        let leaf = NSBezierPath()
        leaf.move(to: NSPoint(x: 77, y: 96))
        leaf.curve(to: NSPoint(x: 100, y: 98), controlPoint1: NSPoint(x: 85, y: 105), controlPoint2: NSPoint(x: 95, y: 104))
        leaf.curve(to: NSPoint(x: 77, y: 96), controlPoint1: NSPoint(x: 94, y: 89), controlPoint2: NSPoint(x: 85, y: 89))
        leaf.close()
        NSColor(calibratedRed: 0.35, green: 0.72, blue: 0.38, alpha: 1).setFill()
        leaf.fill()

    case .tomato:
        shape.append(NSBezierPath(ovalIn: NSRect(x: 8, y: 9, width: 124, height: 84)))
        NSColor(calibratedRed: 0.94, green: 0.29, blue: 0.19, alpha: 1).setFill()
        shape.fill()
        textRect = NSRect(x: 24, y: 20, width: 92, height: 38)
        textColor = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.82, alpha: 1)

    case .bear:
        shape.append(NSBezierPath(roundedRect: NSRect(x: 10, y: 8, width: 120, height: 86),
                                  xRadius: 38, yRadius: 38))
        NSColor(calibratedRed: 0.58, green: 0.34, blue: 0.20, alpha: 1).setFill()
        shape.fill()
        NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: 68, width: 28, height: 25)).fill()
        NSBezierPath(ovalIn: NSRect(x: 94, y: 68, width: 28, height: 25)).fill()
        textRect = NSRect(x: 28, y: 20, width: 84, height: 39)
        textColor = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.82, alpha: 1)

    case .dino:
        shape.append(NSBezierPath(roundedRect: NSRect(x: 10, y: 8, width: 120, height: 86),
                                  xRadius: 28, yRadius: 28))
        NSColor(calibratedRed: 0.52, green: 0.78, blue: 0.22, alpha: 1).setFill()
        shape.fill()
        textRect = NSRect(x: 24, y: 18, width: 92, height: 38)
        textColor = NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.15, alpha: 1)

    case .monster:
        shape.append(NSBezierPath(roundedRect: NSRect(x: 10, y: 8, width: 120, height: 86),
                                  xRadius: 28, yRadius: 28))
        NSColor(calibratedRed: 0.31, green: 0.47, blue: 0.90, alpha: 1).setFill()
        shape.fill()
        textRect = NSRect(x: 24, y: 18, width: 92, height: 38)
        textColor = NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.65, alpha: 1)
    }

    shape.lineWidth = 1.2
    NSColor.black.withAlphaComponent(0.10).setStroke()
    shape.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    paragraph.lineSpacing = 1.5
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
        .foregroundColor: textColor,
        .paragraphStyle: paragraph,
    ]
    (text as NSString).draw(
        with: textRect,
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
        attributes: attributes)
    return image
}

func makeThumbnail(_ url: URL, maxPixels: Int = 480) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
