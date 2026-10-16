import AppKit

/// Die-cut paper notes inspired by small screen-printed stationery: a warm
/// paper edge, restrained flat color, and subtle paper grain.
func makeNoteThumbnail(_ text: String, style: NoteStyle) -> NSImage {
    if style == .bucket {
        return makeCustomNoteThumbnail(text, style: NoteStyle.bucketLayout, artwork: NoteArtworkResources.bucket, pixelScale: 4)
    }
    if style == .sweetbaby || style == .kissbaby, let layout = style.hangingLayout {
        return makeCustomNoteThumbnail(text, style: layout,
                                       artwork: style == .sweetbaby ? NoteArtworkResources.sweetbaby : NoteArtworkResources.kissbaby,
                                       pixelScale: 4)
    }
    if style == .wangyibo {
        return makeCustomNoteThumbnail(text, style: NoteStyle.wangYiboLayout, artwork: NoteArtworkResources.wangyibo, pixelScale: 4)
    }
    if let custom = style.custom {
        return makeCustomNoteThumbnail(text, style: custom, artwork: CustomStyleStore.shared.image(for: custom))
    }
    let image = NSImage(size: NSSize(width: 140, height: 104))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.shouldAntialias = true
    let layout: (NSRect, NSColor)
    switch style {
    case .shirt, .tote:
        drawNoteArtwork(NoteArtworkResources.tote)
        layout = (NSRect(x: 41, y: 30, width: 58, height: 42), Paper.ink)
    case .paperbag:
        drawNoteArtwork(NoteArtworkResources.paperbag)
        layout = (NSRect(x: 54, y: 20, width: 50, height: 52), Paper.ink)
    case .clock:
        drawNoteArtwork(NoteArtworkResources.clock)
        layout = (NSRect(x: 40, y: 32, width: 60, height: 36), Paper.ink)
    case .screwdriver:
        drawNoteArtwork(NoteArtworkResources.screwdriver, upsideDown: true)
        layout = (NSRect(x: 48, y: 52, width: 44, height: 38), Paper.ink)
    case .house:
        drawPaperHouse()
        layout = (NSRect(x: 36, y: 29, width: 72, height: 39), Paper.ink)
    case .apple:
        drawPaperApple()
        layout = (NSRect(x: 34, y: 30, width: 70, height: 41), Paper.cream)
    case .tomato:
        drawNoteArtwork(NoteArtworkResources.tomato)
        layout = (NSRect(x: 32, y: 15, width: 76, height: 35), Paper.cream)
    case .bear:
        drawNoteArtwork(NoteArtworkResources.bear)
        layout = (NSRect(x: 32, y: 15, width: 76, height: 35), Paper.cream)
    case .dino:
        drawPaperDino()
        layout = (NSRect(x: 18, y: 12, width: 104, height: 30), Paper.dinoDark)
    case .monster:
        drawPaperMonster()
        layout = (NSRect(x: 18, y: 12, width: 104, height: 30), Paper.monsterDark)
    default:
        drawNoteArtwork(NoteArtworkResources.tote)
        layout = (NSRect(x: 41, y: 30, width: 58, height: 42), Paper.ink)
    }
    let maximumFontSize: CGFloat = style == .screwdriver ? 10.5 : (style == .paperbag ? 11.5 : 13.5)
    drawNoteText(text, in: layout.0, color: layout.1, maximumFontSize: maximumFontSize)
    return image
}

