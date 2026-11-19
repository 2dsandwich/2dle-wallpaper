import AppKit
import SceneKit

/// A continuous inscription on the smooth vinyl collar surrounding the artwork.
enum RecordDeadwax {
    static let outerRadius: Float = 0.063
    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 64  // (a few albums' worth of labels: nothing is kept without a limit)
        return cache
    }()

    static func neutralUnlockLabel(for style: RecordStyle) -> String {
        style == .black ? "UNL START" : "LOCKED"
    }

    static func text(for style: RecordStyle, side: Int = 1, unlockLabel: String? = nil) -> String {
        let label = unlockLabel ?? Collection.shared.deadwaxUnlockLabel(for: style)
        return
            "2dle · \(style.catalogueID) · SIDE \(max(side, 1)) · \(style.rarity.inscription.uppercased()) · \(style.title.uppercased()) · \(label) · "
    }

    static func node(style: RecordStyle, side: Int = 1, unlockLabel: String? = nil) -> SCNNode {
        // (Ink pressed into the vinyl, lit as the label beside it is, a shade under white. It was drawn unlit in full white
        // so it could be read in any light, and in a dark room it glowed as a ring round the label: owner, 2026-10-18.)
        let material = Mat.print(image(style: style, side: side, unlockLabel: unlockLabel), roughness: 0.62)
        material.lightingModel = .physicallyBased
        material.metalness.contents = 0.0
        material.multiply.contents = rgb(0.62, 0.61, 0.58)
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.diffuse.minificationFilter = .linear
        material.diffuse.magnificationFilter = .linear
        material.diffuse.maxAnisotropy = 16
        material.writesToDepthBuffer = false
        let node = SCNNode(Mesh.disc(radius: outerRadius, segments: 128), material: material, name: "deadwax")
        node.simdPosition.y = Dim.recordThickness + 0.00022
        node.castsShadow = false
        node.renderingOrder = 4
        return node
    }

    private static func image(style: RecordStyle, side: Int, unlockLabel: String?) -> CGImage {
        let text = text(for: style, side: side, unlockLabel: unlockLabel)
        let key = text as NSString
        if let image = cache.object(forKey: key) { return image }
        let glyphs = Array(text)
        let drawn = Tex.draw(width: 2048, height: 2048) { context, rect in
            // A matte collar makes the full glyph height readable on every vinyl material.
            context.addEllipse(in: rect.insetBy(dx: rect.width * 0.008, dy: rect.height * 0.008))
            let innerDiameter = rect.width * CGFloat(0.0501 / outerRadius)
            context.addEllipse(
                in: CGRect(
                    x: rect.midX - innerDiameter / 2, y: rect.midY - innerDiameter / 2,
                    width: innerDiameter, height: innerDiameter))
            context.setFillColor(Tex.rgb(0.025, 0.024, 0.022))
            context.drawPath(using: .eoFill)
            let radius = rect.width / 2 * CGFloat(0.0565 / outerRadius)
            // Equal angular advances, including spaces and separators, close the ring
            // with exactly the same spacing at its start and end.
            let advance = 2 * CGFloat.pi / CGFloat(glyphs.count)
            let fontSize = min(94, radius * advance * 0.98)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor(white: 1, alpha: 1),
                .strokeColor: NSColor(white: 0.03, alpha: 0.85),
                .strokeWidth: -3,
            ]
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            for (index, glyph) in glyphs.enumerated() {
                let angle = CGFloat.pi / 2 - CGFloat(index) * advance
                let character = String(glyph) as NSString
                let size = character.size(withAttributes: attributes)
                context.saveGState()
                context.translateBy(x: rect.midX + cos(angle) * radius, y: rect.midY + sin(angle) * radius)
                context.rotate(by: angle - .pi / 2)
                character.draw(
                    in: CGRect(
                        x: -size.width / 2, y: -size.height / 2,
                        width: size.width, height: size.height), withAttributes: attributes)
                context.restoreGState()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        // (Out of the app's memory: see `Tex.settled`.)
        let image = Tex.settled(drawn)
        cache.setObject(image, forKey: key)
        return image
    }
}
