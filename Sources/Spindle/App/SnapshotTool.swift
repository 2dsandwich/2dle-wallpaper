import AppKit
import Metal
import SceneKit
import SwiftUI

/// Offscreen renderer used during development:
///   Spindle --snapshot out.png [--scene listeningRoom|afterHours|turntable] [--framing close|mid|wide]
///           [--size 1800x1169] [--art cover.jpg] [--progress 0.35] [--paused] [--transparent]
///           [--change 0.4,0.9,1.4]   (render an album change at the given times after it starts)
enum SnapshotTool {
    static func run(_ args: [String]) -> Int32 {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let out = value("--snapshot") else { return 2 }
        if args.contains("--record-previews") {
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            let directory = URL(fileURLWithPath: out, isDirectory: true)
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch {
                return 1
            }
            let start = Date()
            for style in RecordStyle.allCases {
                let saved = autoreleasepool { () -> Bool in
                    let image = SceneThumbnails.record(
                        style, device: device,
                        unlockLabel: RecordDeadwax.neutralUnlockLabel(for: style))
                    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
                    return writePNG(cg, to: directory.appendingPathComponent("\(style.rawValue).png"))
                }
                guard saved else { return 1 }
                // The see-through ones are taken a second time with nothing under or behind them.
                if VinylLook.make(style, art: nil).transparency < 1 {
                    autoreleasepool {
                        let image = SceneThumbnails.record(
                            style, device: device, unlockLabel: RecordDeadwax.neutralUnlockLabel(for: style),
                            clear: true)
                        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                            _ = writePNG(cg, to: directory.appendingPathComponent("\(style.rawValue)-clear.png"))
                        }
                    }
                }
            }
            print(
                "Rendered \(RecordStyle.allCases.count) record previews in \(String(format: "%.2f", Date().timeIntervalSince(start)))s."
            )
            return 0
        }
        if args.contains("--menu-previews") {
            Hidden.suppressed = true
            // The stills the menu shows for the scenes, made once at build time.
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            let directory = URL(fileURLWithPath: out, isDirectory: true)
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch {
                return 1
            }
            let start = Date()
            let size = CGSize(width: 800, height: 500)
            func writeJPEG(_ image: NSImage, _ name: String) -> Bool {
                guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                    let data = NSBitmapImageRep(cgImage: cg).representation(
                        using: .jpeg, properties: [.compressionFactor: 0.86])
                else { return false }
                return (try? data.write(to: directory.appendingPathComponent(name))) != nil
            }
            for preset in ScenePreset.allCases {
                guard
                    autoreleasepool(invoking: {
                        writeJPEG(
                            SceneThumbnails.scene(preset, turntable: .heritage, clock: nil, device: device, size: size),
                            "scene-\(preset.rawValue).jpg")
                    })
                else { return 1 }
            }
            print("Rendered the menu stills in \(String(format: "%.2f", Date().timeIntervalSince(start)))s.")
            return 0
        }
        if args.contains("--probe-speed") {
            // Does changing the speed of a running, keyed action take effect?
            let scene = SCNScene()
            let node = SCNNode()
            scene.rootNode.addChildNode(node)
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = scene
            node.runAction(.sequence([.wait(duration: 1), .moveBy(x: 10, y: 0, z: 0, duration: 10)]), forKey: "t")
            var t = 0.0
            func step(to end: Double) {
                while t < end {
                    t += 1.0 / 30
                    _ = renderer.snapshot(atTime: t, with: CGSize(width: 8, height: 8), antialiasingMode: .none)
                }
            }
            step(to: 2.0)
            print("x at 2s (speed 1):", node.position.x, node.presentation.position.x)
            node.action(forKey: "t")?.speed = 4
            step(to: 3.0)
            print("x at 3s (speed 4 for 1s):", node.position.x, node.presentation.position.x)
            return 0
        }
        if let style = ClockStyle(rawValue: value("--clock-preview") ?? ""), let device = MTLCreateSystemDefaultDevice()
        {
            if let cg = DeskClock.preview(style, device: device).cgImage(forProposedRect: nil, context: nil, hints: nil)
            {
                writeJPEG(cg, to: URL(fileURLWithPath: out))
            }
            return 0
        }
        if args.contains("--books") {
            // All eight classics laid out side by side, plus one stack, for checking the bindings.
            let scene = SCNScene()
            scene.background.contents = NSColor(white: 0.08, alpha: 1)
            scene.lightingEnvironment.contents = Resources.url("hdri/photo_studio_loft_hall.hdr")
            for i in 0..<8 {
                let stack = Props.classicBooks(seed: UInt64(i) &* 7919 &+ (UInt64(value("--seed") ?? "1") ?? 1))
                stack.simdPosition = SIMD3(Float(i % 4) * 0.21 - 0.315, 0, Float(i / 4) * 0.27 - 0.13)
                stack.simdEulerAngles = SIMD3(0, deg(i % 2 == 0 ? 0 : 90), 0)
                scene.rootNode.addChildNode(stack)
            }
            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 30
            camera.camera?.zNear = 0.05
            camera.simdPosition = SIMD3(0, 0.75, 0.62)
            camera.simdLook(at: SIMD3(0, 0.02, 0.0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            scene.rootNode.addChildNode(camera)
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            let renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene
            renderer.pointOfView = camera
            let image = renderer.snapshot(
                atTime: 0, with: CGSize(width: 1800, height: 1200), antialiasingMode: .multisampling4X)
            if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                writeJPEG(cg, to: URL(fileURLWithPath: out))
            }
            return 0
        }
        if let which = value("--prop") {
            // Close studio view of one of the things that stand on the desk: `cat`, `tea`, `matcha`, `red`, `white`.
            let scene = SCNScene()
            scene.background.contents = NSColor(white: 0.16, alpha: 1)
            scene.lightingEnvironment.contents = Resources.url("hdri/photo_studio_loft_hall.hdr")
            scene.lightingEnvironment.intensity = 0.22
            let prop: SCNNode
            switch which {
            case "cat": prop = DeskThings.manekiNeko().node
            case "tea": prop = Drinks.yunomi()
            case "teacup": prop = Drinks.teacup()
            case "books": prop = Props.classicBooks(seed: UInt64(value("--seed") ?? "3") ?? 3)
            case "matcha": prop = Props.chawan(steam: 0.1)
            // (Anything else is the name of a model in the library, stood up at a metre across.)
            default: prop = ModelLibrary.node(which, length: Float(value("--length") ?? "0.3") ?? 0.3)
            }
            prop.simdEulerAngles = SIMD3(0, deg(Float(value("--turn") ?? "0") ?? 0), 0)
            scene.rootNode.addChildNode(prop)
            let floor = SCNNode(SCNPlane(width: 2, height: 2), material: Mat.pbr(rgb(0.36, 0.26, 0.18), roughness: 0.5))
            floor.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            scene.rootNode.addChildNode(floor)
            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .spot
            key.light?.intensity = 26
            key.light?.spotOuterAngle = 50
            key.light?.castsShadow = true
            key.simdPosition = SIMD3(0.5, 0.7, 0.6)
            key.simdLook(at: SIMD3(0, 0.08, 0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            scene.rootNode.addChildNode(key)
            let (low, high) = prop.boundingBox
            let known = ["cat", "tea", "teacup", "matcha", "white", "red", "books"].contains(which)
            let tall = known ? Float(max(high.y - low.y, 0.06)) : (Float(value("--length") ?? "0.3") ?? 0.3)
            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 24
            camera.camera?.zNear = 0.02
            let above = args.contains("--from-above")
            camera.simdPosition = above ? SIMD3(0, tall * 3.4, tall * 1.5) : SIMD3(0, tall * 1.45, tall * 3.6)
            camera.simdLook(at: SIMD3(0, tall * 0.48, 0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            scene.rootNode.addChildNode(camera)
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            let renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene
            renderer.pointOfView = camera
            let image = renderer.snapshot(
                atTime: 0, with: CGSize(width: 700, height: 700), antialiasingMode: .multisampling4X)
            if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                writeJPEG(cg, to: URL(fileURLWithPath: out))
            }
            return 0
        }
        if let pick = value("--mug") {
            // Close studio view of one mug design, for checking the print and the steam.
            let scene = SCNScene()
            scene.background.contents = NSColor(white: 0.08, alpha: 1)
            scene.lightingEnvironment.contents = Resources.url("hdri/photo_studio_loft_hall.hdr")
            let dark = args.contains("--dark-mug")
            let mug = Props.mug(
                dark ? rgb(0.17, 0.21, 0.19) : rgb(0.84, 0.80, 0.72), design: Int(pick) ?? 0, facing: 140, steam: 0.17,
                latte: Int(value("--latte") ?? "0") ?? 0, coaster: Int(value("--coaster") ?? "0") ?? 0)
            mug.simdEulerAngles = SIMD3(0, deg(140), 0)
            scene.rootNode.addChildNode(mug)
            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 26
            camera.camera?.zNear = 0.05
            camera.simdPosition = args.contains("--from-above") ? SIMD3(0, 0.42, 0.16) : SIMD3(0, 0.30, 0.55)
            camera.simdLook(
                at: SIMD3(0, args.contains("--from-above") ? 0.07 : 0.10, 0), up: SIMD3(0, 1, 0),
                localFront: SIMD3(0, 0, -1))
            scene.rootNode.addChildNode(camera)
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            let renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene
            renderer.pointOfView = camera
            mug.enumerateHierarchy { node, _ in
                if node.name == "steam" {
                    node.geometry?.firstMaterial?.setValue(
                        NSNumber(value: Float(value("--time") ?? "3") ?? 3), forKey: "steamTime")
                }
            }
            let image = renderer.snapshot(
                atTime: 0, with: CGSize(width: 420, height: 520), antialiasingMode: .multisampling4X)
            if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                writeJPEG(cg, to: URL(fileURLWithPath: out))
            }
            return 0
        }
        // The menu bar's drop-down, its bubble or its record's drawings (see `MenuBarController.snapshot`).
        if args.contains("--menubar") { return MenuBarController.snapshot(args, to: out) }
        if let n = value("--dump-latte"), let image = Props.coffeeSurface(Int(n) ?? 1) {
            writePNG(image, to: URL(fileURLWithPath: out))
            return 0
        }
        if args.contains("--rock-size") {
            let rock = ScenePieces.rock(size: SIMD3(1, 0.5, 0.8), seed: 331, material: SCNMaterial())
            var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var high = -low
            rock.enumerateHierarchy { node, _ in
                guard let source = node.geometry?.sources(for: .vertex).first else { return }
                source.data.withUnsafeBytes { raw in
                    for i in 0..<source.vectorCount {
                        let o = i * source.dataStride + source.dataOffset
                        let p = SIMD3(
                            raw.loadUnaligned(fromByteOffset: o, as: Float.self),
                            raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self),
                            raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self))
                        low = simd_min(low, p)
                        high = simd_max(high, p)
                    }
                }
            }
            print("rock of size (1, 0.5, 0.8) spans", low, high)
            return 0
        }
        if let names = value("--model-size") {
            for name in names.split(separator: ",") { print(name, ModelLibrary.size(String(name))) }
            return 0
        }
        if let name = value("--model-facing") {
            // Which way a library model faces as it comes: where its tall part (a chair's back) is, seen from its middle.
            let node = ModelLibrary.node(name)
            var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var high = -low
            var points: [SIMD3<Float>] = []
            node.enumerateHierarchy { child, _ in
                guard let source = child.geometry?.sources(for: .vertex).first else { return }
                let stride = source.dataStride
                let offset = source.dataOffset
                source.data.withUnsafeBytes { raw in
                    for i in Swift.stride(from: 0, to: source.vectorCount, by: 7) {
                        let x = raw.loadUnaligned(fromByteOffset: i * stride + offset, as: Float.self)
                        let y = raw.loadUnaligned(fromByteOffset: i * stride + offset + 4, as: Float.self)
                        let z = raw.loadUnaligned(fromByteOffset: i * stride + offset + 8, as: Float.self)
                        let p = child.simdConvertPosition(SIMD3(x, y, z), to: node)
                        points.append(p)
                        low = simd_min(low, p)
                        high = simd_max(high, p)
                    }
                }
            }
            let upper = points.filter { $0.y > low.y + (high.y - low.y) * 0.7 }
            let mean = upper.reduce(SIMD3<Float>(repeating: 0), +) / Float(max(upper.count, 1))
            print(name, "size", high - low, "upper part centred at", mean - (low + high) / 2)
            return 0
        }
        if let name = value("--bake-blurred") {
            // One library model photographed from where the scene's camera stands and thrown well out
            // of focus, for something that has to sit right in front of the lens: a picture of a blur
            // costs nothing to draw, and the lens itself can then stay sharp for the rest of the room.
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            let scene = SCNScene()
            scene.background.contents = NSColor.clear
            let model = ModelLibrary.node(name, length: 1)
            model.simdEulerAngles = SIMD3(0, deg(Float(value("--turn") ?? "0") ?? 0), 0)
            scene.rootNode.addChildNode(model)
            func light(_ type: SCNLight.LightType, _ colour: NSColor, _ intensity: CGFloat, from: SIMD3<Float>? = nil) {
                let node = SCNNode()
                let lamp = SCNLight()
                lamp.type = type
                lamp.color = colour
                lamp.intensity = intensity
                node.light = lamp
                if let from {
                    node.simdPosition = from
                    node.simdLook(at: SIMD3(0, 0.5, 0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
                }
                scene.rootNode.addChildNode(node)
            }
            light(.directional, rgb(1.0, 0.88, 0.70), 900, from: SIMD3(-3.0, 2.2, 1.0))
            light(.ambient, rgb(0.70, 0.74, 0.86), 260)
            let camera = SCNCamera()
            camera.usesOrthographicProjection = true
            camera.orthographicScale = 0.62
            camera.zNear = 0.1
            camera.zFar = 20
            let eye = SCNNode()
            eye.camera = camera
            let tilt = deg(Float(value("--tilt") ?? "32") ?? 32)
            eye.simdPosition = SIMD3(0, 0.5 + 6 * sin(tilt), 6 * cos(tilt))
            eye.simdLook(at: SIMD3(0, 0.5, 0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            scene.rootNode.addChildNode(eye)
            let renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene
            renderer.pointOfView = eye
            renderer.autoenablesDefaultLighting = false
            _ = renderer.snapshot(atTime: 0, with: CGSize(width: 512, height: 512), antialiasingMode: .none)
            let image = renderer.snapshot(
                atTime: 0, with: CGSize(width: 512, height: 512), antialiasingMode: .multisampling4X)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1 }
            writePNG(
                Tex.blur(cg, radius: CGFloat(Double(value("--blur") ?? "11") ?? 11)), to: URL(fileURLWithPath: out))
            return 0
        }
        if args.contains("--lid-report") {
            // How far back and how high each deck reaches with its cover fully open.
            for style in TurntableStyle.allCases {
                let rig = Props.turntable(style)
                rig.cover?.setOpen(true, animated: false)
                var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                var high = -low
                rig.root.enumerateHierarchy { node, _ in
                    guard node.geometry != nil else { return }
                    let (a, b) = node.boundingBox
                    for x in [a.x, b.x] {
                        for y in [a.y, b.y] {
                            for z in [a.z, b.z] {
                                let p = node.simdConvertPosition(SIMD3(Float(x), Float(y), Float(z)), to: rig.root)
                                low = simd_min(low, p)
                                high = simd_max(high, p)
                            }
                        }
                    }
                }
                print(
                    style.rawValue, "cover:", rig.cover != nil, "rear z", low.z, "front z", high.z, "top y", high.y,
                    "x", low.x, high.x)
            }
            return 0
        }
        if args.contains("--dump-gobo") {
            writePNG(Tex.blindsGobo(), to: URL(fileURLWithPath: out))
            return 0
        }
        if args.contains("--dump-skyline") {
            writeJPEG(Tex.skyline(), to: URL(fileURLWithPath: out))
            return 0
        }
        // (`--sun 7.5` lights the daylight scenes for that hour of the day.)
        Daylight.hour = value("--sun").flatMap { Double($0) }
        // (`--quality minimum|maximum`: the stage as that setting builds it. The size and the frames are the caller's to choose.)
        if let quality = DrawingQuality(rawValue: value("--quality") ?? "") { DrawingQuality.current = quality }
        let preset = ScenePreset(rawValue: value("--scene") ?? "") ?? .listeningRoom
        let framing = Framing(rawValue: value("--framing") ?? "") ?? .mid
        var size = CGSize(width: 1800, height: 1169)
        if let parts = value("--size")?.split(separator: "x"), parts.count == 2,
            let w = Double(parts[0]), let h = Double(parts[1])
        {
            size = CGSize(width: w, height: h)
        }
        func tourStage(_ preset: ScenePreset) -> Stage {
            let stage = autoreleasepool {
                Stage(
                    preset: preset, current: AlbumArt(id: "builtin-0", image: Tex.placeholderCover(0)),
                    history: (1...5).map { AlbumArt(id: "builtin-\($0)", image: Tex.placeholderCover($0)) },
                    transparent: false, turntable: .heritage, clock: ClockStyle(rawValue: value("--clock") ?? ""))
            }
            stage.setFraming(framing, aspect: Float(size.width / size.height), animated: false)
            stage.setPlayback(isPlaying: true, position: 70, duration: 200)
            stage.settle()
            return stage
        }
        if args.contains("--memory-tour") {
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            Bench.tour(
                device: device, size: size, samples: Int(value("--msaa") ?? "2") ?? 2,
                vmmap: args.contains("--vmmap"), make: tourStage)
            return 0
        }
        if args.contains("--settle-test") {
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            return Bench.settleTest(device: device, size: size, make: tourStage)
        }
        if args.contains("--weather-motion-test") {
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            return Bench.weatherMotionTest(device: device, size: size) { preset in
                let stage = tourStage(preset)
                // (Paused, as the owner's was: nothing playing, the record still, only the scene's own ambience drawn.)
                stage.setPlayback(isPlaying: false, position: 70, duration: 200)
                stage.settle()
                return stage
            }
        }
        if args.contains("--pack-test") {
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            return Bench.packTest(device: device, size: size, make: tourStage)
        }
        if args.contains("--leave-test") {
            guard let device = MTLCreateSystemDefaultDevice() else { return 1 }
            return Bench.leaveTest(device: device, size: size, make: tourStage)
        }
        let progress = Double(value("--progress") ?? "0.35") ?? 0.35
        let paused = args.contains("--paused")

        // (`--covers <folder>`: the pictures in it, in name order, stand in for the built-in covers 0, 1, 2… and go round again.)
        let given: [CGImage] =
            value("--covers").map { folder in
                ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted()
                    .filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".png") }
                    .compactMap {
                        loadImage(at: URL(fileURLWithPath: folder).appendingPathComponent($0)).map { Tex.squared($0) }
                    }
            } ?? []
        func cover(_ n: Int) -> CGImage { given.isEmpty ? Tex.placeholderCover(n) : given[n % given.count] }
        var current = AlbumArt(id: "builtin-0", image: cover(0))
        if let path = value("--art"), let image = loadImage(at: URL(fileURLWithPath: path)) {
            current = AlbumArt(id: path, image: Tex.squared(image))
        }
        var history = (1...(Int(value("--history") ?? "5") ?? 5)).map {
            AlbumArt(id: "builtin-\($0)", image: cover($0))
        }
        // (`--empty`: a first-time listener's desk, the plain record on the platter and no sleeves.)
        if args.contains("--empty") {
            current = AlbumArt(id: "builtin-empty", image: Tex.plainLabel(ring: .darkGray))
            history = []
        }

        // (In a pool of its own, as the app builds a stage on a queue that empties its pool after each: what was
        // drawn with AppKit's help is let go of then, and a bench's memory is the app's.)
        let stage = autoreleasepool {
            Stage(
                preset: preset, current: current, history: history, transparent: args.contains("--transparent"),
                turntable: TurntableStyle(rawValue: value("--deck") ?? "") ?? .heritage,
                clock: ClockStyle(rawValue: value("--clock") ?? ""))
        }
        stage.setFraming(framing, aspect: Float(size.width / size.height), animated: false)
        stage.setPlayback(isPlaying: !paused, position: progress * 200, duration: 200)
        if args.contains("--lid-closed") { stage.setLidClosedForTesting(true) }
        stage.settle()
        if args.contains("--bare") { stage.clearDeskForTesting() }
        if args.contains("--texture-report") {
            Bench.textureReport(stage: stage)
            return 0
        }
        if args.contains("--count-draws") {
            // How many separate pieces the renderer has to draw, by top-level group.
            func draws(_ node: SCNNode) -> Int {
                (node.isHidden
                    ? 0 : (node.geometry?.elements.count ?? 0) + node.childNodes.reduce(0) { $0 + draws($1) })
            }
            func report(_ node: SCNNode, depth: Int) {
                for child in node.childNodes {
                    let n = draws(child)
                    var materials = Set<ObjectIdentifier>()
                    child.enumerateHierarchy { node, _ in
                        node.geometry?.materials.forEach { materials.insert(ObjectIdentifier($0)) }
                    }
                    let box = child.boundingBox
                    if n >= 2 {
                        print(
                            String(repeating: "  ", count: depth)
                                + "\(n) draws, \(materials.count) materials  \(child.name ?? "-")  children=\(child.childNodes.count) at \(child.simdPosition) size \(box.max.x - box.min.x)x\(box.max.y - box.min.y)"
                        )
                    }
                    if depth < 1 && n >= 30 { report(child, depth: depth + 1) }
                }
            }
            print("total", draws(stage.scene.rootNode))
            report(stage.scene.rootNode, depth: 0)
            return 0
        }

        guard let device = MTLCreateSystemDefaultDevice() else {
            FileHandle.standardError.write(Data("No Metal device\n".utf8))
            return 1
        }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = stage.scene
        renderer.pointOfView = stage.cameraNode
        renderer.autoenablesDefaultLighting = false

        func save(_ time: TimeInterval, to path: String) {
            let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let url = URL(fileURLWithPath: path)
            if path.hasSuffix(".jpg") { writeJPEG(cg, to: url, quality: 0.9) } else { writePNG(cg, to: url) }
            print("wrote \(path)")
        }

        var clock: TimeInterval = 0
        func advance(to target: TimeInterval) {
            while clock < target {
                clock = min(clock + 1.0 / 60, target)
                renderer.update(atTime: clock)
                stage.update(atTime: clock)
                // Let action completion handlers (dispatched to main) run.
                RunLoop.main.run(until: Date(timeIntervalSinceNow: args.contains("--realtime") ? 1.0 / 60 : 0.0005))
            }
        }

        advance(to: Double(value("--time") ?? "0.5") ?? 0.5)
        if args.contains("--bench") {
            Bench.run(
                stage: stage, device: device, size: size, frames: Int(value("--bench-frames") ?? "120") ?? 120,
                samples: Int(value("--msaa") ?? "2") ?? 2, live: !args.contains("--still"))
            return 0
        }
        if args.contains("--prepare-test") {
            // What the app does when a turntable, clock or camera is changed: a second stage is built
            // and handed to the renderer to warm up while the first is still on screen.
            _ = renderer.snapshot(atTime: clock, with: size, antialiasingMode: .none)
            let next = Stage(
                preset: preset, current: current, history: history, transparent: false,
                turntable: TurntableStyle(rawValue: value("--deck") ?? "") ?? .heritage,
                clock: ClockStyle(rawValue: value("--clock") ?? ""))
            next.setFraming(framing, aspect: Float(size.width / size.height), animated: false)
            next.settle()
            var done = false
            renderer.prepare([next.scene]) { ok in
                print("prepared \(preset.rawValue): \(ok)")
                done = true
            }
            let limit = Date(timeIntervalSinceNow: 30)
            while !done, Date() < limit { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
            return done ? 0 : 2
        }
        if let skips = value("--skip-test") {
            // Five skips, 0.6 s apart, then frames at the given times after the first.
            let start = clock
            let times = skips.split(separator: ",").compactMap { Double($0) }
            let base = (out as NSString).deletingPathExtension
            let ext = (out as NSString).pathExtension
            var issued = 0
            for (i, t) in times.enumerated() {
                while issued < 5, start + Double(issued) * 0.6 <= start + t {
                    advance(to: start + Double(issued) * 0.6)
                    stage.setAlbum(
                        AlbumArt(id: "skip-\(issued)", image: Tex.placeholderCover(issued + 1)), animated: true)
                    issued += 1
                }
                advance(to: start + t)
                save(clock, to: "\(base)_\(i).\(ext)")
            }
            return 0
        }
        if let pair = value("--restyle")?.split(separator: ",").compactMap({ RecordStyle(rawValue: String($0)) }),
            pair.count == 2
        {
            // Change the record's style and save frames of the dissolve (run with SPINDLE_UNLOCK_ALL=1).
            Collection.shared.setChoice(style: pair[0], shuffle: false)
            stage.restyleRecord()
            advance(to: clock + 2.5)
            Collection.shared.setChoice(style: pair[1], shuffle: false)
            stage.restyleRecord()
            let start = clock
            let base = (out as NSString).deletingPathExtension
            let ext = (out as NSString).pathExtension
            for (i, t) in (value("--frames") ?? "").split(separator: ",").compactMap({ Double($0) }).enumerated() {
                advance(to: start + t)
                save(clock, to: "\(base)_\(i).\(ext)")
            }
            return 0
        }
        // (`--put-away bare|shield|thrown`: how the first album change of a test puts its record away.)
        if let way = value("--put-away") { Stage.putAwayForTesting = Stage.PutAway.allCases.first { "\($0)" == way } }
        if let script = value("--script") {
            // "time:album,time:album…" asks for albums at those moments (album "b5" is builtin-5, the top
            // of the pile; anything else is a new cover); frames are saved at the `--frames` times.
            let start = clock
            var asks = script.split(separator: ",").compactMap { item -> (Double, String)? in
                let parts = item.split(separator: ":")
                guard parts.count == 2, let t = Double(parts[0]) else { return nil }
                return (t, String(parts[1]))
            }
            let base = (out as NSString).deletingPathExtension
            let ext = (out as NSString).pathExtension
            for (i, t) in (value("--frames") ?? "").split(separator: ",").compactMap({ Double($0) }).enumerated() {
                while let ask = asks.first, ask.0 <= t {
                    asks.removeFirst()
                    advance(to: start + ask.0)
                    let name = ask.1
                    if name.hasPrefix("b"), let n = Int(name.dropFirst()) {
                        stage.setAlbum(AlbumArt(id: "builtin-\(n)", image: cover(n)), animated: true)
                    } else {
                        stage.setAlbum(
                            AlbumArt(id: "new-\(name)", image: Tex.placeholderCover(Int(stableHash(name) % 9) + 6)),
                            animated: true)
                    }
                }
                advance(to: start + t)
                save(clock, to: "\(base)_\(i).\(ext)")
            }
            return 0
        }
        if let what = value("--drink-test") {
            // "sip", "throw" or "serve": frames of whoever is drinking the drink doing that, at the `--frames` times.
            Drinks.advance(playing: true)
            if what == "sip" { Drinks.sipNow() } else { Drinks.finishNow() }
            if what == "serve" {
                _ = stage.refreshDrink(animated: false)
                Drinks.bringNow()
                Drinks.advance(playing: true)
            }
            _ = stage.refreshDrink(animated: true)
            let start = clock
            let base = (out as NSString).deletingPathExtension
            let ext = (out as NSString).pathExtension
            for (i, t) in (value("--frames") ?? "").split(separator: ",").compactMap({ Double($0) }).enumerated() {
                advance(to: start + t)
                save(clock, to: "\(base)_\(i).\(ext)")
            }
            return 0
        }
        if let disc = value("--disc-swap") {
            // Render the disc-one-to-disc-two change at the given times.
            stage.setPlayback(isPlaying: true, position: 30, duration: 200, album: "test", disc: 1)
            advance(to: clock + 0.2)
            stage.setPlayback(isPlaying: true, position: 5, duration: 200, album: "test", disc: 2)
            let start = clock
            let base = (out as NSString).deletingPathExtension
            let ext = (out as NSString).pathExtension
            for (i, t) in disc.split(separator: ",").compactMap({ Double($0) }).enumerated() {
                advance(to: start + t)
                save(clock, to: "\(base)_\(i).\(ext)")
            }
            return 0
        }
        if let change = value("--change") {
            let times = change.split(separator: ",").compactMap { Double($0) }
            let next = AlbumArt(id: "builtin-change", image: Tex.placeholderCover(3))
            stage.setAlbum(next, animated: true)
            let start = clock
            let base = (out as NSString).deletingPathExtension
            let ext = (out as NSString).pathExtension
            for (i, t) in times.enumerated() {
                advance(to: start + t)
                save(clock, to: "\(base)_\(i).\(ext)")
            }
        } else {
            save(clock, to: out)
            if args.contains("--cover-stats") { coverStats(stage: stage, renderer: renderer, size: size, at: clock) }
        }
        return 0
    }

    /// (`--cover-stats`: after the still, how the cover on the stand and the top cover of the pile come out: the mean
    /// luma of the middle of each (0-255), its spread (the art reading), the brightest channel; the deck's lit half for
    /// comparison; and whether any 4x4 patch of the frame is at 245 or above.)
    static func coverStats(stage: Stage, renderer: SCNRenderer, size: CGSize, at time: TimeInterval) {
        let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let w = cg.width
        let h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard
            let ctx = CGContext(
                data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let lens = simd_inverse(stage.cameraNode.simdWorldTransform)
        let tall = tan(Float(stage.cameraNode.camera?.fieldOfView ?? 20) * .pi / 360)
        let wide = tall * Float(w) / Float(h)
        func screen(_ p: SIMD3<Float>) -> SIMD2<Float> {
            // (The Boathouse's lens is shifted off its axis.)
            if stage.preset == .turntable,
                let at = BoathouseScene.screenSpot(p, framing: stage.framing, aspect: Float(w) / Float(h))
            {
                return SIMD2((0.5 + 0.5 * at.x) * Float(w), (0.5 - 0.5 * at.y) * Float(h))
            }
            let q = lens * SIMD4(p, 1)
            return SIMD2((0.5 + 0.5 * q.x / -q.z / wide) * Float(w), (0.5 - 0.5 * q.y / -q.z / tall) * Float(h))
        }
        func luma(_ i: Int) -> Float {
            0.2126 * Float(pixels[i]) + 0.7152 * Float(pixels[i + 1]) + 0.0722 * Float(pixels[i + 2])
        }
        func inQuad(_ quad: [SIMD2<Float>], _ p: SIMD2<Float>) -> Bool {
            var sign: Float = 0
            for k in 0..<4 {
                let a = quad[k]
                let b = quad[(k + 1) % 4]
                let c = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
                if c != 0 {
                    if sign == 0 { sign = c } else if (c > 0) != (sign > 0) { return false }
                }
            }
            return true
        }
        func region(_ quad: [SIMD2<Float>]) -> [Int] {
            let xs = quad.map(\.x)
            let ys = quad.map(\.y)
            var found: [Int] = []
            for y in max(0, Int(ys.min()!))..<min(h, Int(ys.max()!) + 1) {
                for x in max(0, Int(xs.min()!))..<min(w, Int(xs.max()!) + 1)
                where inQuad(quad, SIMD2(Float(x) + 0.5, Float(y) + 0.5)) {
                    found.append((y * w + x) * 4)
                }
            }
            return found
        }
        func describe(_ name: String, _ found: [Int]) -> String {
            guard !found.isEmpty else { return "\(name) none" }
            let l = found.map(luma).sorted()
            let mean = l.reduce(0, +) / Float(l.count)
            let sd = sqrt(l.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(l.count))
            var rgb = SIMD3<Float>(0, 0, 0)
            var top: UInt8 = 0
            for i in found {
                rgb += SIMD3(Float(pixels[i]), Float(pixels[i + 1]), Float(pixels[i + 2]))
                top = max(top, pixels[i], pixels[i + 1], pixels[i + 2])
            }
            rgb /= Float(found.count)
            return String(
                format: "%@ mean %.1f sd %.1f p10 %.0f p90 %.0f rgb %.0f/%.0f/%.0f max %d n %d", name, mean, sd,
                l[l.count / 10], l[l.count * 9 / 10], rgb.x, rgb.y, rgb.z, top, found.count)
        }
        func face(_ node: SCNNode, shrink: Float = 0.80) -> [SIMD2<Float>] {
            let half = Dim.sleeveSize / 2 * shrink
            let z = Dim.sleeveThickness / 2
            return [SIMD3(-half, -half, z), SIMD3(half, -half, z), SIMD3(half, half, z), SIMD3(-half, half, z)].map {
                screen(node.simdConvertPosition($0, to: nil))
            }
        }
        var lines: [String] = []
        if let held = stage.held {
            lines.append(describe("stand", region(face(held.node))))
            print("standQuad", face(held.node).map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: " "))
        }
        let pile = stage.entries.filter { $0 !== stage.held }
        if let top = pile.last {
            lines.append(describe("pile", region(face(top.node))))
            print("pileQuad", face(top.node).map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: " "))
        }
        // The desk clock: the middle of its outline on screen (its face, where it faces us).
        if let clock = stage.deskClock?.node {
            let (cl, ch) = clock.boundingBox
            var pts: [SIMD2<Float>] = []
            for x in [cl.x, ch.x] {
                for y in [cl.y, ch.y] {
                    for z in [cl.z, ch.z] {
                        pts.append(screen(clock.simdConvertPosition(SIMD3(Float(x), Float(y), Float(z)), to: nil)))
                    }
                }
            }
            let lo = SIMD2(pts.map(\.x).min()!, pts.map(\.y).min()!)
            let hi = SIMD2(pts.map(\.x).max()!, pts.map(\.y).max()!)
            let a = lo + (hi - lo) * 0.2
            let b = lo + (hi - lo) * 0.8
            lines.append(describe("clock", region([a, SIMD2(b.x, a.y), b, SIMD2(a.x, b.y)])))
            print("clockQuad \(Int(lo.x)),\(Int(lo.y)) \(Int(hi.x)),\(Int(lo.y)) \(Int(hi.x)),\(Int(hi.y)) \(Int(lo.x)),\(Int(hi.y))")
        }
        // The deck's lit half: the brighter half of what is inside the deck's outline on screen.
        let (low, high) = stage.rig.root.boundingBox
        var corners: [SIMD2<Float>] = []
        for x in [low.x, high.x] {
            for y in [low.y, high.y] {
                for z in [low.z, high.z] {
                    corners.append(screen(stage.rig.root.simdConvertPosition(SIMD3(Float(x), Float(y), Float(z)), to: nil)))
                }
            }
        }
        let x0 = max(0, Int(corners.map(\.x).min()!))
        let x1 = min(w, Int(corners.map(\.x).max()!))
        let y0 = max(0, Int(corners.map(\.y).min()!))
        let y1 = min(h, Int(corners.map(\.y).max()!))
        var deck: [Float] = []
        if x1 > x0, y1 > y0 {
            for y in stride(from: y0, to: y1, by: 2) {
                for x in stride(from: x0, to: x1, by: 2) { deck.append(luma((y * w + x) * 4)) }
            }
        }
        deck.sort()
        let lit = deck.isEmpty ? 0 : deck[(deck.count / 2)...].reduce(0, +) / Float(deck.count - deck.count / 2)
        lines.append(String(format: "deckLit %.1f", lit))
        // Clipping: 4x4 blocks whose mean in any channel is 245 or more.
        var clipped = 0
        for by in stride(from: 0, to: h - 3, by: 4) {
            for bx in stride(from: 0, to: w - 3, by: 4) {
                var sum = SIMD3<Int>(0, 0, 0)
                for y in by..<(by + 4) {
                    for x in bx..<(bx + 4) {
                        let i = (y * w + x) * 4
                        sum &+= SIMD3(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
                    }
                }
                if sum.max() >= 245 * 16 { clipped += 1 }
            }
        }
        lines.append("clip4x4 \(clipped)")
        // Lights that are in and on (SceneKit lights a node with at most eight).
        var on = 0
        stage.scene.rootNode.enumerateHierarchy { node, _ in
            guard let light = node.light, light.intensity > 0, light.type != .ambient else { return }
            var up: SCNNode? = node
            while let n = up { if n.isHidden { return }; up = n.parent }
            on += 1
        }
        lines.append("lightsOn \(on)")
        print(lines.joined(separator: " | "))
    }
}