private enum Paper {
    static let cream = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.82, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.13, alpha: 1)
    static let mustard = NSColor(calibratedRed: 0.91, green: 0.64, blue: 0.08, alpha: 1)
    static let mustardDark = NSColor(calibratedRed: 0.72, green: 0.43, blue: 0.04, alpha: 1)
    static let sage = NSColor(calibratedRed: 0.28, green: 0.57, blue: 0.43, alpha: 1)
    static let forest = NSColor(calibratedRed: 0.12, green: 0.39, blue: 0.27, alpha: 1)
    static let tomato = NSColor(calibratedRed: 0.82, green: 0.25, blue: 0.14, alpha: 1)
    static let leaf = NSColor(calibratedRed: 0.28, green: 0.58, blue: 0.38, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.32, green: 0.66, blue: 0.78, alpha: 1)
    static let blush = NSColor(calibratedRed: 0.79, green: 0.25, blue: 0.33, alpha: 1)
    static let dino = NSColor(calibratedRed: 0.55, green: 0.81, blue: 0.27, alpha: 1)
    static let dinoLight = NSColor(calibratedRed: 0.91, green: 0.97, blue: 0.75, alpha: 1)
    static let dinoMouth = NSColor(calibratedRed: 0.67, green: 0.86, blue: 0.38, alpha: 1)
    static let dinoDark = NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.16, alpha: 1)
    static let monster = NSColor(calibratedRed: 0.38, green: 0.54, blue: 0.91, alpha: 1)
    static let monsterLight = NSColor(calibratedRed: 0.86, green: 0.90, blue: 0.99, alpha: 1)
    static let monsterMouth = NSColor(calibratedRed: 0.48, green: 0.61, blue: 0.94, alpha: 1)
    static let monsterDark = NSColor(calibratedRed: 0.15, green: 0.29, blue: 0.68, alpha: 1)
    static let pink = NSColor(calibratedRed: 0.96, green: 0.56, blue: 0.63, alpha: 1)
}

private func drawPaperShirt() {
    let outer = shirtPath(inset: 0)
    fillPaper(outer, color: Paper.cream, seed: 11, grain: 175)

    let inner = shirtPath(inset: 5)
    fillPaper(inner, color: Paper.mustard, seed: 19, grain: 150)

    let neck = NSBezierPath()
    neck.move(to: NSPoint(x: 52, y: 93))
    neck.curve(to: NSPoint(x: 70, y: 80), controlPoint1: NSPoint(x: 55, y: 82), controlPoint2: NSPoint(x: 62, y: 79))
    neck.curve(to: NSPoint(x: 89, y: 94), controlPoint1: NSPoint(x: 79, y: 79), controlPoint2: NSPoint(x: 86, y: 83))
    neck.lineWidth = 5
    neck.lineCapStyle = .round
    Paper.cream.setStroke()
    neck.stroke()

    let seam = NSBezierPath()
    seam.move(to: NSPoint(x: 42, y: 17))
    seam.curve(to: NSPoint(x: 98, y: 17), controlPoint1: NSPoint(x: 57, y: 13), controlPoint2: NSPoint(x: 83, y: 20))
    stroke(seam, Paper.mustardDark.withAlphaComponent(0.46), width: 1.2)

    drawTinyFace(x: 84, y: 76, ink: Paper.ink)
}

private func shirtPath(inset: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    if inset == 0 {
        path.move(to: NSPoint(x: 44, y: 101))
        path.curve(to: NSPoint(x: 70, y: 88), controlPoint1: NSPoint(x: 50, y: 94), controlPoint2: NSPoint(x: 59, y: 89))
        path.curve(to: NSPoint(x: 97, y: 101), controlPoint1: NSPoint(x: 83, y: 88), controlPoint2: NSPoint(x: 92, y: 94))
        path.line(to: NSPoint(x: 121, y: 91))
        path.line(to: NSPoint(x: 137, y: 65))
        path.line(to: NSPoint(x: 116, y: 49))
        path.line(to: NSPoint(x: 112, y: 57))
        path.line(to: NSPoint(x: 113, y: 5))
        path.curve(to: NSPoint(x: 27, y: 5), controlPoint1: NSPoint(x: 87, y: 1), controlPoint2: NSPoint(x: 52, y: 1))
        path.line(to: NSPoint(x: 28, y: 57))
        path.line(to: NSPoint(x: 24, y: 49))
        path.line(to: NSPoint(x: 3, y: 65))
        path.line(to: NSPoint(x: 19, y: 91))
    } else {
        path.move(to: NSPoint(x: 46, y: 94))
        path.curve(to: NSPoint(x: 70, y: 83), controlPoint1: NSPoint(x: 52, y: 88), controlPoint2: NSPoint(x: 60, y: 84))
        path.curve(to: NSPoint(x: 94, y: 94), controlPoint1: NSPoint(x: 81, y: 83), controlPoint2: NSPoint(x: 89, y: 88))
        path.line(to: NSPoint(x: 117, y: 85))
        path.line(to: NSPoint(x: 130, y: 66))
        path.line(to: NSPoint(x: 114, y: 55))
        path.line(to: NSPoint(x: 106, y: 65))
        path.line(to: NSPoint(x: 107, y: 11))
        path.curve(to: NSPoint(x: 33, y: 11), controlPoint1: NSPoint(x: 85, y: 8), controlPoint2: NSPoint(x: 54, y: 8))
        path.line(to: NSPoint(x: 34, y: 65))
        path.line(to: NSPoint(x: 26, y: 55))
        path.line(to: NSPoint(x: 10, y: 66))
        path.line(to: NSPoint(x: 23, y: 85))
    }
    path.close()
    return path
}

