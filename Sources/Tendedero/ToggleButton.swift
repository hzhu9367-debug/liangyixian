import SwiftUI

struct ToggleButton: View {
    @ObservedObject var line: Line
    let action: () -> Void
    let noteAction: () -> Void

    var body: some View {
        LineToolbar(staysOpen: line.staysOpen, action: action, noteAction: noteAction)
            .frame(width: TogglePanel.panelSize.width, height: TogglePanel.panelSize.height, alignment: .top)
    }
}

struct LineToolbar: View {
    let staysOpen: Bool
    let action: () -> Void
    let noteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: action) {
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
            .accessibilityLabel(L("Keep line open", "Fijar tendedero", "保持晾衣线展开"))
            .accessibilityValue(staysOpen ? L("On", "Activado", "已开启") : L("Off", "Desactivado", "已关闭"))
            .help(staysOpen
                  ? L("Click to hide the clothesline", "Pulsa para ocultar el tendedero", "点击收起晾衣线")
                  : L("Click to keep the clothesline open", "Pulsa para fijar el tendedero", "点击后保持晾衣线展开"))

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
