import AppKit
import Metal
import SceneKit

/// The small scene pictures the menu shows, loaded from the stills made when the app is built.
final class SceneThumbnails: ObservableObject {
    static let shared = SceneThumbnails()
    @Published var images: [ScenePreset: NSImage] = [:]

    init() {
        for preset in ScenePreset.allCases {
            if let image = Resources.image("menu-previews/scene-\(preset.rawValue).jpg") {
                images[preset] = NSImage(cgImage: image, size: NSSize(width: 400, height: 250))
            }
        }
    }

    /// A still of one scene as the menu shows it.
    static func scene(
        _ preset: ScenePreset, turntable: TurntableStyle, clock: ClockStyle?, device: MTLDevice,
        size: CGSize = CGSize(width: 400, height: 250),
        snapshot: Stage.PresentationSnapshot? = nil
    ) -> NSImage {
        let art = AlbumArt(id: "preview", image: Tex.previewCover())
        let history = (1...5).map { AlbumArt(id: "builtin-\($0)", image: Tex.placeholderCover($0)) }
        let stage = Stage(
            preset: preset, current: art, history: history, turntable: turntable, clock: clock,
            presentationSnapshot: snapshot ?? Stage.PresentationSnapshot(wearLevels: [:]),
            daylight: false)
        stage.setFraming(
            Settings.framing(topDown: preset.isTopDown), aspect: Float(size.width / size.height), animated: false)
        stage.setPlayback(isPlaying: true, position: 60, duration: 200)
        stage.settle()
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = stage.scene
        renderer.pointOfView = stage.cameraNode
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
}

extension SceneThumbnails {
    /// One record style seen from straight above on a dark mat.
    static func record(
        _ style: RecordStyle, device: MTLDevice, unlockLabel: String? = nil, clear: Bool = false, art: AlbumArt? = nil
    ) -> NSImage {
        let scene = SCNScene()
        scene.background.contents = clear ? NSColor.clear : NSColor(white: 0.07, alpha: 1)
        scene.lightingEnvironment.contents = Resources.url("hdri/photo_studio_loft_hall.hdr")
        scene.lightingEnvironment.intensity = 1.1
        // A grey mat underneath, so the clear and frosted ones have something to show through to.
        if !clear {
            SCNNode(
                Mesh.disc(radius: Dim.recordRadius * 0.985, segments: 64),
                material: Mat.pbr(NSColor(white: 0.20, alpha: 1), roughness: 0.9)
            ).at(0, -0.0006, 0).adding(to: scene.rootNode)
        }
        let record = Props.record(
            label: Tex.plainLabel(ring: style.rarity.colour), vinyl: Mat.vinyl(look: VinylLook.make(style, art: art)),
            style: style, unlockLabel: unlockLabel)
        scene.rootNode.addChildNode(record)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 700
        sun.simdEulerAngles = SIMD3(-1.05, -0.5, 0)
        scene.rootNode.addChildNode(sun)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = Double(Dim.recordRadius) * 1.06
        camera.camera?.wantsHDR = true
        camera.camera?.zNear = 0.05
        camera.simdPosition = SIMD3(0, 0.6, 0)
        camera.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        return renderer.snapshot(atTime: 0, with: CGSize(width: 1600, height: 1600), antialiasingMode: .multisampling4X)
    }
}
