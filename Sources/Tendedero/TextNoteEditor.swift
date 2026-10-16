import AppKit

struct NoteStyle: RawRepresentable, Hashable, CaseIterable {
    let rawValue: String
    init?(rawValue: String) {
        guard Self.builtins.contains(where: { $0.rawValue == rawValue }) ||
                (rawValue.hasPrefix("custom") && UUID(uuidString: String(rawValue.dropFirst(6))) != nil) else { return nil }
        self.rawValue = rawValue
    }
    private init(_ value: String) { rawValue = value }
    // Kept only to decode older notes; not offered in the style picker.
    static let shirt = NoteStyle("shirt")
    static let tote = NoteStyle("tote")
    static let paperbag = NoteStyle("paperbag")
    static let clock = NoteStyle("clock")
    static let screwdriver = NoteStyle("screwdriver")
    static let house = NoteStyle("house")
    static let apple = NoteStyle("apple")
    static let tomato = NoteStyle("tomato")
    static let bear = NoteStyle("bear")
    static let dino = NoteStyle("dino")
    static let monster = NoteStyle("monster")
    static let bucket = NoteStyle("bucket")
    static let sweetbaby = NoteStyle("sweetbaby")
    static let kissbaby = NoteStyle("kissbaby")
    static let wangyibo = NoteStyle("wangyibo")

    static let builtins: [NoteStyle] = [.shirt, .tote, .paperbag, .clock, .screwdriver, .house, .apple, .tomato, .bear, .dino, .monster, .bucket, .sweetbaby, .kissbaby, .wangyibo]
    static var allCases: [NoteStyle] {
        Array(builtins.dropFirst()) + CustomStyleStore.shared.styles.filter { !$0.archived }.compactMap { NoteStyle(rawValue: $0.key) }
    }
    var custom: CustomNoteStyle? { CustomStyleStore.shared.styles.first { $0.key == rawValue } }
    var hangingLayout: CustomNoteStyle? {
        switch self {
        case .bucket: return Self.bucketLayout
        case .sweetbaby: return Self.sweetBabyLayout
        case .kissbaby: return Self.kissBabyLayout
        case .wangyibo: return Self.wangYiboLayout
        default: return custom
        }
    }

    static let sweetBabyLayout = babyLayout(name: "Sweet Baby", textLeft: 0.25, textTop: 0.40, textWidth: 0.34, textHeight: 0.29)
    static let kissBabyLayout = babyLayout(name: "Kiss Baby", textLeft: 0.24, textTop: 0.39, textWidth: 0.34, textHeight: 0.30)
    static let wangYiboLayout: CustomNoteStyle = {
        var style = babyLayout(name: "WANG YIBO", textLeft: 0.34, textTop: 0.43, textWidth: 0.28, textHeight: 0.28)
        style.red = 0.08; style.green = 0.27; style.blue = 0.15
        return style
    }()

    private static func babyLayout(name: String, textLeft: Double, textTop: Double,
                                   textWidth: Double, textHeight: Double) -> CustomNoteStyle {
        var style = CustomNoteStyle()
        style.name = name
        // Artwork is square, centered within the 140 × 104 thumbnail.
        // Clip the top tab just above its punched hole.
        style.clipX = 0.5; style.clipY = 0.055
        style.textX = (18 + 104 * textLeft) / 140
        style.textY = textTop
        style.textWidth = 104 * textWidth / 140
        style.textHeight = textHeight
        style.fontSize = 11
        style.red = 0.29; style.green = 0.37; style.blue = 0.20
        return style
    }

