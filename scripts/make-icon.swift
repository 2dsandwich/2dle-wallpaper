import AppKit
import CoreText

// The icon, in the dark style of a current macOS icon: a nearly black tile with the light caught along its edge, and
// the name on it lit from above.
//   swift scripts/make-icon.swift <font> <iconset folder> [<website assets folder>]
// writes the app's icon at every size macOS asks for (the build script makes the .icns from them) and, given the
// website's folder as well, its two pictures of it: app-icon.png (512: the tile with room round it for its shadow,
// for the download modules) and icon.png (256: the tile edge to edge, for the browser's tab).

let fontURL = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func grey(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [white, white, white, alpha])!
}
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

/// The tile's outline: rounder into its corners than a rounded rectangle, as the system's icons are.
func tile(_ box: CGRect) -> CGPath {
    let path = CGMutablePath()
    let power: CGFloat = 4.4
    let steps = 720
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let x = pow(abs(cos(angle)), 2 / power) * (cos(angle) < 0 ? -1 : 1)
        let y = pow(abs(sin(angle)), 2 / power) * (sin(angle) < 0 ? -1 : 1)
        let point = CGPoint(x: box.midX + x * box.width / 2, y: box.midY + y * box.height / 2)
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

/// Draws the icon into `box` of a picture `pixels` square, with or without the shadow it throws.
/// (`brief`: only the first letter of the name, which is all that can be read at the smallest sizes.)
func draw(pixels: Int, box: CGRect, shadow: Bool, brief: Bool = false) -> Data {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let side = box.width
    let outline = tile(box)
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.022), blur: side * 0.045, color: grey(0, 0.38))
        ctx.addPath(outline)
        ctx.setFillColor(grey(0.1))
        ctx.fillPath()
        ctx.restoreGState()
    }
    // The tile: nearly black, a shade lighter towards the top.
    ctx.saveGState()
    ctx.addPath(outline)
    ctx.clip()
    // A rainbow from the bottom left corner to the top right, with a little sheen over the top.
    ctx.drawLinearGradient(
        gradient([
            (rgb(0.93, 0.13, 0.25), 0), (rgb(0.98, 0.42, 0.13), 0.2), (rgb(0.98, 0.75, 0.12), 0.36),
            (rgb(0.22, 0.78, 0.40), 0.52), (rgb(0.10, 0.62, 0.95), 0.7), (rgb(0.33, 0.30, 0.93), 0.86),
            (rgb(0.62, 0.22, 0.86), 1),
        ]),
        start: CGPoint(x: box.minX, y: box.minY), end: CGPoint(x: box.maxX, y: box.maxY), options: [])
    ctx.drawLinearGradient(
        gradient([(grey(1, 0.22), 0), (grey(1, 0), 0.5), (grey(0, 0.10), 1)]),
        start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])
    // The light along its edge: brightest at the top left and the bottom right, as on glass.
    ctx.addPath(outline)
    // (Never thinner than a pixel's worth inside the tile, or the small sizes lose it.)
    ctx.setLineWidth(max(side * 0.02, 2))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(grey(1, 0.56), 0), (grey(1, 0.17), 0.42), (grey(1, 0.13), 0.62), (grey(1, 0.38), 1)]),
        start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [])
    ctx.restoreGState()

    // The name: lit from above, so it runs from white down to a cool grey, with a little of its own light round it.
    let font = CTFontCreateWithName("ComforterBrush-Regular" as CFString, side * (brief ? 0.9 : 0.43), nil)
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: brief ? "2" : "2dle", attributes: [.font: font, .foregroundColor: NSColor.white]))
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let origin = CGPoint(x: box.midX - ink.midX, y: box.midY - ink.midY)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.012), blur: side * 0.04, color: grey(0, 0.38))
    ctx.textPosition = origin
    ctx.setFillColor(grey(1, 0.5))
    CTLineDraw(line, ctx)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.textPosition = origin
    ctx.setTextDrawingMode(.clip)
    CTLineDraw(line, ctx)
    ctx.drawLinearGradient(
        gradient([(grey(1), 0), (grey(0.97), 0.5), (grey(0.90), 1)]),
        start: CGPoint(x: box.midX, y: origin.y + ink.maxY), end: CGPoint(x: box.midX, y: origin.y + ink.minY),
        options: [])
    ctx.restoreGState()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        // A single brush letter remains legible at menu and Dock sizes.
        let png = draw(
            pixels: pixels, box: CGRect(x: 0, y: 0, width: pixels, height: pixels), shadow: false, brief: pixels < 128)
        try png.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
if CommandLine.arguments.count > 3 {
    let web = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    // (In the modules the tile is 414 of the picture's 512 across, a little above the middle, with its shadow below it.)
    try draw(pixels: 512, box: CGRect(x: 49, y: 57, width: 414, height: 414), shadow: true).write(
        to: web.appendingPathComponent("app-icon.png"))
    try draw(pixels: 256, box: CGRect(x: 0, y: 0, width: 256, height: 256), shadow: false).write(
        to: web.appendingPathComponent("icon.png"))
}