private func drawPaperHouse() {
    let outer = NSBezierPath()
    outer.move(to: NSPoint(x: 16, y: 9))
    outer.line(to: NSPoint(x: 124, y: 8))
    outer.line(to: NSPoint(x: 124, y: 57))
    outer.line(to: NSPoint(x: 105, y: 73))
    outer.line(to: NSPoint(x: 105, y: 98))
    outer.line(to: NSPoint(x: 90, y: 100))
    outer.line(to: NSPoint(x: 90, y: 85))
    outer.line(to: NSPoint(x: 70, y: 102))
    outer.line(to: NSPoint(x: 8, y: 59))
    outer.close()
    fillPaper(outer, color: Paper.cream, seed: 31, grain: 185)

    let body = NSBezierPath()
    body.move(to: NSPoint(x: 23, y: 14))
    body.line(to: NSPoint(x: 117, y: 13))
    body.line(to: NSPoint(x: 117, y: 57))
    body.line(to: NSPoint(x: 70, y: 89))
    body.line(to: NSPoint(x: 23, y: 57))
    body.close()
    fillPaper(body, color: Paper.sage, seed: 37, grain: 145)

    let roof = NSBezierPath()
    roof.move(to: NSPoint(x: 14, y: 58))
    roof.line(to: NSPoint(x: 70, y: 96))
    roof.line(to: NSPoint(x: 127, y: 58))
    roof.line(to: NSPoint(x: 118, y: 48))
    roof.line(to: NSPoint(x: 70, y: 81))
    roof.line(to: NSPoint(x: 22, y: 49))
    roof.close()
    fillPaper(roof, color: Paper.tomato, seed: 41, grain: 120)

    let chimney = roundedRect(NSRect(x: 94, y: 82, width: 9, height: 16), radius: 2)
    fillPaper(chimney, color: Paper.tomato, seed: 43, grain: 24)

    drawTinyFace(x: 97, y: 71, ink: Paper.ink)
}

private func drawPaperApple() {
    let outer = applePath(expanded: true)
    fillPaper(outer, color: Paper.cream, seed: 53, grain: 190)

    let inner = applePath(expanded: false)
    fillPaper(inner, color: Paper.tomato, seed: 59, grain: 155)

    let stemUnderlay = NSBezierPath()
    stemUnderlay.move(to: NSPoint(x: 69, y: 88))
    stemUnderlay.curve(to: NSPoint(x: 76, y: 102), controlPoint1: NSPoint(x: 69, y: 94), controlPoint2: NSPoint(x: 73, y: 99))
    stroke(stemUnderlay, Paper.cream, width: 8)
    stroke(stemUnderlay, Paper.ink, width: 3.5)

    let leafOuter = NSBezierPath()
    leafOuter.move(to: NSPoint(x: 74, y: 96))
    leafOuter.curve(to: NSPoint(x: 104, y: 97), controlPoint1: NSPoint(x: 84, y: 108), controlPoint2: NSPoint(x: 98, y: 106))
    leafOuter.curve(to: NSPoint(x: 74, y: 96), controlPoint1: NSPoint(x: 97, y: 84), controlPoint2: NSPoint(x: 83, y: 86))
    leafOuter.close()
    Paper.cream.setFill()
    leafOuter.fill()

    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: 78, y: 96))
    leaf.curve(to: NSPoint(x: 99, y: 97), controlPoint1: NSPoint(x: 86, y: 104), controlPoint2: NSPoint(x: 95, y: 103))
    leaf.curve(to: NSPoint(x: 78, y: 96), controlPoint1: NSPoint(x: 94, y: 89), controlPoint2: NSPoint(x: 85, y: 90))
    leaf.close()
    fillPaper(leaf, color: Paper.leaf, seed: 61, grain: 30)

    let shine = NSBezierPath()
    shine.move(to: NSPoint(x: 34, y: 67))
    shine.curve(to: NSPoint(x: 30, y: 55), controlPoint1: NSPoint(x: 31, y: 64), controlPoint2: NSPoint(x: 29, y: 59))
    stroke(shine, Paper.cream.withAlphaComponent(0.86), width: 3.0)

    drawTinyFace(x: 95, y: 77, ink: Paper.ink)
}

