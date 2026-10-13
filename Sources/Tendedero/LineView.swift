import SwiftUI

enum Layout {
    static let panelHeight: CGFloat = 230
    static let ropeTop: CGFloat = 10
    static let preferredSpacing: CGFloat = 174
    static let cardWidth: CGFloat = 150
    static let pinAbove: CGFloat = 9.5
    static let edgeInset: CGFloat = 54
    static let pendingWidth: CGFloat = 118
    static let toolbarReserve: CGFloat = 140

    /// The rope hangs as a parabola from edge to edge of the screen.
    static func sag(width: CGFloat) -> CGFloat { min(30, width * 0.018) }

    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = x / width
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }

    static func trailingReserve(hasAuxiliary: Bool) -> CGFloat {
        hasAuxiliary ? pendingWidth : 0
    }

    static func spacing(count: Int, width: CGFloat, trailingReserve: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        let usable = max(cardWidth, width - edgeInset * 2 - toolbarReserve - trailingReserve)
        return min(preferredSpacing, (usable - cardWidth) / CGFloat(count - 1))
    }

    static func scale(count: Int, width: CGFloat, trailingReserve: CGFloat) -> CGFloat {
        guard count > 1 else { return 1 }
        return max(0.52, min(1, (spacing(count: count, width: width, trailingReserve: trailingReserve) - 10) / cardWidth))
    }

    static func x(index: Int, count: Int, width: CGFloat, trailingReserve: CGFloat = 0) -> CGFloat {
        let step = spacing(count: count, width: width, trailingReserve: trailingReserve)
        let total = CGFloat(max(count - 1, 0)) * step
        let center = (width + toolbarReserve - trailingReserve) / 2
        return center - total / 2 + CGFloat(index) * step
    }
}

struct LineView: View {
    @ObservedObject var line: Line

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let reserve = Layout.trailingReserve(hasAuxiliary: !line.pending.isEmpty || !line.recentStowed.isEmpty)
            let scale = Layout.scale(count: line.items.count, width: width, trailingReserve: reserve)
            ZStack(alignment: .topLeading) {
                Rope(width: width)

                if line.isEmpty {
                    Hint()
                        .position(x: width / 2, y: Layout.ropeY(x: width / 2, width: width) + 34)
                        .transition(.opacity)
                }

                ForEach(Array(line.items.enumerated()), id: \.element.id) { index, item in
                    let x = Layout.x(index: index, count: line.items.count, width: width,
                                     trailingReserve: reserve)
                    let ropeY = Layout.ropeY(x: x, width: width)
                    PeggedView(item: item, line: line, displayScale: scale)
                        .frame(width: Layout.cardWidth, height: Layout.panelHeight - ropeY, alignment: .top)
                        .position(x: x, y: ropeY - Layout.pinAbove + (Layout.panelHeight - ropeY) / 2)
                        .zIndex(line.hoveredID == item.id ? 1000 : Double(index))
                }

                if !line.pending.isEmpty {
                    PendingStack(line: line)
                        .position(x: width - 63, y: 83)
                        .zIndex(2000)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else if !line.recentStowed.isEmpty {
                    RecentStack(line: line)
                        .position(x: width - 67, y: 68)
                        .zIndex(2000)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                if let notice = line.undoNotice {
                    UndoToast(notice: notice, line: line)
                        .position(x: width / 2, y: Layout.panelHeight - 24)
                        .zIndex(3000)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let markerX = line.reorderMarkerX {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 78)
                        .position(x: markerX, y: Layout.ropeY(x: markerX, width: width) + 42)
                        .allowsHitTesting(false)
                        .zIndex(2500)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: line.items.map(\.id))
            .animation(.easeInOut(duration: 0.3), value: line.items.isEmpty)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: line.pending.count)
            .animation(.easeOut(duration: 0.2), value: line.undoNotice?.id)
            // Tucked away, the whole line waits above the top edge and slides
            // out from under the menu bar, the way an auto-hiding Dock does.
            .offset(y: line.revealed ? 0 : -(Layout.panelHeight + 12))
            .animation(line.revealed ? .spring(response: 0.42, dampingFraction: 0.82)
                                     : .easeIn(duration: 0.22), value: line.revealed)
        }
        .onPreferenceChange(HitRectsKey.self) { rects in
            line.hitRects = rects
        }
    }
}

