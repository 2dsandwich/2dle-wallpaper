import AppKit
import Metal
import SceneKit
import SwiftUI

/// Renders the small scene previews for the picker, off the main thread.
final class SceneThumbnails: ObservableObject {
    static let shared = SceneThumbnails()
    @Published var images: [ScenePreset: NSImage] = [:]
    /// The see-through pressings again, photographed over nothing, for when one is held up on its own.
    @Published var clearRecords: [RecordStyle: NSImage] = [:]
    /// The album the cover-coloured records were last drawn for.
    fileprivate var tintedFor: String?
    fileprivate var tintArt: AlbumArt?
    /// Each clock by itself on nothing, drawn the first time it is wanted.
    @Published var clearClocks: [ClockStyle: NSImage] = [:]
    func drawClearClock(_ style: ClockStyle) {
        guard clearClocks[style] == nil else { return }
        queue.async {
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            let image = DeskClock.preview(style, device: device, clear: true)
            DispatchQueue.main.async { self.clearClocks[style] = image }
        }
    }
    @Published var decks: [TurntableStyle: NSImage] = [:]
    @Published var clocks: [ClockStyle: NSImage] = [:]
    @Published var records: [RecordStyle: NSImage] = [:]
    private let queue = DispatchQueue(label: "spindle.thumbnails", qos: .userInitiated)
    private var renderedFor: String?
    private var recordLabels: [RecordStyle: String] = [:]
    private var recordRenderGeneration: [RecordStyle: UInt64] = [:]
    private var sceneRenderGeneration: UInt64 = 0