private func drawNoteArtwork(_ artwork: NSImage?, upsideDown: Bool = false) {
    guard let artwork else { return }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    if upsideDown {
        // Rotate the artwork only; note text stays upright on the yellow handle.
        let transform = NSAffineTransform()
        transform.translateX(by: 140, yBy: 104)
        transform.rotate(byDegrees: 180)
        transform.concat()
    }
    let scale = min(140 / artwork.size.width, 104 / artwork.size.height)
    let size = NSSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
    NSGraphicsContext.current?.imageInterpolation = .high
    artwork.draw(in: NSRect(x: (140 - size.width) / 2, y: (104 - size.height) / 2,
                           width: size.width, height: size.height))
}

private enum NoteArtworkResources {
    static let tomato = load("tomato")
    static let bear = load("bear")
    static let tote = load("tote")
    static let paperbag = load("paperbag")
    static let clock = load("clock")
    static let screwdriver = load("screwdriver")
    static let bucket = load("bucket")
    static let sweetbaby = load("sweetbaby")
    static let kissbaby = load("kissbaby")
    static let wangyibo = load("wangyibo")

    private static func load(_ name: String) -> NSImage? {
        // The app bundle uses standard Resources; swift run uses its resource bundle.
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        #endif
        assertionFailure("Missing \(name) note artwork")
        return nil
    }
}

private func drawPaperDino() {
    drawDinoSpikes()

    let head = domePath()
    fillPaper(head, color: Paper.dino, seed: 93, grain: 220)
    stroke(head, Paper.dinoDark.withAlphaComponent(0.40), width: 1.1)

    // The reference uses soft, irregular oval spots instead of hard graphic dots.
    fillPaper(NSBezierPath(ovalIn: NSRect(x: 18, y: 77, width: 15, height: 10)), color: Paper.dinoDark, seed: 95, grain: 18)
    fillPaper(NSBezierPath(ovalIn: NSRect(x: 24, y: 57, width: 10, height: 16)), color: Paper.dinoDark, seed: 97, grain: 15)
    fillPaper(NSBezierPath(ovalIn: NSRect(x: 34, y: 83, width: 12, height: 8)), color: Paper.dinoLight, seed: 99, grain: 12)
    fillPaper(NSBezierPath(ovalIn: NSRect(x: 106, y: 72, width: 12, height: 17)), color: Paper.dinoDark, seed: 101, grain: 17)

    let note = roundedRect(NSRect(x: 9, y: 6, width: 122, height: 45), radius: 8)
    fillPaper(note, color: Paper.dinoLight, seed: 103, grain: 165)
    stroke(note, Paper.dinoDark.withAlphaComponent(0.35), width: 1.0)

    let mouth = roundedRect(NSRect(x: 8, y: 43, width: 124, height: 18), radius: 6)
    fillPaper(mouth, color: Paper.dinoMouth, seed: 105, grain: 70)
    stroke(mouth, Paper.dinoDark.withAlphaComponent(0.42), width: 1.0)
    drawTeeth(y: 57, color: Paper.cream)

    drawDinoEye(center: NSPoint(x: 54, y: 73), seed: 107)
    drawDinoEye(center: NSPoint(x: 84, y: 69), seed: 109)
    fillPaper(NSBezierPath(ovalIn: NSRect(x: 28, y: 56, width: 18, height: 9)), color: Paper.pink, seed: 111, grain: 12)
    fillPaper(NSBezierPath(ovalIn: NSRect(x: 96, y: 55, width: 18, height: 9)), color: Paper.pink, seed: 113, grain: 12)
}

