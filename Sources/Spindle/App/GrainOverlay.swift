import AppKit

/// Film grain that holds still. The renderer's own grain is redrawn every frame, which on a
/// wallpaper reads as the picture crawling; a print has its grain where it is. So one tile of
/// noise, dark specks and light, is laid over the picture and left alone: as dense and as
/// coarse as the film in the chosen camera is grainy.
final class GrainOverlay: NSView {
    private static var made: CGImage?
    private static let side = 512
    private var laid = false
    private var laidFor: (size: CGSize, scale: CGFloat) = (.zero, 0)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        layer?.isOpaque = false
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// How much of the grain shows: 0 none, two thirds the film's own, 1 half as much again.
    var amount: Float = 2.0 / 3 {
        didSet {
            layer?.opacity = amount
            isHidden = amount <= 0
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        if laid { lay() }
    }

    func lay() {
        guard let layer else { return }
        let scale = window?.backingScaleFactor ?? 2
        if laid, laidFor.size == bounds.size, laidFor.scale == scale { return }
        laid = true
        laidFor = (bounds.size, scale)
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let tile = Self.tile() else { return }
        // (One noise pixel to one pixel of the display, repeated across it.)
        let step = CGFloat(Self.side) / scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var y: CGFloat = 0
        while y < bounds.height {
            var x: CGFloat = 0
            while x < bounds.width {
                let cell = CALayer()
                cell.frame = CGRect(x: x, y: y, width: step, height: step)
                cell.contents = tile
                cell.contentsScale = scale
                cell.magnificationFilter = .nearest
                cell.minificationFilter = .nearest
                layer.addSublayer(cell)
                x += step
            }
            y += step
        }
        CATransaction.commit()
    }

    /// Specks of black and of white, each as opaque as it is far from grey: laid over a picture
    /// they darken and lighten it by turns and leave its overall tone where it was.
    private static func tile() -> CGImage? {
        if let made { return made }
        guard FilmLook.grain > 0.005 else { return nil }
        let n = side
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func unit() -> Float {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Float(state >> 40) / Float(1 << 24)
        }
        var field = [Float](repeating: 0, count: n * n)
        for i in 0..<(n * n) { field[i] = unit() + unit() + unit() - 1.5 }
        // Coarser films: the specks clump. (Averaged with their neighbours, wrapping at the edges so the tile repeats.)
        let reach = max(0, Int(((FilmLook.grainSize - 1.4) / 1.1).rounded()))
        if reach > 0 {
            var across = field
            for y in 0..<n {
                for x in 0..<n {
                    var sum: Float = 0
                    for d in -reach...reach { sum += field[y * n + (x + d + n) % n] }
                    across[y * n + x] = sum
                }
            }
            for y in 0..<n {
                for x in 0..<n {
                    var sum: Float = 0
                    for d in -reach...reach { sum += across[((y + d + n) % n) * n + x] }
                    field[y * n + x] = sum / Float(2 * reach + 1)  // (divided once, not twice: keeps the specks as strong as they were)
                }
            }
        }
        // (Made at one and a half times the film's own grain: `amount` then shows two thirds of it for the usual look, or all of it.)
        let strength = Float(FilmLook.grain) * 0.56 * 1.5
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let v = field[i]
            let alpha = min(abs(v) * strength, 0.9)
            let level = UInt8((v > 0 ? alpha : 0) * 255)
            pixels[i * 4] = level
            pixels[i * 4 + 1] = level
            pixels[i * 4 + 2] = level
            pixels[i * 4 + 3] = UInt8(alpha * 255)
        }
        let image = pixels.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(
                data: raw.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .makeImage()
        }
        made = image
        return image
    }
}
