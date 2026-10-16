import AppKit

/// Compile alongside Sources/Tendedero/*.swift, excluding main.swift.
@main
@MainActor
struct RemovalCheck {
    static func main() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("line-removal-\(UUID())")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let domain = "local.line-removal.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "soundOff")
        // An old installation's history must not restore removed cards.
        let legacyHistory = Data("[]".utf8)
        defaults.set(legacyHistory, forKey: "recentStowed.v1")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Tendedero/Resources/tomato.png")
        let originals = try (0..<3).map { index -> URL in
            let url = folder.appendingPathComponent("screenshot-\(index).png")
            try fm.copyItem(at: source, to: url)
            return url
        }
        let bytes = try originals.map { try Data(contentsOf: $0) }
        let line = Line(defaults: defaults, startsBreeze: false)
        line.maxItems = 2
        let first = line.hang(originals[0], quietly: true)!
        let second = line.hang(originals[1], quietly: true)!
        line.togglePinned(first)
        line.stow(first, quietly: true)
        precondition(line.items.map(\.id) == [second] && line.canUndo)
        let reloaded = Line(defaults: defaults, startsBreeze: false)
        precondition(reloaded.items.map(\.url) == [originals[1]])
        line.undo()
        precondition(line.items.map(\.id) == [first, second] && line.items[0].isPinned)
        precondition(line.hang(originals[2], quietly: true) == nil)
        line.togglePendingChoice()
        line.primaryAction(second)
        precondition(line.items[1].url == originals[2] && line.pending.isEmpty)
        line.undo()
        precondition(line.items.map(\.id) == [first, second])
        precondition(line.items[0].isPinned && line.pending.map(\.url) == [originals[2]])
        for (index, url) in originals.enumerated() {
            let remainingBytes = try Data(contentsOf: url)
            precondition(remainingBytes == bytes[index], "Removal changed an original file")
        }
        precondition(defaults.data(forKey: "recentStowed.v1") == legacyHistory)
        print("PASS: removal persists without deleting files; undo restores position and pin; replacement undo restores the queue; originals remain byte-for-byte unchanged.")
    }
}
