import AppKit
import SwiftUI

/// Bridges each photo to AppKit's drag and drop, so it can be dragged into
/// any app as a real file. Each destination means one thing:
///
/// - An app gets a copy, and the photo stays on the line.
/// - A folder or the Desktop keeps the file, and the photo leaves the line.
/// - The Trash discards it.
/// - Nowhere that accepts it: the photo flies back to the line.
///
/// Click copies, press and hold opens Markup, the corner cross removes the card while keeping its file.
struct GrabArea: NSViewRepresentable {
    let item: Pegged
    let line: Line

    func makeNSView(context: Context) -> GrabView {
        let view = GrabView()
        configure(view)
        return view
    }

    func updateNSView(_ view: GrabView, context: Context) {
        configure(view)
    }

    private func configure(_ view: GrabView) {
        let id = item.id
        let line = line
        view.itemID = id
        view.url = item.url
        view.text = item.note
        view.dragImage = item.thumb
        view.onClick = { line.primaryAction(id) }
        view.onDoubleClick = { line.open(id) }
        view.onDragStart = { line.draggingID = id }
        view.onDragEnd = {
            line.draggingID = nil
            line.reorderMarkerX = nil
            // Moved into a folder: it is saved where you wanted it.
            if item.note == nil {
                line.prune()
                // Finder may finish moving the file after the drag callback.
                // Only prune here; do not clear a newer drag's state later.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { line.prune() }
            }
        }
        view.onTrash = { line.trash(id) }
        view.onDiscard = { line.stow(id) }
        view.onLongPress = { line.markup(id) }
        view.onPressChange = { pressed in line.pressedID = pressed ? id : nil }
        view.menuProvider = {
            let menu = NSMenu()
            menu.addItem(ClosureMenuItem(L("Copy", "Copiar", "复制")) { line.copy(id) })
            if item.note != nil {
                menu.addItem(ClosureMenuItem(L("Edit note", "Editar nota", "编辑便签")) { line.editNote(id) })
                menu.addItem(.separator())
                menu.addItem(ClosureMenuItem(L("Remove from line (keep file)", "Quitar del tendedero (conservar archivo)", "移除（保留文件）")) { line.stow(id) })
                menu.addItem(ClosureMenuItem(L("Move to Trash", "Mover a la Papelera", "移到废纸篓")) { line.trash(id) })
                return menu
            }
            menu.addItem(ClosureMenuItem(L("Open", "Abrir", "打开")) { line.open(id) })
            menu.addItem(ClosureMenuItem(L("Markup", "Marcación", "标记")) { line.markup(id) })
            menu.addItem(ClosureMenuItem(L("Show in Finder", "Mostrar en Finder", "在访达中显示")) { line.reveal(id) })
            let inInbox = line.isInInbox(id)
            if inInbox {
                menu.addItem(ClosureMenuItem(L("Save to Desktop", "Guardar en el Escritorio", "保存到桌面")) { line.saveToDesktop(id) })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(L("Remove from line (keep file)", "Quitar del tendedero (conservar archivo)", "移除（保留文件）")) { line.stow(id) })
            menu.addItem(ClosureMenuItem(L("Move to Trash", "Mover a la Papelera", "移到废纸篓")) { line.trash(id) })
            return menu
        }
    }
}

final class GrabView: NSView, NSDraggingSource {
    static var isDragging = false
    static let lineItemType = NSPasteboard.PasteboardType("app.tendedero.line-item")

    var itemID: UUID?
    var url: URL?
    var text: String?
    var dragImage: NSImage?
    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onDragStart: () -> Void = {}
    var onDragEnd: () -> Void = {}
    var onTrash: () -> Void = {}
    var onDiscard: () -> Void = {}
    var onLongPress: () -> Void = {}
    var onPressChange: (Bool) -> Void = { _ in }
    var menuProvider: () -> NSMenu = { NSMenu() }

    private var downPoint: NSPoint?
    private var startedDrag = false
    private var holdTimer: Timer?
    private var didLongPress = false

    /// How long you hold before Markup opens. Long enough not to fire on a
    /// slow click, short enough to feel deliberate.
    private static let holdDuration: TimeInterval = 0.45

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The removal control drawn in the top right corner of the card. It is
    /// handled here because this view sits on top of the SwiftUI card.
    static let crossHitSize: CGFloat = 26

    private func isInCross(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        let corner = NSRect(x: bounds.width - Self.crossHitSize,
                            y: isFlipped ? 0 : bounds.height - Self.crossHitSize,
                            width: Self.crossHitSize, height: Self.crossHitSize)
        return corner.contains(p)
    }

    override func mouseDown(with event: NSEvent) {
        if isInCross(event) {
            downPoint = nil
            onDiscard()
            return
        }
        if event.clickCount == 2 {
            downPoint = nil
            onDoubleClick()
            return
        }
        downPoint = event.locationInWindow
        startedDrag = false
        didLongPress = false
        onPressChange(true)
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.downPoint != nil, !self.startedDrag else { return }
                self.didLongPress = true
                self.onPressChange(false)
                self.onLongPress()
            }
        }
    }

    private func endPress() {
        holdTimer?.invalidate()
        holdTimer = nil
        onPressChange(false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !startedDrag else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4, !didLongPress else { return }
        startedDrag = true
        endPress()

        guard let writer = makeDragPasteboardItem() else { return }
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(imageFrame(), contents: dragImage)
        GrabView.isDragging = true
        onDragStart()
        let session = beginDraggingSession(with: [item], event: event, source: self)
        // Released where nothing accepts it: it flies back to the line.
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func makeDragPasteboardItem() -> NSPasteboardItem? {
        let writer = NSPasteboardItem()
        if let text {
            writer.setString(text, forType: .string)
            writer.setData(Data(text.utf8), forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
        } else if let url {
            writer.setString(url.absoluteString, forType: .fileURL)
        } else {
            return nil
        }
        if let itemID { writer.setString(itemID.uuidString, forType: Self.lineItemType) }
        return writer
    }

    override func mouseUp(with event: NSEvent) {
        endPress()
        if downPoint != nil && !startedDrag && !didLongPress && event.clickCount == 1 { onClick() }
        downPoint = nil
        didLongPress = false
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Apps pick copy. Finder picks move, so a folder or the Desktop keeps
        // the file. Delete is what lets the Dock's Trash accept it.
        guard context == .outsideApplication else { return [.move] }
        return text == nil ? [.copy, .move, .delete] : [.copy]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        GrabView.isDragging = false
        startedDrag = false
        downPoint = nil
        log.notice("Drag ended with operation \(operation.rawValue, privacy: .public)")
        // Dropped on the Trash: macOS only tells us, we move the file.
        if operation.contains(.delete) {
            onDragEnd()
            onTrash()
            return
        }
        onDragEnd()
    }

    /// The drag preview keeps the photo's aspect ratio inside the card.
    private func imageFrame() -> NSRect {
        guard let size = dragImage?.size, size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
