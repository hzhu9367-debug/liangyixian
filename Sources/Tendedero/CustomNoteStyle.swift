import AppKit
import ImageIO
import UniformTypeIdentifiers

struct CustomNoteStyle: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "我的便签"
    var imageFile = ""
    // Coordinates are normalized to the 140 x 104 thumbnail, from top left.
    var textX = 0.22
    var textY = 0.35
    var textWidth = 0.56
    var textHeight = 0.45
    var clipX = 0.5
    var clipY = 0.06
    var tilt = 0.0
    var fontSize = 13.5
    var alignment = "center"
    var red = 0.13
    var green = 0.12
    var blue = 0.13
    var archived = false
    var key: String { "custom" + id.uuidString }
    var color: NSColor { NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1) }
    var textRect: NSRect {
        NSRect(x: textX * 140, y: (1 - textY - textHeight) * 104,
               width: textWidth * 140, height: textHeight * 104)
    }

    mutating func normalize() {
        name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        if name.isEmpty { name = "我的便签" }
        func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        textWidth = bounded(textWidth, 0.12...1, fallback: 0.56)
        textHeight = bounded(textHeight, 0.12...1, fallback: 0.45)
        textX = bounded(textX, 0...(1 - textWidth), fallback: 0)
        textY = bounded(textY, 0...(1 - textHeight), fallback: 0)
        clipX = bounded(clipX, 0...1, fallback: 0.5)
        clipY = bounded(clipY, 0...1, fallback: 0.06)
        tilt = bounded(tilt, -30...30, fallback: 0)
        fontSize = bounded(fontSize, 8.5...22, fallback: 13.5)
        red = bounded(red, 0...1, fallback: 0.13)
        green = bounded(green, 0...1, fallback: 0.12)
        blue = bounded(blue, 0...1, fallback: 0.13)
        if !["left", "center", "right"].contains(alignment) { alignment = "center" }
    }
}

final class CustomStyleStore {
    static let shared = CustomStyleStore()
    static let changed = Notification.Name("CustomNoteStylesChanged")
    // Keep the chooser and decoder in sync with the formats ImageIO can
    // actually read on this Mac, including HEIC and additional raster types.
    static let importContentTypes: [UTType] = (CGImageSourceCopyTypeIdentifiers() as! [String])
        .compactMap { UTType($0) }.filter { $0.conforms(to: .image) }
    static let importFormatHint = "PNG / JPG / WebP / GIF / HEIC / TIFF / BMP 等 · 最大 20 MB"
    let folder: URL
    private(set) var styles: [CustomNoteStyle] = []
    private var images: [String: NSImage] = [:]

    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Tendedero/Styles", isDirectory: true)) {
        self.folder = folder
        if let data = try? Data(contentsOf: folder.appendingPathComponent("styles.json")),
           let loaded = try? JSONDecoder().decode([CustomNoteStyle].self, from: data) {
            styles = loaded.filter { $0.imageFile == URL(fileURLWithPath: $0.imageFile).lastPathComponent }
            for index in styles.indices { styles[index].normalize() }
        }
    }

    func image(for style: CustomNoteStyle) -> NSImage? {
        guard !style.imageFile.isEmpty else { return nil }
        if let cached = images[style.imageFile] { return cached }
        let result = NSImage(contentsOf: folder.appendingPathComponent(style.imageFile))
        images[style.imageFile] = result
        return result
    }

    func save(_ draft: CustomNoteStyle, image: NSImage) throws -> NoteStyle {
        try save(draft, image: image, png: Self.pngData(image))
    }

    static func pngData(_ image: NSImage) throws -> Data {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            throw WorkshopError.message("无法保存这张图片，请换一张再试。")
        }
        return png
    }

    func save(_ draft: CustomNoteStyle, image: NSImage, png: Data) throws -> NoteStyle {
        var style = draft
        style.normalize()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Version image files so a failed manifest write cannot alter an existing style.
        style.imageFile = "\(style.id.uuidString)-\(UUID().uuidString).png"
        try png.write(to: folder.appendingPathComponent(style.imageFile), options: .atomic)
        var updated = styles
        if let index = updated.firstIndex(where: { $0.id == style.id }) { updated[index] = style }
        else { updated.append(style) }
        try JSONEncoder().encode(updated).write(to: folder.appendingPathComponent("styles.json"), options: .atomic)
        styles = updated
        images[style.imageFile] = image
        NotificationCenter.default.post(name: Self.changed, object: nil)
        return NoteStyle(rawValue: style.key)!
    }

    func archive(_ id: UUID) throws {
        var updated = styles
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].archived = true
        try JSONEncoder().encode(updated).write(to: folder.appendingPathComponent("styles.json"), options: .atomic)
        styles = updated
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    static func importImage(_ url: URL) throws -> (NSImage, String?) {
        let (cgImage, message) = try decodeImage(url)
        return (NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)), message)
    }

    // ImageIO decoding can run off the main thread; AppKit images are created
    // only after the result returns to the workshop.
    static func decodeImage(_ url: URL) throws -> (CGImage, String?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 20 * 1024 * 1024 else { throw WorkshopError.message("图片不能超过 20 MB。") }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String),
              importContentTypes.contains(where: { type.conforms(to: $0) }) else {
            throw WorkshopError.message("图片无法读取。请使用 PNG、JPG、WebP、GIF、HEIC、TIFF、BMP 等本机支持的图片格式。")
        }
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int,
              let h = properties[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, Double(w) * Double(h) <= 60_000_000,
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { throw WorkshopError.message("图片无法读取，或尺寸超过 6000 万像素。请换一张图片再试。") }
        var warnings: [String] = []
        if CGImageSourceGetCount(source) > 1 { warnings.append("多帧或多页图片使用第一张作为静态底图。") }
        if max(w, h) < 600 { warnings.append("这张图片较小，放大后可能模糊。") }
        return (cgImage, warnings.isEmpty ? nil : warnings.joined(separator: " "))
    }
}

enum WorkshopError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

func makeCustomNoteThumbnail(_ text: String, style: CustomNoteStyle, artwork: NSImage?, pixelScale: CGFloat = 2) -> NSImage {
    let image = NSImage(size: NSSize(width: 140, height: 104))
    let scale = max(1, min(8, pixelScale))
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(140 * scale),
                                      pixelsHigh: Int(104 * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return image }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    if let artwork, artwork.size.width > 0, artwork.size.height > 0 {
        let scale = min(140 / artwork.size.width, 104 / artwork.size.height)
        let size = NSSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
        NSGraphicsContext.current?.imageInterpolation = .high
        artwork.draw(in: NSRect(x: (140 - size.width) / 2, y: (104 - size.height) / 2,
                               width: size.width, height: size.height))
    } else {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 132, height: 96), xRadius: 6, yRadius: 6).fill()
    }
    let alignment: NSTextAlignment = style.alignment == "left" ? .left : (style.alignment == "right" ? .right : .center)
    drawNoteText(text, in: style.textRect, color: style.color, maximumFontSize: style.fontSize, alignment: alignment)
    bitmap.size = image.size
    image.addRepresentation(bitmap)
    return image
}