    static let bucketLayout: CustomNoteStyle = {
        var style = CustomNoteStyle()
        style.name = "水桶"
        // The square artwork fits in the center of the 140 × 104 canvas.
        // Grip the neck beside the cap, toward the handle, with a gentle lean.
        style.clipX = (18 + 104 * 0.60) / 140
        style.clipY = 0.175
        style.tilt = -10
        style.textX = 0.29; style.textY = 0.51
        style.textWidth = 0.43; style.textHeight = 0.30
        style.fontSize = 12
        style.red = 0.19; style.green = 0.31; style.blue = 0.41
        return style
    }()

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
        case .bucket: return L("Water jug", "Bidón de agua", "水桶")
        case .sweetbaby: return "Sweet Baby"
        case .kissbaby: return "Kiss Baby"
        case .wangyibo: return "WANG YIBO"
        default: return custom?.name ?? "自定义便签"
        }
    }

    static func encoded(in url: URL) -> NoteStyle? {
        let stem = url.deletingPathExtension().lastPathComponent
        if stem.hasPrefix("custom"), stem.count >= 42 {
            return NoteStyle(rawValue: String(stem.prefix(42)))
        }
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
final class PasteAwareTextView: NSTextView {
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

@MainActor
enum TextNoteEditor {
    private static var session: NoteEditorSession?

    static func prompt(initial: String = "", style: NoteStyle = .tote,
                       completion: @escaping (TextNoteDraft?) -> Void) {
        if let session {
            session.alert.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
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

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 160))
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
        let workshopAction = WorkshopPickerAction(picker: stylePicker)
        if !workshopAction.choices.contains(style), style.custom != nil { workshopAction.choices.append(style) }
        stylePicker.addItems(withTitles: workshopAction.choices.map(\.name))
        stylePicker.selectItem(at: workshopAction.choices.firstIndex(of: style) ?? 0)
        let workshop = NSButton(title: "便签工坊…", target: workshopAction, action: #selector(WorkshopPickerAction.open))
        workshop.frame = NSRect(x: 235, y: 3, width: 110, height: 28)
        workshop.bezelStyle = .rounded

        container.addSubview(scroll)
        container.addSubview(styleLabel)
        container.addSubview(stylePicker)
        container.addSubview(workshop)
        alert.accessoryView = container

        let controller = NoteEditorSession(alert: alert, editor: editor, workshopAction: workshopAction) { draft in
            session = nil
            completion(draft)
        }
        session = controller
        alert.layout()
        alert.window.delegate = controller
        alert.window.isReleasedWhenClosed = false
        alert.buttons[0].target = controller
        alert.buttons[0].action = #selector(NoteEditorSession.save)
        alert.buttons[1].target = controller
        alert.buttons[1].action = #selector(NoteEditorSession.cancel)

        NSApp.activate(ignoringOtherApps: true)
        // NSAlert can create its window lazily. Set both the initial responder
        // and the live first responder so Command-V works immediately after
        // opening the note, even when the dialog was opened by a global hotkey.
        alert.window.initialFirstResponder = editor
        alert.window.makeFirstResponder(editor)
        alert.window.center()
        alert.window.makeKeyAndOrderFront(nil)
        alert.window.makeFirstResponder(editor)
    }
}

@MainActor
private final class NoteEditorSession: NSObject, NSWindowDelegate {
    let alert: NSAlert
    let editor: NSTextView
    let workshopAction: WorkshopPickerAction
    var completion: ((TextNoteDraft?) -> Void)?
    init(alert: NSAlert, editor: NSTextView, workshopAction: WorkshopPickerAction,
         completion: @escaping (TextNoteDraft?) -> Void) {
        self.alert = alert
        self.editor = editor
        self.workshopAction = workshopAction
        self.completion = completion
    }
    @objc func save() {
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, workshopAction.choices.indices.contains(workshopAction.picker.indexOfSelectedItem) else {
            NSSound.beep()
            alert.window.makeFirstResponder(editor)
            return
        }
        finish(TextNoteDraft(text: text, style: workshopAction.choices[workshopAction.picker.indexOfSelectedItem]))
    }
    @objc func cancel() { finish(nil) }
    func finish(_ draft: TextNoteDraft?) {
        guard alert.window.attachedSheet == nil, let completion else { return }
        self.completion = nil
        alert.window.orderOut(nil)
        completion(draft)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
}

@MainActor
private final class WorkshopPickerAction: NSObject {
    let picker: NSPopUpButton
    var choices = NoteStyle.allCases
    init(picker: NSPopUpButton) { self.picker = picker }
    @objc func open() {
        let previous = choices.indices.contains(picker.indexOfSelectedItem) ? choices[picker.indexOfSelectedItem] : .tote
        NoteWorkshop.open(parent: picker.window) { [weak self] saved in
            guard let self else { return }
            self.choices = NoteStyle.allCases
            if !self.choices.contains(previous), previous.custom != nil { self.choices.append(previous) }
            self.picker.removeAllItems()
            self.picker.addItems(withTitles: self.choices.map(\.name))
            self.picker.selectItem(at: self.choices.firstIndex(of: saved ?? previous) ?? 0)
        }
    }
}