private func drawPaperMonster() {
    let head = domePath()
    fillPaper(head, color: Paper.monster, seed: 115, grain: 220)
    stroke(head, Paper.monsterDark.withAlphaComponent(0.35), width: 1.1)

    let star = NSBezierPath()
    for index in 0..<10 {
        let angle = CGFloat(index) * .pi / 5 - .pi / 2
        let radius: CGFloat = index.isMultiple(of: 2) ? 12 : 5.5
        let point = NSPoint(x: 99 + cos(angle) * radius, y: 80 + sin(angle) * radius)
        if index == 0 { star.move(to: point) } else { star.line(to: point) }
    }
    star.close()
    fillPaper(star, color: Paper.monsterDark, seed: 117, grain: 18)
    fillPaper(NSBezierPath(ovalIn: NSRect(x: 18, y: 65, width: 11, height: 17)), color: Paper.monsterDark, seed: 119, grain: 12)
    fillPaper(NSBezierPath(ovalIn: NSRect(x: 114, y: 67, width: 6, height: 6)), color: Paper.monsterDark, seed: 121, grain: 8)
    fillPaper(NSBezierPath(ovalIn: NSRect(x: 121, y: 58, width: 5, height: 5)), color: Paper.monsterDark, seed: 123, grain: 8)

    let note = roundedRect(NSRect(x: 9, y: 6, width: 122, height: 45), radius: 8)
    fillPaper(note, color: Paper.monsterLight, seed: 125, grain: 165)
    stroke(note, Paper.monsterDark.withAlphaComponent(0.28), width: 1.0)

    let mouth = roundedRect(NSRect(x: 8, y: 43, width: 124, height: 18), radius: 6)
    fillPaper(mouth, color: Paper.monsterMouth, seed: 127, grain: 70)
    stroke(mouth, Paper.monsterDark.withAlphaComponent(0.36), width: 1.0)
    drawTeeth(y: 57, color: Paper.cream)

    drawMonsterEye(center: NSPoint(x: 52, y: 74), wink: false)
    drawMonsterEye(center: NSPoint(x: 85, y: 72), wink: true)
    let cheek = NSBezierPath(ovalIn: NSRect(x: 24, y: 58, width: 13, height: 7))
    fillPaper(cheek, color: Paper.pink, seed: 129, grain: 10)
}

private func drawDinoEye(center: NSPoint, seed: UInt32) {
    fillPaper(NSBezierPath(ovalIn: NSRect(x: center.x - 17, y: center.y - 15, width: 34, height: 31)),
              color: Paper.cream, seed: seed, grain: 24)
    fillPaper(NSBezierPath(ovalIn: NSRect(x: center.x - 8, y: center.y - 9, width: 17, height: 19)),
              color: Paper.ink, seed: seed + 1, grain: 12)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 3, y: center.y + 4, width: 5, height: 5)).fill()
}

private func drawMonsterEye(center: NSPoint, wink: Bool) {
    if wink {
        fillPaper(NSBezierPath(ovalIn: NSRect(x: center.x - 17, y: center.y - 15, width: 34, height: 31)),
                  color: Paper.cream, seed: 133, grain: 24)
        let line = NSBezierPath()
        line.move(to: NSPoint(x: center.x + 9, y: center.y + 8))
        line.line(to: NSPoint(x: center.x - 4, y: center.y))
        line.line(to: NSPoint(x: center.x + 9, y: center.y - 8))
        stroke(line, Paper.ink, width: 5)
        return
    }
    fillPaper(NSBezierPath(ovalIn: NSRect(x: center.x - 17, y: center.y - 15, width: 34, height: 31)),
              color: Paper.cream, seed: 129, grain: 24)
    fillPaper(NSBezierPath(ovalIn: NSRect(x: center.x - 8, y: center.y - 9, width: 17, height: 19)),
              color: Paper.ink, seed: 131, grain: 12)
}

private func drawTeeth(y: CGFloat, color: NSColor) {
    let teeth = NSBezierPath()
    teeth.move(to: NSPoint(x: 23, y: y))
    teeth.line(to: NSPoint(x: 117, y: y))
    for x in stride(from: CGFloat(23), through: CGFloat(103), by: CGFloat(20)) {
        teeth.curve(to: NSPoint(x: x + 10, y: y - 9),
                    controlPoint1: NSPoint(x: x + 3, y: y - 1),
                    controlPoint2: NSPoint(x: x + 6, y: y - 9))
        teeth.curve(to: NSPoint(x: x + 20, y: y),
                    controlPoint1: NSPoint(x: x + 14, y: y - 9),
                    controlPoint2: NSPoint(x: x + 17, y: y - 1))
    }
    teeth.close()
    color.setFill()
    teeth.fill()
}

private func domePath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 9, y: 47))
    path.line(to: NSPoint(x: 9, y: 64))
    path.curve(to: NSPoint(x: 70, y: 101), controlPoint1: NSPoint(x: 10, y: 90), controlPoint2: NSPoint(x: 34, y: 101))
    path.curve(to: NSPoint(x: 131, y: 64), controlPoint1: NSPoint(x: 106, y: 101), controlPoint2: NSPoint(x: 130, y: 90))
    path.line(to: NSPoint(x: 131, y: 47))
    path.close()
    return path
}