private struct RecentStack: View {
    @ObservedObject var line: Line

    var body: some View {
        Label(L("Recent \(line.recentStowed.count)",
                "Recientes \(line.recentStowed.count)",
                "最近收起 \(line.recentStowed.count)"),
              systemImage: "clock.arrow.circlepath")
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassFrame(capsule: true)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let first = line.recentStowed.first else { return }
                line.restoreRecent(first.id)
            }
            .help(L("Restore the most recently taken down item",
                    "Restaurar el elemento descolgado más reciente",
                    "恢复最近收起的一项"))
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self,
                                           value: [line.recentHitID: g.frame(in: .global)])
                }
            )
    }
}

private struct PendingStack: View {
    @ObservedObject var line: Line

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ForEach(Array(line.pending.prefix(3).enumerated()), id: \.element.id) { index, item in
                    Image(nsImage: item.thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 48)
                        .padding(3)
                        .glassFrame(cornerRadius: 7)
                        .rotationEffect(.degrees(Double(index - 1) * 4))
                        .offset(x: CGFloat(index) * 4, y: CGFloat(index) * 3)
                }
            }
            .frame(width: 88, height: 58)

            Label(
                line.replacementPendingID == nil
                    ? L("Waiting \(line.pending.count)", "En espera \(line.pending.count)", "待上绳 \(line.pending.count)")
                    : L("Cancel replace", "Cancelar reemplazo", "取消替换"),
                systemImage: line.replacementPendingID == nil ? "tray.full" : "xmark.circle.fill")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .glassFrame(capsule: true)
        }
        .contentShape(Rectangle())
        .onTapGesture { line.togglePendingChoice() }
        .help(line.replacementPendingID == nil
              ? L("Choose an item to put on the line", "Elige un elemento para colgar", "点击后选择要收起的旧内容")
              : L("Cancel replacement", "Cancelar reemplazo", "取消本次替换"))
        .background(
            GeometryReader { g in
                Color.clear.preference(key: HitRectsKey.self,
                                       value: [line.pendingHitID: g.frame(in: .global)])
            }
        )
    }
}

private struct UndoToast: View {
    let notice: UndoNotice
    @ObservedObject var line: Line

    var body: some View {
        HStack(spacing: 8) {
            Text(notice.message)
                .lineLimit(1)
            if notice.canUndo {
                Button(action: line.undo) {
                    Label(L("Undo", "Deshacer", "撤销"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
            }
        }
        .font(.system(size: 11.5, weight: .medium, design: .rounded))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassFrame(capsule: true)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: HitRectsKey.self,
                                       value: [line.undoHitID: g.frame(in: .global)])
            }
        )
    }
}

private struct Hint: View {
    var body: some View {
        Text(L("Take a screenshot and it will hang here", "Haz una captura y se quedará colgada aquí"))
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}

/// A thin, neutral line: a mid gray core with a faint highlight and a soft
/// shadow, so it reads on light and dark backgrounds alike. It fades out at
/// both ends so it seems to come from beyond the screen.
struct Rope: View {
    let width: CGFloat

    private var path: Path {
        Path { p in
            let top = Layout.ropeTop
            p.move(to: CGPoint(x: -20, y: top))
            p.addQuadCurve(
                to: CGPoint(x: width + 20, y: top),
                control: CGPoint(x: width / 2, y: top + 2 * Layout.sag(width: width)))
        }
    }

    var body: some View {
        ZStack {
            path.stroke(Color.black.opacity(0.22), lineWidth: 1.4).offset(y: 1.2).blur(radius: 1.2)
            path.stroke(Color(white: 0.55), lineWidth: 1.2)
            path.stroke(Color.white.opacity(0.45), lineWidth: 0.4).offset(y: -0.35)
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .allowsHitTesting(false)
    }
}

struct HitRectsKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
