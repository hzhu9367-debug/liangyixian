import AppKit

@main
@MainActor
final class NoteEditingCheck: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = NoteEditingCheck()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        EditingMenu.install()
        if CommandLine.arguments.contains("--interactive") || Bundle.main.bundleIdentifier == "local.tendedero.note-editing-check" {
            TextNoteEditor.prompt { _ in NSApp.terminate(nil) }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            do {
                try self.runChecks()
                NSApp.terminate(nil)
            } catch {
                print("FAIL: \(error)")
                exit(1)
            }
        }
    }

    private func check(_ value: Bool, line: Int = #line) throws {
        if !value { throw NSError(domain: "NoteEditingCheck", code: line) }
    }

    private func runChecks() throws {
        let clipboard = NSPasteboard.general
        let saved = (clipboard.pasteboardItems ?? []).map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer {
            clipboard.clearContents()
            if !saved.isEmpty { clipboard.writeObjects(saved) }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let editor = PasteAwareTextView(frame: NSRect(x: 0, y: 50, width: 400, height: 190))
        editor.isRichText = false
        editor.allowsUndo = true
        window.contentView!.addSubview(editor)
        let otherField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        window.contentView!.addSubview(otherField)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)

        let sample = "从别处复制的中文与 English 🧺\n第二行，保留换行"
        clipboard.clearContents()
        clipboard.setString(sample, forType: .string)
        let commandV = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                        modifierFlags: [.command, .capsLock], timestamp: 0,
                                        windowNumber: window.windowNumber, context: nil,
                                        characters: "V", charactersIgnoringModifiers: "V",
                                        isARepeat: false, keyCode: 9)!
        try check(editor.performKeyEquivalent(with: commandV))
        try check(editor.string == sample)
        editor.undoManager!.undo()
        try check(editor.string.isEmpty)
        editor.undoManager!.redo()
        try check(editor.string == sample)

        // The menu and context-menu action share the plain-text paste path.
        editor.selectAll(nil)
        let rich = NSAttributedString(string: sample, attributes: [.font: NSFont.boldSystemFont(ofSize: 30)])
        clipboard.clearContents()
        clipboard.setData(try rich.data(from: NSRange(location: 0, length: rich.length),
                                         documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), forType: .rtf)
        let paste = NSApp.mainMenu!.items[1].submenu!.items.first { $0.action == #selector(NSText.paste(_:)) }!
        try check(paste.target == nil)
        try check(NSApp.sendAction(paste.action!, to: paste.target, from: paste))
        try check(editor.string == sample && !editor.isRichText)

        // A hidden note editor must not steal paste from another input field.
        window.makeFirstResponder(otherField)
        clipboard.clearContents()
        clipboard.setString("其他输入框", forType: .string)
        try check(!editor.performKeyEquivalent(with: commandV))
        try check(NSApp.sendAction(paste.action!, to: nil, from: paste))
        try check(otherField.stringValue == "其他输入框")
        try check(editor.string == sample)
        window.orderOut(nil)
        print("PASS: Command-V with Caps Lock, Chinese/emoji/multiline, RTF-only clipboard, menu paste, text undo/redo, and paste into another focused field.")
    }
}