private func drawDinoSpikes() {
    let spikes: [(CGFloat, CGFloat, CGFloat)] = [
        (35, 83, 24), (61, 88, 27), (88, 85, 22), (113, 79, 18),
        (7, 64, 19), (133, 64, 18)
    ]
    for (x, base, height) in spikes {
        let spike = NSBezierPath()
        spike.move(to: NSPoint(x: x - 12, y: base))
        spike.curve(to: NSPoint(x: x, y: base + height),
                    controlPoint1: NSPoint(x: x - 8, y: base + 3),
                    controlPoint2: NSPoint(x: x - 4, y: base + height - 2))
        spike.curve(to: NSPoint(x: x + 12, y: base),
                    controlPoint1: NSPoint(x: x + 5, y: base + height - 2),
                    controlPoint2: NSPoint(x: x + 9, y: base + 3))
        spike.close()
        fillPaper(spike, color: Paper.dinoDark, seed: UInt32(x + base), grain: 24)
    }
}

private func applePath(expanded: Bool) -> NSBezierPath {
    let d: CGFloat = expanded ? 5 : 0
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 69, y: 86 + d))
    path.curve(to: NSPoint(x: 28 - d, y: 86 + d), controlPoint1: NSPoint(x: 51, y: 101 + d), controlPoint2: NSPoint(x: 34, y: 95 + d))
    path.curve(to: NSPoint(x: 16 - d, y: 44), controlPoint1: NSPoint(x: 12 - d, y: 74), controlPoint2: NSPoint(x: 11 - d, y: 57))
    path.curve(to: NSPoint(x: 48, y: 6 - d), controlPoint1: NSPoint(x: 21 - d, y: 23), controlPoint2: NSPoint(x: 35, y: 6 - d))
    path.curve(to: NSPoint(x: 70, y: 12 - d), controlPoint1: NSPoint(x: 58, y: 5 - d), controlPoint2: NSPoint(x: 64, y: 11 - d))
    path.curve(to: NSPoint(x: 92, y: 6 - d), controlPoint1: NSPoint(x: 77, y: 11 - d), controlPoint2: NSPoint(x: 83, y: 5 - d))
    path.curve(to: NSPoint(x: 124 + d, y: 44), controlPoint1: NSPoint(x: 105, y: 6 - d), controlPoint2: NSPoint(x: 119 + d, y: 24))
    path.curve(to: NSPoint(x: 111 + d, y: 86 + d), controlPoint1: NSPoint(x: 129 + d, y: 58), controlPoint2: NSPoint(x: 127 + d, y: 75))
    path.curve(to: NSPoint(x: 69, y: 86 + d), controlPoint1: NSPoint(x: 104, y: 95 + d), controlPoint2: NSPoint(x: 87, y: 101 + d))
    path.close()
    return path
}

private func fillPaper(_ path: NSBezierPath, color: NSColor, seed: UInt32, grain: Int) {
    color.setFill()
    path.fill()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    var random = PaperRandom(seed: seed)
    let bounds = path.bounds
    for index in 0..<grain {
        let x = bounds.minX + random.next() * bounds.width
        let y = bounds.minY + random.next() * bounds.height
        let diameter = 0.25 + random.next() * 0.65
        let alpha: CGFloat = 0.018 + random.next() * 0.032
        let speck = index.isMultiple(of: 3)
            ? NSColor.white.withAlphaComponent(alpha)
            : NSColor.black.withAlphaComponent(alpha)
        speck.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: diameter, height: diameter)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

private struct PaperRandom {
    var state: UInt32
    init(seed: UInt32) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 1_664_525 &+ 1_013_904_223
        return CGFloat(state & 0x00FF_FFFF) / CGFloat(0x0100_0000)
    }
}

private func drawTinyFace(x: CGFloat, y: CGFloat, ink: NSColor) {
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 5, y: y, width: 2.5, height: 3.2)).fill()
    NSBezierPath(ovalIn: NSRect(x: x + 4, y: y + 0.4, width: 2.5, height: 3.2)).fill()
    let mouth = NSBezierPath()
    mouth.move(to: NSPoint(x: x - 0.5, y: y - 2))
    mouth.curve(to: NSPoint(x: x + 3, y: y - 1.5), controlPoint1: NSPoint(x: x + 0.5, y: y - 4), controlPoint2: NSPoint(x: x + 2, y: y - 3.5))
    stroke(mouth, ink, width: 1.1)
}

