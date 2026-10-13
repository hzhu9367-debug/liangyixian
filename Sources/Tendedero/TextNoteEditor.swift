import AppKit

enum NoteStyle: String, CaseIterable {
    // Kept only to decode older notes; not offered in the style picker.
    case shirt
    case tote
    case paperbag
    case clock
    case screwdriver
    case house
    case apple
    case tomato
    case bear
    case dino
    case monster

    static let allCases: [NoteStyle] = [.tote, .paperbag, .clock, .screwdriver, .house, .apple, .tomato, .bear, .dino, .monster]

    var name: String {
        switch self {
        case .shirt, .tote: return L("Yellow tote", "Bolsa amarilla", "黄色手提袋")
        case .paperbag: return L("Paper bag", "Bolsa de papel", "牛皮纸袋")
        case .clock: return L("Blue clock", "Reloj azul", "蓝色时钟")
        case .screwdriver: return L("Screwdriver", "Destornillador", "螺丝刀")
        case .house: return L("House", "Casa", "房子")
        case .apple: return L("Apple", "Manzana", "苹果")
        case .tomato: return L("Tomato", "Tomate", "番茄")
        case .bear: return L("Bear", "Osito", "小熊")
        case .dino: return L("Dino", "Dinosaurio", "小恐龙")
        case .monster: return L("Monster", "Monstruo", "小怪兽")
        }
    }

    static func encoded(in url: URL) -> NoteStyle? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard let prefix = stem.split(separator: "-", maxSplits: 1).first else { return nil }
        if prefix == "shirt" { return .tote }
        return NoteStyle(rawValue: String(prefix))
    }

    static func from(url: URL) -> NoteStyle {
        encoded(in: url) ?? .tote
    }
}

struct TextNoteDraft {
    let text: String
    let style: NoteStyle
}

/// NSAlert creates its window lazily, and an accessory NSTextView can otherwise
/// miss the standard paste key equivalent when the dialog was opened by a
/// global shortcut. Keep paste local to the editor so copied text always lands
/// in the note field.
private final class PasteAwareTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, key == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

enum TextNoteEditor {
    static func prompt(initial: String = "", style: NoteStyle = .tote) -> TextNoteDraft? {
        let alert = NSAlert()
        let editing = !initial.isEmpty
        alert.messageText = editing
            ? L("Edit text note", "Editar nota de texto", "编辑文字便签")
            : L("New text note", "Nueva nota de texto", "新建文字便签")
        alert.informativeText = L(
            "Click a note to copy it, or drag it into another app.",
            "Haz clic para copiarla o arrástrala a otra aplicación.",
            "点击便签可复制，拖到其他应用即可粘贴。")
        alert.addButton(withTitle: editing
            ? L("Save", "Guardar", "保存")
            : L("Hang note", "Colgar nota", "挂上便签"))
        alert.addButton(withTitle: L("Cancel", "Cancelar", "取消"))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 160))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 40, width: 340, height: 120))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let editor = PasteAwareTextView(frame: scroll.bounds)
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.usesFontPanel = false
        editor.usesRuler = false
        editor.font = .systemFont(ofSize: 14)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.string = initial
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        scroll.documentView = editor

        let styleLabel = NSTextField(labelWithString: L("Shape:", "Forma:", "外形："))
        styleLabel.frame = NSRect(x: 0, y: 8, width: 52, height: 20)
        styleLabel.alignment = .right

        let stylePicker = NSPopUpButton(frame: NSRect(x: 60, y: 3, width: 150, height: 28))
        stylePicker.addItems(withTitles: NoteStyle.allCases.map(\.name))
        stylePicker.selectItem(at: NoteStyle.allCases.firstIndex(of: style) ?? 0)

        container.addSubview(scroll)
        container.addSubview(styleLabel)
        container.addSubview(stylePicker)
        alert.accessoryView = container

        NSApp.activate(ignoringOtherApps: true)
        // NSAlert can create its window lazily. Set both the initial responder
        // and the live first responder so Command-V works immediately after
        // opening the note, even when the dialog was opened by a global hotkey.
        alert.window.initialFirstResponder = editor
        alert.window.makeFirstResponder(editor)
        DispatchQueue.main.async {
            guard alert.window.isVisible else { return }
            alert.window.makeFirstResponder(editor)
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return TextNoteDraft(text: text, style: NoteStyle.allCases[stylePicker.indexOfSelectedItem])
    }
}
