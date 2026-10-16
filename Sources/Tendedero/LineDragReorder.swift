import AppKit

/// Route local drags to ordering without treating their file payload as an import.
@MainActor
final class LineDragReorder {
    let line: Line
    private weak var panel: LinePanel?

    init(line: Line, panel: LinePanel) {
        self.line = line
        self.panel = panel
        panel.dropOperation = { [weak self] in self?.operation(for: $0) ?? [] }
        panel.onDrop = { [weak self] in self?.drop($0) ?? false }
        panel.onDragExit = { [weak line] in line?.reorderMarkerX = nil }
    }

    private func destination(for info: NSDraggingInfo) -> (UUID, UUID?, CGFloat)? {
        guard let panel, line.revealed,
              let source = info.draggingSource as? GrabView,
              let id = source.itemID, line.draggingID == id,
              info.draggingPasteboard.string(forType: GrabView.lineItemType) == id.uuidString,
              line.items.contains(where: { $0.id == id && !$0.falling && !$0.flying }) else { return nil }
        let point = info.draggingLocation
        let width = panel.frame.width
        let reserve = Layout.trailingReserve(hasAuxiliary: !line.pending.isEmpty)
        guard point.y >= 0, point.y <= panel.frame.height,
              point.x >= Layout.toolbarReserve, point.x <= width - reserve else { return nil }
        let others = line.items.enumerated().filter { $0.element.id != id && !$0.element.falling }
        let centers = others.map {
            Layout.x(index: $0.offset, count: line.items.count, width: width, trailingReserve: reserve)
        }
        let index = centers.firstIndex(where: { point.x < $0 }) ?? centers.count
        let target = index < others.count ? others[index].element.id : nil
        let marker: CGFloat
        if centers.isEmpty { marker = point.x }
        else if index == 0 { marker = centers[0] - 40 }
        else if index == centers.count { marker = centers[index - 1] + 40 }
        else { marker = (centers[index - 1] + centers[index]) / 2 }
        return (id, target, marker)
    }

    func operation(for info: NSDraggingInfo) -> NSDragOperation {
        if let (_, _, marker) = destination(for: info) {
            if line.reorderMarkerX != marker { line.reorderMarkerX = marker }
            return .move
        }
        line.reorderMarkerX = nil
        // A local payload outside the valid line area must not re-import itself.
        if info.draggingSource is GrabView { return [] }
        return line.canImportDragged(info) ? .copy : []
    }

    func drop(_ info: NSDraggingInfo) -> Bool {
        defer { line.reorderMarkerX = nil }
        if let (id, target, _) = destination(for: info) { return line.reorder(id, before: target) }
        if info.draggingSource is GrabView { return false }
        return line.importDragged(info)
    }
}