private func drawCat(x: CGFloat, y: CGFloat, scale: CGFloat) {
    var transform = AffineTransform(translationByX: x, byY: y)
    transform.scale(x: scale, y: scale)

    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 8, y: 12))
    tail.curve(to: NSPoint(x: -2, y: 3), controlPoint1: NSPoint(x: 0, y: 12), controlPoint2: NSPoint(x: -8, y: 8))
    tail.transform(using: transform)
    stroke(tail, Paper.cream, width: 10 * scale)
    stroke(tail, Paper.ink, width: 6 * scale)

    let body = NSBezierPath(roundedRect: NSRect(x: 7, y: 0, width: 17, height: 27), xRadius: 8, yRadius: 8)
    body.transform(using: transform)
    body.lineWidth = 6 * scale
    Paper.cream.setStroke()
    body.stroke()
    Paper.ink.setFill()
    body.fill()

    let head = NSBezierPath(ovalIn: NSRect(x: 3, y: 21, width: 24, height: 19))
    head.transform(using: transform)
    head.lineWidth = 6 * scale
    Paper.cream.setStroke()
    head.stroke()
    Paper.ink.setFill()
    head.fill()

    let leftEar = triangle(NSPoint(x: 6, y: 35), NSPoint(x: 10, y: 45), NSPoint(x: 15, y: 36), transform: transform)
    let rightEar = triangle(NSPoint(x: 17, y: 36), NSPoint(x: 23, y: 45), NSPoint(x: 25, y: 34), transform: transform)
    for ear in [leftEar, rightEar] {
        ear.lineWidth = 5 * scale
        Paper.cream.setStroke()
        ear.stroke()
        Paper.ink.setFill()
        ear.fill()
    }

    Paper.blue.setFill()
    let leftEye = NSBezierPath(ovalIn: NSRect(x: 9, y: 29, width: 4, height: 5))
    let rightEye = NSBezierPath(ovalIn: NSRect(x: 18, y: 29, width: 4, height: 5))
    leftEye.transform(using: transform)
    rightEye.transform(using: transform)
    leftEye.fill()
    rightEye.fill()
    Paper.cream.setFill()
    for eye in [leftEye, rightEye] {
        let b = eye.bounds
        NSBezierPath(ovalIn: NSRect(x: b.minX + b.width * 0.45, y: b.minY + b.height * 0.52,
                                    width: 1.2 * scale, height: 1.2 * scale)).fill()
    }
    Paper.blush.setFill()
    NSBezierPath(ovalIn: NSRect(x: x + 14 * scale, y: y + 26 * scale,
                                width: 2.2 * scale, height: 1.8 * scale)).fill()
}

private func triangle(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint,
                      transform: AffineTransform) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: a)
    path.line(to: b)
    path.line(to: c)
    path.close()
    path.transform(using: transform)
    return path
}

private func stroke(_ path: NSBezierPath, _ color: NSColor, width: CGFloat) {
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

private func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawNoteText(_ text: String, in rect: NSRect, color: NSColor, maximumFontSize: CGFloat = 13.5,
                  alignment: NSTextAlignment = .center) {
    let preferred = containsCJK(text) ? "Hannotate SC" : "Chalkboard SE"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = 0.5
    var size = maximumFontSize
    var attributes: [NSAttributedString.Key: Any] = [:]
    // Fit wrapped lines, but keep a readable lower limit for very long notes.
    while true {
        let rounded = NSFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor.withDesign(.rounded)
        let font = NSFont(name: preferred, size: size)
            ?? rounded.flatMap { NSFont(descriptor: $0, size: size) }
            ?? NSFont.systemFont(ofSize: size, weight: .semibold)
        attributes = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: attributes)
        if ceil(bounds.height) <= rect.height || size <= 8.5 { break }
        size = max(8.5, size - 0.5)
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSBezierPath(rect: rect).addClip()
    (text as NSString).draw(
        with: rect,
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
        attributes: attributes)
}

private func containsCJK(_ text: String) -> Bool {
    text.unicodeScalars.contains {
        (0x3400...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value)
    }
}
