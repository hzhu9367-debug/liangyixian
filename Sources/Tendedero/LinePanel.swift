import AppKit

/// A transparent strip along the top of the screen that floats over every
/// app, Space and full-screen auxiliary Space, never takes focus, and lets clicks pass through
/// everywhere except over the photos.
final class LinePanel: NSPanel, NSDraggingDestination {
    var dropOperation: ((NSDraggingInfo) -> NSDragOperation)?
    var onDrop: ((NSDraggingInfo) -> Bool)?
    var onDragExit: (() -> Void)?

    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        registerForDraggedTypes([
            GrabView.lineItemType, .fileURL, .png, .tiff, NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.webp")
        ])
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropOperation?(sender) ?? []
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropOperation?(sender) ?? []
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExit?()
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = onDrop?(sender) ?? false
        onDragExit?()
        return accepted
    }

    /// The line hangs on the screen you are using, which is the one with the
    /// pointer: that is where you just took the screenshot.
    static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    func placeOnScreen(_ screen: NSScreen? = nil) {
        guard let visible = (screen ?? LinePanel.screenUnderPointer())?.visibleFrame else { return }
        let target = NSRect(x: visible.minX, y: visible.maxY - Layout.panelHeight,
                            width: visible.width, height: Layout.panelHeight)
        if frame != target { setFrame(target, display: true) }
    }
}

/// A small always-visible control above the line. It remains available even
/// while the line is tucked away, so the menu bar is not the only way to open it.
final class TogglePanel: NSPanel {
    static let panelSize = NSSize(width: 124, height: 96)

    init(content: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false
        content.frame = NSRect(origin: .zero, size: Self.panelSize)
        content.autoresizingMask = [.width, .height]
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func placeOnScreen(_ screen: NSScreen? = nil) {
        guard let screen = screen ?? LinePanel.screenUnderPointer() else { return }
        let visible = screen.visibleFrame
        let left: CGFloat = 12
        let clipX = left + Self.panelSize.width / 2
        let clipTop = Layout.ropeY(x: clipX, width: visible.width) - Layout.pinAbove
        let target = NSRect(x: visible.minX + left,
                            y: visible.maxY - clipTop - Self.panelSize.height,
                            width: Self.panelSize.width, height: Self.panelSize.height)
        if frame != target { setFrame(target, display: true) }
        contentView?.frame = NSRect(origin: .zero, size: Self.panelSize)
    }

    func ensureVisible(on screen: NSScreen?) {
        placeOnScreen(screen)
        alphaValue = 1
        orderFrontRegardless()
    }
}
