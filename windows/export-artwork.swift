import AppKit

enum NoteStyle: String, CaseIterable {
    case shirt, tote, paperbag, clock, screwdriver, house, apple, tomato, bear, dino, monster
    var custom: Int? { nil }
}
final class CustomStyleStore {
    static let shared = CustomStyleStore()
    func image(for: Int) -> NSImage? { nil }
}
func makeCustomNoteThumbnail(_ text: String, style: Int, artwork: NSImage?) -> NSImage { NSImage() }

@main struct ExportArtwork {
    static func main() throws {
        _ = NSApplication.shared
        let folder = CommandLine.arguments[1]
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for style in NoteStyle.allCases where style != .shirt {
            let image = makeNoteThumbnail("", style: style)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 560, pixelsHigh: 416, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: NSRect(x: 0, y: 0, width: 560, height: 416))
            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(style.rawValue).png"))
        }
        for (name, size) in [("icon", 256), ("tray", 32)] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            makeNoteThumbnail("", style: .tomato).draw(in: NSRect(x: 0, y: CGFloat(size) * 0.13, width: CGFloat(size), height: CGFloat(size) * 0.74))
            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        }
    }
}
