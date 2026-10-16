import SwiftUI

struct ToggleButton: View {
    @ObservedObject var line: Line
    let modeAction: (Bool) -> Void
    let noteAction: () -> Void

    var body: some View {
        LineToolbar(staysOpen: line.staysOpen, modeAction: modeAction, noteAction: noteAction)
            .frame(width: TogglePanel.panelSize.width, height: TogglePanel.panelSize.height, alignment: .top)
            .offset(y: line.revealed ? 0 : -(Layout.panelHeight + 12))
            .animation(line.revealed ? .spring(response: 0.42, dampingFraction: 0.82)
                                     : .easeIn(duration: 0.22), value: line.revealed)
    }
}

struct LineToolbar: View {
    let staysOpen: Bool
    let modeAction: (Bool) -> Void
    let noteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: chooseMode) {
                VStack(spacing: -10) {
                    Clothespin().zIndex(1)
                    Image(systemName: staysOpen ? "pin.fill" : "pin")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(staysOpen ? Color.accentColor : Color.primary)
                        .frame(width: 32, height: 34)
                        .glassFrame(cornerRadius: 6)
                }
                .frame(width: 40, height: 82, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(ToolCharmStyle(tilt: 4))
            .accessibilityLabel(L("Display mode", "Modo de visualización", "显示模式"))
            .accessibilityValue(staysOpen
                ? L("Always visible", "Siempre visible", "始终显示")
                : L("Show on top hover", "Mostrar al acercar al borde superior", "顶部悬停显示"))
            .help(L("Display mode", "Modo de visualización", "显示模式"))

            Button(action: noteAction) {
                VStack(spacing: -10) {
                    Clothespin().zIndex(1)
                    Group {
                        if let image = ToolArtwork.hammer {
                            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        } else {
                            Image(systemName: "hammer.fill").resizable().scaledToFit()
                        }
                    }
                    .frame(width: 50, height: 62)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 2)
                }
                .frame(width: 64, height: 82, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(ToolCharmStyle(tilt: -9))
            .accessibilityLabel(L("New note", "Nueva nota", "新建便签"))
            .help(L("Create a text note", "Crear una nota de texto", "新建文字便签"))
        }
    }

    private func chooseMode() {
        let menu = NSMenu(title: L("Display mode", "Modo de visualización", "显示模式"))
        for (value, title) in [(true, L("Always visible", "Siempre visible", "始终显示")),
                               (false, L("Show on top hover", "Mostrar al acercar al borde superior", "顶部悬停显示"))] {
            let item = ClosureMenuItem(title) { modeAction(value) }
            item.state = staysOpen == value ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private struct ToolCharmStyle: ButtonStyle {
    let tilt: Double
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rotationEffect(.degrees(tilt + (hovering && !reduceMotion ? 3 : 0)), anchor: .top)
            .scaleEffect(configuration.isPressed ? 0.95 : (hovering ? 1.05 : 1), anchor: .top)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.55), value: hovering)
            .onHover { hovering = $0 }
    }
}

private enum ToolArtwork {
    static let hammer: NSImage? = {
        if let url = Bundle.main.url(forResource: "hammer", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "hammer", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        #endif
        return nil
    }()
}