    init() {
        // These are rendered at build time, so the Records grid never waits for room rendering.
        var loadedRecords: [RecordStyle: NSImage] = [:]
        var loadedLabels: [RecordStyle: String] = [:]
        for style in RecordStyle.allCases {
            if let clear = Resources.image("record-previews/\(style.rawValue)-clear.png") {
                clearRecords[style] = NSImage(cgImage: clear, size: NSSize(width: 480, height: 480))
            }
            guard let image = Resources.image("record-previews/\(style.rawValue).png") else { continue }
            loadedRecords[style] = NSImage(cgImage: image, size: NSSize(width: 480, height: 480))
            loadedLabels[style] = RecordDeadwax.neutralUnlockLabel(for: style)
        }
        records = loadedRecords
        recordLabels = loadedLabels
        // The scene, turntable and clock pictures are stills too, made when the app is built: the
        // menu opens with all of them already there instead of drawing each room while you wait.
        for preset in ScenePreset.allCases {
            if let image = Resources.image("menu-previews/scene-\(preset.rawValue).jpg") {
                images[preset] = NSImage(cgImage: image, size: NSSize(width: 400, height: 250))
            }
        }
        for style in TurntableStyle.allCases {
            if let image = Resources.image("menu-previews/deck-\(style.rawValue).jpg") {
                decks[style] = NSImage(cgImage: image, size: NSSize(width: 400, height: 250))
            }
        }
        for style in ClockStyle.allCases {
            if let image = Resources.image("menu-previews/clock-\(style.rawValue).png") {
                clocks[style] = NSImage(cgImage: image, size: NSSize(width: 400, height: 250))
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

    /// A still of one turntable, close, from above.
    static func deck(
        _ style: TurntableStyle, device: MTLDevice, size: CGSize = CGSize(width: 400, height: 250),
        snapshot: Stage.PresentationSnapshot? = nil
    ) -> NSImage {
        let art = AlbumArt(id: "preview", image: Tex.previewCover())
        // (On the tatami: the plainest ground there is to see a turntable against.)
        let stage = Stage(
            preset: .tatami, current: art, history: [], turntable: style,
            presentationSnapshot: snapshot ?? Stage.PresentationSnapshot(wearLevels: [:]),
            daylight: false)
        stage.setFraming(.close, aspect: Float(size.width / size.height), animated: false)
        stage.setPlayback(isPlaying: true, position: 60, duration: 200)
        stage.settle()
        // (The turntable by itself, in the middle: no album beside it. Owner, 2026-10-17.)
        stage.showDeckAlone()
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = stage.scene
        renderer.pointOfView = stage.cameraNode
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    /// Room previews are drawn off the main thread while the panel is visible.
    /// (They show a plain white stand-in album rather than whatever is playing, so they are
    /// drawn once per turntable and clock, not again for every song.)
    func refresh(turntable: TurntableStyle, clock: ClockStyle?, delay: TimeInterval = 0) {
        let key = turntable.rawValue + (clock?.rawValue ?? "")
        let visible = NSApp.windows.contains(where: {
            $0.isVisible
                && ($0.contentView is NSHostingView<SettingsView>
                    || $0.contentView?.subviews.contains(where: { $0 is NSHostingView<SettingsView> }) == true)
        })
        guard visible else { return }
        // (Only a build without the baked stills has to draw the rooms itself.)
        let renderScenes = renderedFor != key && images.count < ScenePreset.allCases.count
        let currentLabels = Dictionary(
            uniqueKeysWithValues: RecordStyle.allCases.map {
                ($0, Collection.shared.deadwaxUnlockLabel(for: $0))
            })
        let recordsToRender = RecordStyle.allCases.filter {
            records[$0] == nil || recordLabels[$0] != currentLabels[$0]
        }
        guard renderScenes || !recordsToRender.isEmpty || renderedFor != key else { return }
        var recordGenerations: [RecordStyle: UInt64] = [:]
        for style in recordsToRender {
            let generation = (recordRenderGeneration[style] ?? 0) &+ 1
            recordRenderGeneration[style] = generation
            recordGenerations[style] = generation
        }
        if renderScenes { sceneRenderGeneration &+= 1 }
        let sceneGeneration = sceneRenderGeneration
        let missingClocks = renderedFor != key || renderScenes ? ClockStyle.allCases.filter { clocks[$0] == nil } : []
        let missingDecks = renderedFor != key || renderScenes ? TurntableStyle.allCases.filter { decks[$0] == nil } : []
        renderedFor = key
        let presentationSnapshot = Stage.PresentationSnapshot(wearLevels: [:])
        // (The two records that are pressed in the cover's colour are drawn in the colour of what is playing, whoever asks for them.)
        let playing = tintArt
        queue.asyncAfter(deadline: .now() + delay) {
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            for style in recordsToRender {
                let label = currentLabels[style] ?? RecordDeadwax.neutralUnlockLabel(for: style)
                let image = SceneThumbnails.record(
                    style, device: device, unlockLabel: label,
                    art: style == .pressing || style == .splatter ? playing : nil)
                DispatchQueue.main.async {
                    guard self.recordRenderGeneration[style] == recordGenerations[style],
                        Collection.shared.deadwaxUnlockLabel(for: style) == label
                    else { return }
                    self.records[style] = image
                    self.recordLabels[style] = label
                }
            }
            if renderScenes {
                for preset in ScenePreset.allCases {
                    let image = SceneThumbnails.scene(
                        preset, turntable: turntable, clock: clock, device: device, snapshot: presentationSnapshot)
                    DispatchQueue.main.async {
                        guard self.sceneRenderGeneration == sceneGeneration else { return }
                        self.images[preset] = image
                    }
                }
            }
            for style in missingClocks {
                let image = DeskClock.preview(style, device: device)
                DispatchQueue.main.async {
                    guard self.sceneRenderGeneration == sceneGeneration else { return }
                    self.clocks[style] = image
                }
            }
            for style in missingDecks {
                let image = SceneThumbnails.deck(style, device: device, snapshot: presentationSnapshot)
                DispatchQueue.main.async {
                    guard self.sceneRenderGeneration == sceneGeneration else { return }
                    self.decks[style] = image
                }
            }
        }
    }
}

extension SceneThumbnails {
    /// Two of the records are pressed in the colour of the cover that is playing: their pictures are taken again for each new album.
    func recolour(for art: AlbumArt) {
        guard art.id != tintedFor else { return }
        tintedFor = art.id
        tintArt = art
        // (Anything still being drawn for these two from before is out of date now, and is thrown away when it arrives.)
        var generations: [RecordStyle: UInt64] = [:]
        for style in [RecordStyle.pressing, .splatter] {
            let generation = (recordRenderGeneration[style] ?? 0) &+ 1
            recordRenderGeneration[style] = generation
            generations[style] = generation
        }
        let labels = Dictionary(
            uniqueKeysWithValues: [RecordStyle.pressing, .splatter].map {
                ($0, Collection.shared.deadwaxUnlockLabel(for: $0))
            })
        queue.async {
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            for style in [RecordStyle.pressing, .splatter] {
                let label = labels[style] ?? RecordDeadwax.neutralUnlockLabel(for: style)
                let image = SceneThumbnails.record(style, device: device, unlockLabel: label, art: art)
                DispatchQueue.main.async {
                    guard self.tintedFor == art.id, self.recordRenderGeneration[style] == generations[style] else {
                        return
                    }
                    self.records[style] = image
                    self.recordLabels[style] = label
                }
            }
        }
    }

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
