import AppKit

/// Accessory apps still need a main Edit menu for AppKit to route keyboard
/// equivalents through the key window's responder chain (including fields).
@MainActor
enum EditingMenu {
    static func install() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("Quit", "Salir", "退出桌面晾衣杆"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("Edit", "Editar", "编辑"))
        edit.addItem(withTitle: L("Undo", "Deshacer", "撤销"),
                     action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L("Redo", "Rehacer", "重做"),
                                action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Cut", "Cortar", "剪切"),
                     action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Copy", "Copiar", "复制"),
                     action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Paste", "Pegar", "粘贴"),
                     action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let plainPaste = edit.addItem(withTitle: L("Paste as plain text", "Pegar como texto sin formato", "粘贴为纯文本"),
                                      action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        plainPaste.keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(withTitle: L("Select All", "Seleccionar todo", "全选"),
                     action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
