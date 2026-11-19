import AppKit
import Metal
import SceneKit

/// What a frame costs: `2dle --snapshot - --bench --scene <preset> --size 3024x1964` draws the scene off screen as
/// the wallpaper does and reports the time each frame takes on the processor and on the graphics chip.
/// (`BENCH_*` switches leave one thing out at a time, for finding what the time is spent on.)
enum Bench {
    static func run(stage: Stage, device: MTLDevice, size: CGSize, frames: Int, samples: Int, live: Bool) {
        let env = ProcessInfo.processInfo.environment
        if env["BENCH_GPU"] != nil { GPUCount.watch(device) }
        defer { if env["BENCH_GPU"] != nil { GPUCount.report() } }
        let camera = stage.cameraNode.camera
        var lights: [SCNLight] = []
        stage.scene.rootNode.enumerateHierarchy { node, _ in
            if let light = node.light, !node.isHidden { lights.append(light) }
        }
        if env["BENCH_NOSHADOW"] != nil { lights.forEach { $0.castsShadow = false } }
        if let n = env["BENCH_SHADOW_SAMPLES"].flatMap({ Int($0) }) { lights.forEach { $0.shadowSampleCount = n } }
        if let n = env["BENCH_SHADOW_MAP"].flatMap({ Double($0) }) {
            lights.forEach { $0.shadowMapSize = CGSize(width: n, height: n) }
        }
        if env["BENCH_NOSSAO"] != nil { camera?.screenSpaceAmbientOcclusionIntensity = 0 }
        if env["BENCH_NODOF"] != nil { camera?.wantsDepthOfField = false }
        if env["BENCH_NOBLOOM"] != nil { camera?.bloomIntensity = 0 }
        if env["BENCH_NOHDR"] != nil { camera?.wantsHDR = false }
        if env["BENCH_NOGRADE"] != nil { camera?.colorGrading.contents = nil }
        if env["BENCH_NOVIGNETTE"] != nil { camera?.vignettingIntensity = 0 }
        // (`BENCH_HIDE=<name>` leaves out the piece of the scene with that name: `library` is the Library's room, say.)
        if let name = env["BENCH_HIDE"] {
            stage.scene.rootNode.childNode(withName: name, recursively: true)?.isHidden = true
        }
        if env["BENCH_NOLIGHTS"] != nil {
            stage.scene.rootNode.enumerateHierarchy { node, _ in if node.light != nil { node.isHidden = true } }
        }
        let casting = lights.filter(\.castsShadow).count
        var pieces = 0
        stage.scene.rootNode.enumerateHierarchy { node, _ in
            if !node.isHidden { pieces += node.geometry?.elements.count ?? 0 }
        }

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = stage.scene
        renderer.pointOfView = stage.cameraNode
        renderer.autoenablesDefaultLighting = false
        guard let queue = device.makeCommandQueue() else { return }
        let width = Int(size.width)
        let height = Int(size.height)
        func target(_ format: MTLPixelFormat, samples: Int) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: width, height: height, mipmapped: false)
            d.usage = [.renderTarget]
            d.storageMode = .private
            if samples > 1 {
                d.textureType = .type2DMultisample
                d.sampleCount = samples
            }
            return device.makeTexture(descriptor: d)
        }
        guard let resolved = target(.bgra8Unorm_srgb, samples: 1) else { return }
        let pass = MTLRenderPassDescriptor()
        if samples > 1, let multi = target(.bgra8Unorm_srgb, samples: samples) {
            pass.colorAttachments[0].texture = multi
            pass.colorAttachments[0].resolveTexture = resolved
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].texture = resolved
            pass.colorAttachments[0].storeAction = .store
        }
        pass.colorAttachments[0].loadAction = .clear
        let viewport = CGRect(x: 0, y: 0, width: width, height: height)

        var clock = CACurrentMediaTime()
        func frame() -> Double {
            clock += 1.0 / 60
            if live { stage.update(atTime: clock) }
            guard let buffer = queue.makeCommandBuffer() else { return 0 }
            renderer.render(atTime: clock, viewport: viewport, commandBuffer: buffer, passDescriptor: pass)
            buffer.commit()
            buffer.waitUntilCompleted()
            return buffer.gpuEndTime - buffer.gpuStartTime
        }
        // (The first frames compile shaders and upload textures: they are not what a frame costs.)
        for _ in 0..<12 { _ = frame() }
        // (`BENCH_ENERGY=<s> BENCH_FPS=<n>`: what drawing at the wallpaper's pace costs, as the system counts it.)
        if let seconds = env["BENCH_ENERGY"].flatMap({ Double($0) }) {
            energy(
                seconds: seconds, fps: env["BENCH_FPS"].flatMap { Double($0) } ?? 60, label: stage.preset.rawValue,
                draw: { step, done in
                    clock += step
                    if live { stage.update(atTime: clock) }
                    guard let buffer = queue.makeCommandBuffer() else { return nil }
                    renderer.render(atTime: clock, viewport: viewport, commandBuffer: buffer, passDescriptor: pass)
                    buffer.addCompletedHandler { done($0.gpuEndTime - $0.gpuStartTime) }
                    buffer.commit()
                    return buffer
                })
            return
        }
        let cpu0 = processCPUSeconds()
        let wall0 = CACurrentMediaTime()
        var gpu: [Double] = []
        for _ in 0..<frames { gpu.append(frame()) }
        let cpu = (processCPUSeconds() - cpu0) / Double(frames)
        let wall = (CACurrentMediaTime() - wall0) / Double(frames)
        gpu.sort()
        let label = env.keys.filter { $0.hasPrefix("BENCH_") }.sorted().map { "\($0.dropFirst(6))=\(env[$0] ?? "")" }
            .joined(separator: " ")
        print(
            String(
                format:
                    "%@ %dx%d x%d  gpu %.2f ms (median %.2f)  cpu %.2f ms  wall %.2f ms  | %d lights, %d casting, %d pieces  %@",
                stage.preset.rawValue, width, height, samples, gpu.reduce(0, +) / Double(gpu.count) * 1000,
                gpu[gpu.count / 2] * 1000,
                cpu * 1000, wall * 1000, lights.count, casting, pieces, label))
        // (And what the process holds, as Activity Monitor says "Memory": the goal of 2026-10-17 is to bring it down, so a
        // change is compared by this line before and after.)
        print(String(format: "%@ memory %.0f MB (footprint)", stage.preset.rawValue, footprintMB()))
        // (`BENCH_HOLD=<s>`: the process waits that long with the scene still held, for `vmmap`, `footprint` or `heap`.)
        if env["BENCH_VMMAP"] != nil { print(vmmapSummary()) }
        // (`BENCH_REGIONS=<file>`: every region, for finding which pictures are still in memory by their sizes.)
        if let file = env["BENCH_HEAP"] { inspect("/usr/bin/heap", arguments: ["-s"], into: file) }
        if let file = env["BENCH_REGIONS"] {
            inspect("/usr/bin/vmmap", into: file)
            // (And, run with `MallocStackLogging=1`, where each big picture still in memory was made.)
            if env["MallocStackLogging"] != nil {
                let text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
                var n = 0
                for line in text.split(separator: "\n")
                where line.hasPrefix("CG Raster Data") || line.hasPrefix("CG Image") {
                    let words = line.split(separator: " ")
                    guard let range = words.first(where: { $0.contains("-") && $0.count > 16 }),
                        let size = line.split(separator: "[").dropFirst().first?.split(separator: " ").first,
                        size.hasSuffix("M"), (Double(size.dropLast()) ?? 0) >= 2
                    else { continue }
                    let start = "0x" + range.split(separator: "-")[0]
                    inspect("/usr/bin/malloc_history", arguments: ["-fullStacks"], into: file + ".\(n)", last: start)
                    n += 1
                }
            }
        }
        if let hold = env["BENCH_HOLD"].flatMap({ Double($0) }) {
            print("holding pid \(ProcessInfo.processInfo.processIdentifier) for \(hold) s")
            Thread.sleep(forTimeInterval: hold)
        }
    }

    /// Draws frames at `fps` (none, at 0) for `seconds`, paced by the clock as the display link paces the wallpaper,
    /// and says what the process cost meanwhile: its energy as the kernel counts it (`ri_energy_nj`, CPU; and
    /// `ri_billed_energy`, what it is billed for, work done for it by others included), its CPU time, the graphics
    /// chip's time (each frame's GPU time, summed: the share of each second the chip is busy for it) and the
    /// kernel's own count of that (`task_gpu_utilisation`).
    static func energy(
        seconds: Double, fps: Double, label: String,
        draw: (Double, @escaping (Double) -> Void) -> MTLCommandBuffer?
    ) {
        struct Count {
            var energy: UInt64 = 0, billed: UInt64 = 0, cpu: UInt64 = 0, gpu: UInt64 = 0
        }
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        func count() -> Count {
            var c = Count()
            var info = rusage_info_v6()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0)
                }
            }
            if ok == 0 {
                c.energy = info.ri_energy_nj
                c.billed = info.ri_billed_energy
                // (In ticks of the time base.)
                c.cpu = (info.ri_user_time + info.ri_system_time) * UInt64(base.numer) / UInt64(base.denom)
            }
            var power = task_power_info_v2()
            var size = mach_msg_type_number_t(
                MemoryLayout<task_power_info_v2>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &power) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO_V2), $0, &size)
                }
            }
            if result == KERN_SUCCESS { c.gpu = power.gpu_energy.task_gpu_utilisation }
            return c
        }
        let lock = NSLock()
        var gpuTime = 0.0
        var frames = 0
        let before = count()
        let start = CACurrentMediaTime()
        var last: MTLCommandBuffer?
        if fps > 0 {
            var next = start
            while CACurrentMediaTime() - start < seconds {
                last = draw(1 / fps) { t in
                    lock.lock()
                    gpuTime += t
                    lock.unlock()
                }
                frames += 1
                next += 1 / fps
                let wait = next - CACurrentMediaTime()
                if wait > 0 { Thread.sleep(forTimeInterval: wait) } else { next = CACurrentMediaTime() }
            }
            last?.waitUntilCompleted()
        } else {
            Thread.sleep(forTimeInterval: seconds)
        }
        let wall = CACurrentMediaTime() - start
        let after = count()
        lock.lock()
        let busy = gpuTime
        lock.unlock()
        print(
            String(
                format:
                    "%@ energy %.0f fps for %.0f s: %.3f W (energy_nj), billed %.3f W, CPU %.1f ms/s, GPU busy %.0f ms/s (frames %.2f ms GPU each), kernel GPU time %.0f ms/s",
                label, Double(frames) / wall, wall, Double(after.energy &- before.energy) / 1e9 / wall,
                Double(after.billed &- before.billed) / 1e9 / wall, Double(after.cpu &- before.cpu) / 1e6 / wall,
                busy * 1000 / wall, frames > 0 ? busy * 1000 / Double(frames) : 0,
                Double(after.gpu &- before.gpu) / 1e6 / wall))
    }

    /// The memory the wallpaper keeps as it goes from scene to scene: `2dle --snapshot - --memory-tour [--size WxH]
    /// [--msaa n] [--quality q] [--vmmap]` builds every scene in turn in one process, draws it for a moment through one
    /// renderer (as the one scene view draws them all), and says the footprint with it drawn and again once it has
    /// been let go of; last, the bare stand-in that the wallpaper keeps while it rests.
    static func tour(device: MTLDevice, size: CGSize, samples: Int, vmmap: Bool, make: (ScenePreset) -> Stage) {
        let env = ProcessInfo.processInfo.environment
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.autoenablesDefaultLighting = false
        guard let queue = device.makeCommandQueue() else { return }
        let width = Int(size.width)
        let height = Int(size.height)
        func target(_ format: MTLPixelFormat, samples: Int) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: width, height: height, mipmapped: false)
            d.usage = [.renderTarget]
            d.storageMode = .private
            if samples > 1 {
                d.textureType = .type2DMultisample
                d.sampleCount = samples
            }
            return device.makeTexture(descriptor: d)
        }
        guard let resolved = target(.bgra8Unorm_srgb, samples: 1) else { return }
        let pass = MTLRenderPassDescriptor()
        if samples > 1, let multi = target(.bgra8Unorm_srgb, samples: samples) {
            pass.colorAttachments[0].texture = multi
            pass.colorAttachments[0].resolveTexture = resolved
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].texture = resolved
            pass.colorAttachments[0].storeAction = .store
        }
        pass.colorAttachments[0].loadAction = .clear
        let viewport = CGRect(x: 0, y: 0, width: width, height: height)
        var clock = CACurrentMediaTime()
        func summary() -> String { vmmap ? vmmapSummary() : "" }
        print(String(format: "start memory %.0f MB (footprint)", footprintMB()))
        let only = env["TOUR_SCENES"].map { $0.split(separator: ",").compactMap { ScenePreset(rawValue: String($0)) } }
        for preset in only ?? ScenePreset.allCases {
            weak var heldStage: Stage?
            weak var heldScene: SCNScene?
            var built = 0.0
            let drawn: Double = autoreleasepool {
                let started = CACurrentMediaTime()
                let stage = make(preset)
                built = CACurrentMediaTime() - started
                heldStage = stage
                heldScene = stage.scene
                renderer.scene = stage.scene
                renderer.pointOfView = stage.cameraNode
                for _ in 0..<30 {
                    clock += 1.0 / 60
                    stage.update(atTime: clock)
                    guard let buffer = queue.makeCommandBuffer() else { continue }
                    renderer.render(atTime: clock, viewport: viewport, commandBuffer: buffer, passDescriptor: pass)
                    buffer.commit()
                    buffer.waitUntilCompleted()
                }
                let mb = footprintMB()
                renderer.scene = nil
                return mb
            }
            autoreleasepool {
                renderer.scene = nil
                renderer.pointOfView = nil
                // (One frame of nothing, so the renderer lets go of what it drew.)
                if let buffer = queue.makeCommandBuffer() {
                    renderer.render(atTime: clock, viewport: viewport, commandBuffer: buffer, passDescriptor: pass)
                    buffer.commit()
                    buffer.waitUntilCompleted()
                }
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            print(
                String(
                    format: "%@ built in %.2f s, drawn %.0f MB  left %.0f MB  (picture cache %.0f MB)%@%@",
                    preset.rawValue, built, drawn,
                    footprintMB(), Double(Mat.cachedMegabytes), heldStage == nil ? "" : "  STAGE KEPT",
                    heldScene == nil ? "" : "  SCENE KEPT"))
            let lines = summary()
            if !lines.isEmpty { print(lines) }
        }
        autoreleasepool {
            let stand = Stage(
                preset: .fireside, current: AlbumArt(id: "builtin-0", image: Tex.placeholderCover(0)), history: [],
                transparent: true)
            _ = stand
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        print(String(format: "resting memory %.0f MB (footprint)", footprintMB()))
        let lines = summary()
        if !lines.isEmpty { print(lines) }
        if let file = env["BENCH_HEAP"] { inspect("/usr/bin/heap", into: file) }
        // (`BENCH_TRACE=<file>`: what keeps the materials still alive, from `leaks --traceTree` on a few of them.)
        if let file = env["BENCH_TRACE"] {
            inspect("/usr/bin/heap", arguments: ["-addresses=SCNMaterial$"], into: file + ".addresses")
            let text = (try? String(contentsOfFile: file + ".addresses", encoding: .utf8)) ?? ""
            let found = text.split(separator: "\n").compactMap { line -> String? in
                guard let word = line.split(separator: " ").first, word.hasPrefix("0x") else { return nil }
                return String(word)
            }
            let step = max(found.count / 12, 1)
            for (i, address) in found.enumerated() where i % step == 0 {
                inspect("/usr/bin/leaks", arguments: ["--traceTree=\(address)"], into: file + ".\(i)")
            }
        }
        if let hold = env["BENCH_HOLD"].flatMap({ Double($0) }) {
            print("holding pid \(ProcessInfo.processInfo.processIdentifier) for \(hold) s")
            Thread.sleep(forTimeInterval: hold)
        }
    }

    /// Runs a tool that looks at this process (`heap`, `vmmap`) and writes what it says to a file.
    static func inspect(_ tool: String, arguments: [String] = [], into file: String, last: String? = nil) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments + ["\(ProcessInfo.processInfo.processIdentifier)"] + (last.map { [$0] } ?? [])
        FileManager.default.createFile(atPath: file, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: file) else { return }
        task.standardOutput = handle
        task.standardError = handle
        guard (try? task.run()) != nil else { return }
        task.waitUntilExit()
        try? handle.close()
    }

    /// That a picture moved out of memory (`Tex.settled`) draws the same: `2dle --snapshot - --settle-test [--size WxH]`
    /// builds each scene with every picture in memory, draws it at a fixed moment, settles every drawn picture it holds
    /// and draws it at the same moment again. The two must be the same to the last bit.
    static func settleTest(device: MTLDevice, size: CGSize, make: (ScenePreset) -> Stage) -> Int32 {
        let env = ProcessInfo.processInfo.environment
        let only = env["TOUR_SCENES"].map { $0.split(separator: ",").compactMap { ScenePreset(rawValue: String($0)) } }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.autoenablesDefaultLighting = false
        var failed = false
        for preset in only ?? ScenePreset.allCases {
            autoreleasepool {
                Tex.settles = false
                let stage = make(preset)
                renderer.scene = stage.scene
                renderer.pointOfView = stage.cameraNode
                let shotA = renderer.snapshot(atTime: 1.5, with: size, antialiasingMode: .multisampling4X)
                let first = pixels(shotA)
                let before = footprintMB()
                Tex.settles = true
                if env["SETTLE_SKIP"] == nil { stage.settlePictures(all: true) }
                let shotB = renderer.snapshot(atTime: 1.5, with: size, antialiasingMode: .multisampling4X)
                let second = pixels(shotB)
                if let folder = env["SETTLE_OUT"] {
                    for (shot, side) in [(shotA, "a"), (shotB, "b")] {
                        if let cg = shot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                            writePNG(cg, to: URL(fileURLWithPath: folder).appendingPathComponent("\(preset.rawValue)-\(side).png"))
                        }
                    }
                }
                var differ = 0
                var most = 0
                for i in 0..<min(first.count, second.count) where first[i] != second[i] {
                    differ += 1
                    most = max(most, abs(Int(first[i]) - Int(second[i])))
                }
                if differ > 0 || first.isEmpty || first.count != second.count { failed = true }
                print(
                    String(
                        format: "%@: %@ (%d bytes differ, at most %d)  footprint %.0f -> %.0f MB", preset.rawValue,
                        differ == 0 && !first.isEmpty ? "same" : "DIFFERENT", differ, most, before, footprintMB()))
                renderer.scene = nil
            }
        }
        return failed ? 1 : 0
    }

    /// That rain and snow never hang in the air (owner, 2026-10-20: "droplets are frozen"): `2dle --snapshot -
    /// --weather-motion-test [--size WxH] [--framing f]` builds every scene with weather paused (nothing playing, the
    /// record still) in rain and in snow, steps the stage's clock 30 times a second as the paused ambience is drawn, and
    /// draws only what falls (every sheet of rain, snow, rings and drops on glass, picked out by the camera's category
    /// mask) at 2.0 and 2.37 s. Something falling that is drawn and does not move between the two is FROZEN. It also
    /// says whether the paused stage still asks to be drawn (`isAnimating`) and at what pace: something falling on a
    /// frame that stays would hang there however its clock went. (`TOUR_SCENES=a,b` for some of them.)
    static func weatherMotionTest(device: MTLDevice, size: CGSize, make: (ScenePreset) -> Stage) -> Int32 {
        let env = ProcessInfo.processInfo.environment
        let weatherScenes = ScenePreset.allCases.filter { $0.showsWeather || $0 == .rainyNewYork }
        let only = env["TOUR_SCENES"].map { $0.split(separator: ",").compactMap { ScenePreset(rawValue: String($0)) } }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.autoenablesDefaultLighting = false
        // (What falls: the rain sheets (`dropAmount`), the snow (`flakeDensity`, the Winter Garden's `flakeRows`), the
        // rings where it lands (`dropDensity`) and drops on the glass (`rainGlass`).)
        let marks = ["dropAmount", "flakeDensity", "flakeRows", "dropDensity"]
        let fallBit = 1 << 21
        let was = Outdoors.sky
        defer { Outdoors.sky = was }
        var failed = false
        for preset in only ?? weatherScenes {
            for sky in [Outdoors.Sky.rain, .snow] {
                autoreleasepool {
                    Outdoors.sky = sky
                    let stage = make(preset)
                    var sheets = 0
                    stage.scene.rootNode.enumerateHierarchy { node, _ in
                        let shaders = (node.geometry?.materials ?? []).compactMap { $0.shaderModifiers?[.fragment] }
                        guard node.name == "rainGlass" || shaders.contains(where: { s in marks.contains { s.contains($0) } })
                        else { return }
                        node.categoryBitMask |= fallBit
                        sheets += 1
                    }
                    // (Any material whose shader runs on `rainTime` that the stage never moves: a clock that stands still.)
                    var moves = Set(stage.ambientMaterials.map(ObjectIdentifier.init))
                    stage.weatherSheets.forEach { moves.insert(ObjectIdentifier($0.material)) }
                    if let glass = stage.rainGlass { moves.insert(ObjectIdentifier(glass)) }
                    var orphans = Set<String>()
                    stage.scene.rootNode.enumerateHierarchy { node, _ in
                        for material in node.geometry?.materials ?? []
                        where !moves.contains(ObjectIdentifier(material))
                            && (material.shaderModifiers ?? [:]).values.contains(where: { $0.contains("float rainTime;") })
                        {
                            orphans.insert(node.name ?? material.name ?? "?")
                        }
                    }
                    if !orphans.isEmpty {
                        print("\(preset.rawValue) \(sky.rawValue): rainTime never moved on \(orphans.sorted())")
                    }
                    renderer.scene = stage.scene
                    renderer.pointOfView = stage.cameraNode
                    let camera = stage.cameraNode.camera
                    let seen = camera?.categoryBitMask ?? -1
                    var clock: TimeInterval = 0
                    // (`mask` 0: nothing of the scene at all, only what the camera lays over every frame, to tell the fall from.)
                    func shot(at time: TimeInterval, mask: Int = fallBit) -> [UInt8] {
                        while clock < time {
                            clock = min(clock + 1.0 / 30, time)
                            renderer.update(atTime: clock)
                            stage.update(atTime: clock)
                            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.0005))
                        }
                        camera?.categoryBitMask = mask
                        defer { camera?.categoryBitMask = seen }
                        return pixels(renderer.snapshot(atTime: clock, with: size, antialiasingMode: .none))
                    }
                    func apart(_ x: [UInt8], _ y: [UInt8], _ i: Int) -> Bool {
                        abs(Int(x[i]) - Int(y[i])) + abs(Int(x[i + 1]) - Int(y[i + 1])) + abs(Int(x[i + 2]) - Int(y[i + 2]))
                            > 12
                    }
                    let a = shot(at: 2.0)
                    let none = shot(at: 2.0, mask: 1 << 22)
                    let b = shot(at: 2.37)
                    var drawn = 0
                    var moved = 0
                    var i = 0
                    while i + 3 < min(a.count, b.count, none.count) {
                        if apart(a, none, i) || apart(b, none, i) { drawn += 1 }
                        if apart(a, b, i) { moved += 1 }
                        i += 4
                    }
                    // (A fall that shows at all and changes in under a twentieth of the pixels it covers is standing still.)
                    let falls = drawn >= 200
                    let frozen = falls && (moved * 20 < drawn || !stage.isAnimating)
                    if frozen { failed = true }
                    print(
                        String(
                            format: "%@ %@: %@  (%d sheets, %d px drawn, %d px moved in 0.37 s; paused stage %@, ambience %d a second)",
                            preset.rawValue, sky.rawValue, !falls ? "nothing falling" : frozen ? "FROZEN" : "falls",
                            sheets, drawn, moved, stage.isAnimating ? "drawn" : "NOT DRAWN", stage.ambientFrameRate))
                    renderer.scene = nil
                }
            }
        }
        return failed ? 1 : 0
    }

    /// What packing the pictures changes (`Packing`): `2dle --snapshot - --pack-test [--size WxH] [--quality q]`
    /// builds each scene with SceneKit's own pictures, draws it at a fixed moment, packs them and draws it at the same
    /// moment again, in one process, so that nothing else differs. `SPINDLE_PACK=raw` (our own textures, uncompressed)
    /// must draw the same to the bit; compressed, it says how far apart the two are over the frame and in its worst
    /// 16x16 patch, and with `PACK_TEST_OUT=<folder>` writes both pictures there.
    static func packTest(device: MTLDevice, size: CGSize, make: (ScenePreset) -> Stage) -> Int32 {
        let env = ProcessInfo.processInfo.environment
        let only = env["TOUR_SCENES"].map { $0.split(separator: ",").compactMap { ScenePreset(rawValue: String($0)) } }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.autoenablesDefaultLighting = false
        var failed = false
        let raw = Packing.mode == .raw
        for preset in only ?? ScenePreset.allCases {
            autoreleasepool {
                Packing.held = true
                let stage = make(preset)
                Packing.held = false
                if env["PACK_TEST_NOSSAO"] != nil { stage.cameraNode.camera?.screenSpaceAmbientOcclusionIntensity = 0 }
                if env["PACK_TEST_NOSHADOW"] != nil {
                    stage.scene.rootNode.enumerateHierarchy { node, _ in node.light?.castsShadow = false }
                }
                renderer.scene = stage.scene
                renderer.pointOfView = stage.cameraNode
                let a = renderer.snapshot(atTime: 1.5, with: size, antialiasingMode: .multisampling4X)
                let first = pixels(a)
                let before = footprintMB()
                // (`PACK_TEST_EACH=1`: each picture packed alone, and those that change the frame named.)
                if env["PACK_TEST_EACH"] != nil {
                    for job in Packing.jobs(stage.scene.rootNode) {
                        let was = job.property.contents
                        let blend = job.material.blendMode
                        defer { job.material.blendMode = blend }
                        guard Packing.apply(job, halve: DrawingQuality.current == .minimum) else { continue }
                        let shot = renderer.snapshot(atTime: 1.5, with: size, antialiasingMode: .multisampling4X)
                        let one = pixels(shot)
                        if let folder = env["PACK_TEST_OUT"], let mark = env["PACK_TEST_EACH"], job.label.contains(mark),
                            let cg = shot.cgImage(forProposedRect: nil, context: nil, hints: nil)
                        {
                            writePNG(cg, to: URL(fileURLWithPath: folder).appendingPathComponent("\(preset.rawValue)-one.png"))
                        }
                        let score = Packing.Score(first, one, width: Int(size.width), height: Int(size.height))
                        if score.psnr < 100 {
                            let p = job.property
                            let kind =
                                was.map { CFGetTypeID($0 as CFTypeRef) == CGImage.typeID ? "cg" : ($0 is URL ? "url" : "?") }
                                ?? "-"
                            let t = p.contents as? MTLTexture
                            print(
                                String(
                                    format: "  %@: psnr %.1f, worst %.1f  [%@ %dx%d mips %d fmt %d; min %d mag %d mip %d wrap %d/%d aniso %.0f comps %d] "
                                        + "blend \(blend.rawValue)->\(job.material.blendMode.rawValue) transparency \(job.material.transparency) "
                                        + "transparent \(job.material.transparent.contents != nil) tmode \(job.material.transparencyMode.rawValue) "
                                        + "shaders \(job.material.shaderModifiers?.keys.map(\.rawValue) ?? []) lit \(job.material.lightingModel.rawValue) "
                                        + "depthw \(job.material.writesToDepthBuffer)",
                                    job.label, score.psnr, score.worst, kind, t?.width ?? 0, t?.height ?? 0,
                                    t?.mipmapLevelCount ?? 0, Int(t?.pixelFormat.rawValue ?? 0), p.minificationFilter.rawValue,
                                    p.magnificationFilter.rawValue, p.mipFilter.rawValue, p.wrapS.rawValue, p.wrapT.rawValue,
                                    p.maxAnisotropy, p.textureComponents.rawValue))
                        }
                        job.property.contents = was
                    }
                }
                Packing.pack(stage.scene.rootNode)
                let b = renderer.snapshot(atTime: 1.5, with: size, antialiasingMode: .multisampling4X)
                let second = pixels(b)
                let after = footprintMB()
                var differ = 0
                var most = 0
                for i in 0..<min(first.count, second.count) where first[i] != second[i] {
                    differ += 1
                    most = max(most, abs(Int(first[i]) - Int(second[i])))
                }
                let score = Packing.Score(first, second, width: Int(size.width), height: Int(size.height))
                if first.isEmpty || first.count != second.count || (raw && differ > 0) { failed = true }
                print(
                    String(
                        format: "%@: %@ (%d bytes differ, at most %d; psnr %.1f dB, worst 16x16 %.1f dB)  footprint %.0f -> %.0f MB",
                        preset.rawValue, differ == 0 && !first.isEmpty ? "same" : "different", differ, most,
                        score.psnr, score.worst, before, after))
                if let folder = env["PACK_TEST_OUT"] {
                    for (image, side) in [(a, "a"), (b, "b")] {
                        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                            writePNG(cg, to: URL(fileURLWithPath: folder).appendingPathComponent("\(preset.rawValue)-\(side).png"))
                        }
                    }
                }
                renderer.scene = nil
            }
        }
        return failed ? 1 : 0
    }

    /// A rendered picture's bytes, RGBA.
    static func pixels(_ image: NSImage) -> [UInt8] {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return bytes
    }

    /// That a stage going never takes anything from a stage still here (see `Keeping`): `2dle --snapshot -
    /// --leave-test [--size WxH]` builds each scene after another (and after itself, as a change of turntable does,
    /// and after the bare stand-in, as waking from a rest does), draws the newer at a fixed moment, lets the older go,
    /// and draws the newer at the same moment again. The two must be the same to the last bit.
    static func leaveTest(device: MTLDevice, size: CGSize, make: (ScenePreset) -> Stage) -> Int32 {
        let env = ProcessInfo.processInfo.environment
        let only = env["TOUR_SCENES"].map { $0.split(separator: ",").compactMap { ScenePreset(rawValue: String($0)) } }
        let presets = only ?? ScenePreset.allCases
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.autoenablesDefaultLighting = false
        func pixels(_ stage: Stage) -> [UInt8] {
            renderer.scene = stage.scene
            renderer.pointOfView = stage.cameraNode
            let image = renderer.snapshot(atTime: 1.5, with: size, antialiasingMode: .multisampling4X)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            bytes.withUnsafeMutableBytes { raw in
                CGContext(
                    data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                    bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                    .draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }
            return bytes
        }
        var failed = false
        var pairs: [(ScenePreset?, ScenePreset)] = []
        for (i, preset) in presets.enumerated() {
            pairs.append((preset, preset))
            pairs.append((presets[(i + presets.count - 1) % presets.count], preset))
            pairs.append((nil, preset))
        }
        for (before, preset) in pairs {
            autoreleasepool {
                var older: Stage? =
                    before.map(make)
                    ?? Stage(
                        preset: .fireside, current: AlbumArt(id: "builtin-0", image: Tex.placeholderCover(0)),
                        history: [], transparent: true)
                // (`LEAVE_UNDRAWN=1`: the older is never drawn, so that the newer makes every texture itself.)
                if let older, env["LEAVE_UNDRAWN"] == nil {
                    renderer.scene = older.scene
                    renderer.pointOfView = older.cameraNode
                    _ = renderer.snapshot(atTime: 1.5, with: CGSize(width: 64, height: 40), antialiasingMode: .none)
                }
                let newer = make(preset)
                let first = pixels(newer)
                renderer.scene = nil
                // (`LEAVE_CONTROL=1`: the older is kept, for seeing how alike two pictures of one moment are anyway.)
                if env["LEAVE_CONTROL"] == nil { older = nil }
                // (`LEAVE_WAIT=<s>`: and that long before the second, for seeing what moves with the wall clock.)
                if let wait = env["LEAVE_WAIT"].flatMap({ Double($0) }) { Thread.sleep(forTimeInterval: wait) }
                let second = pixels(newer)
                var differ = 0
                var most = 0
                for i in 0..<min(first.count, second.count) where first[i] != second[i] {
                    differ += 1
                    most = max(most, abs(Int(first[i]) - Int(second[i])))
                }
                if differ > 0 || first.isEmpty || first.count != second.count { failed = true }
                print(
                    "\(before?.rawValue ?? "stand-in") -> \(preset.rawValue): \(differ == 0 && !first.isEmpty ? "same" : "DIFFERENT") (\(differ) bytes differ, at most \(most))"
                )
            }
        }
        return failed ? 1 : 0
    }

    /// Every picture a stage's materials, lights and camera hold, largest first, with what it would come to as a
    /// texture (four bytes a pixel, a third more with its mip maps): `2dle --snapshot - --texture-report --scene <preset>`.
    static func textureReport(stage: Stage) {
        struct Seen {
            var label: String
            var width = 0, height = 0
            var uses = 0
            var where_: Set<String> = []
        }
        var seen: [String: Seen] = [:]
        func note(_ contents: Any?, _ place: String, mip: Bool) {
            guard let contents else { return }
            var key = ""
            var w = 0
            var h = 0
            var label = ""
            if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
                let image = contents as! CGImage
                key = "cg:\(Unmanaged.passUnretained(image).toOpaque())"
                w = image.width
                h = image.height
                label =
                    (image.utType != nil
                        ? "CGImage file"
                        : (Tex.noted.contains(ObjectIdentifier(image)) ? "CGImage settled" : "CGImage drawn"))
                    + (image.colorSpace?.model == .monochrome ? " gray" : "")
            } else if let image = contents as? NSImage {
                key = "ns:\(ObjectIdentifier(image))"
                let rep = image.representations.first
                w = rep?.pixelsWide ?? Int(image.size.width)
                h = rep?.pixelsHigh ?? Int(image.size.height)
                label = "NSImage"
            } else if let url = contents as? URL ?? (contents as? String).map({ URL(fileURLWithPath: $0) }) {
                key = "url:\(url.path)"
                label = url.lastPathComponent
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                {
                    w = p[kCGImagePropertyPixelWidth] as? Int ?? 0
                    h = p[kCGImagePropertyPixelHeight] as? Int ?? 0
                    if (p[kCGImagePropertyColorModel] as? String) == (kCGImagePropertyColorModelGray as String) {
                        label += " gray"
                    }
                }
            } else if let texture = contents as? MTLTexture {
                key = "mtl:\(ObjectIdentifier(texture as AnyObject))"
                w = texture.width
                h = texture.height
                label = "MTLTexture"
            } else if let array = contents as? [Any] {
                for (i, item) in array.enumerated() { note(item, place + "[\(i)]", mip: mip) }
                return
            } else {
                return
            }
            var entry = seen[key] ?? Seen(label: label, width: w, height: h)
            entry.uses += 1
            if entry.where_.count < 4 { entry.where_.insert(place) }
            seen[key] = entry
        }
        func properties(_ m: SCNMaterial) -> [(String, SCNMaterialProperty)] {
            var list: [(String, SCNMaterialProperty)] = [
                ("diffuse", m.diffuse), ("normal", m.normal), ("roughness", m.roughness), ("metalness", m.metalness),
                ("ambientOcclusion", m.ambientOcclusion), ("emission", m.emission), ("multiply", m.multiply),
                ("transparent", m.transparent), ("specular", m.specular), ("reflective", m.reflective),
                ("selfIllumination", m.selfIllumination), ("displacement", m.displacement),
                ("clearCoat", m.clearCoat), ("clearCoatRoughness", m.clearCoatRoughness),
                ("clearCoatNormal", m.clearCoatNormal), ("ambient", m.ambient),
            ]
            // (Pictures handed to a shader modifier by name.)
            let text = (m.shaderModifiers ?? [:]).values.joined(separator: "\n")
            let pattern = try! NSRegularExpression(pattern: "texture2d<float>\\s+(\\w+)\\s*;")
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let name = String(text[range])
                if let p = m.value(forKey: name) as? SCNMaterialProperty { list.append((name, p)) }
            }
            return list
        }
        var materials: [(SCNMaterial, String)] = []
        var known = Set<ObjectIdentifier>()
        stage.scene.rootNode.enumerateHierarchy { node, _ in
            let name = node.name ?? "-"
            var list = node.geometry?.materials ?? []
            list += ScenePieces.materials(welded: node)
            for m in list where !known.contains(ObjectIdentifier(m)) {
                known.insert(ObjectIdentifier(m))
                materials.append((m, (m.name ?? "?") + "@" + name))
            }
            if let light = node.light { note(light.gobo?.contents, "gobo@\(name)", mip: false) }
        }
        for (m, place) in materials {
            for (slot, p) in properties(m) {
                note(p.contents, "\(place).\(slot)", mip: p.mipFilter != .none)
            }
        }
        note(stage.scene.background.contents, "background", mip: false)
        note(stage.scene.lightingEnvironment.contents, "lightingEnvironment", mip: false)
        note(stage.cameraNode.camera?.colorGrading.contents, "colorGrading", mip: false)
        let rows = seen.values.sorted { $0.width * $0.height > $1.width * $1.height }
        let total = rows.reduce(0) { $0 + $1.width * $1.height * 4 }
        let drawn = rows.filter { $0.label.hasPrefix("CGImage drawn") }.reduce(0) { $0 + $1.width * $1.height * 4 }
        let gray = rows.filter { $0.label.hasSuffix(" gray") }.reduce(0) { $0 + $1.width * $1.height * 4 }
        print(
            String(
                format: "drawn (not from a file): %.0f MB; one channel (grey) but 4 bytes a pixel: %.0f MB",
                Double(drawn) / 1_048_576, Double(gray) / 1_048_576))
        print(
            String(
                format: "%@: %d pictures, %.0f MB at 4 bytes a pixel (%.0f MB with mip maps), %d materials",
                stage.preset.rawValue, rows.count, Double(total) / 1_048_576, Double(total) * 4 / 3 / 1_048_576,
                materials.count))
        for row in rows.prefix(Int(ProcessInfo.processInfo.environment["REPORT_ROWS"] ?? "45") ?? 45) {
            print(
                String(
                    format: "%5d x %-5d %6.1f MB  x%-3d %@  %@", row.width, row.height,
                    Double(row.width * row.height * 4) / 1_048_576, row.uses, row.label,
                    row.where_.sorted().joined(separator: ", ")))
        }
    }

    /// What `vmmap --summary` says of this process: the kinds of memory that matter here, or every line with
    /// `BENCH_VMMAP=all`.
    static func vmmapSummary() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/vmmap")
        task.arguments = ["--summary", "\(ProcessInfo.processInfo.processIdentifier)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        if ProcessInfo.processInfo.environment["BENCH_VMMAP"] == "all" { return text }
        let wanted = [
            "IOAccelerator", "CG ", "MALLOC", "CoreImage", "IOSurface", "CoreAnimation", "Image IO", "SceneKit",
            "TOTAL", "DefaultMallocZone", "QuartzCore", "Foundation",
        ]
        return text.split(separator: "\n")
            .filter { line in wanted.contains { line.hasPrefix($0) } }
            .map { "    " + $0 }.joined(separator: "\n")
    }

    /// The process's physical footprint in MB (what Activity Monitor calls Memory).
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}

/// How smoothly the panel scrolls: launched with `--settings` and `SPINDLE_SCROLL_BENCH=<file>`, the list is run to its
/// end and back, twice, by itself, and the file is told how the frames came: how far apart, how many came late, and how
/// much of a processor the app took meanwhile. (`SPINDLE_SCROLL_OPEN=scenes|decks|clocks|none` unfolds another section first.)
final class ScrollBench: NSObject {
    private static var running: ScrollBench?
    private let scroll: NSScrollView
    private let file: String
    private var link: CADisplayLink?
    private var began = 0.0, last = 0.0, cpu0 = 0.0
    private var gaps: [Double] = []
    private let seconds = 8.0

    static func start(in window: NSWindow, to file: String) {
        guard let root = window.contentView else { return }
        var lists: [NSScrollView] = []
        func look(_ view: NSView) {
            if let list = view as? NSScrollView { lists.append(list) }
            view.subviews.forEach(look)
        }
        look(root)
        guard
            let scroll = lists.max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) })
        else {
            try? "no list found\n".write(toFile: file, atomically: true, encoding: .utf8)
            return
        }
        let bench = ScrollBench(scroll: scroll, file: file)
        running = bench
        bench.begin()
    }

    private init(scroll: NSScrollView, file: String) {
        self.scroll = scroll
        self.file = file
    }

    private func begin() {
        began = CACurrentMediaTime()
        cpu0 = processCPUSeconds()
        let link = scroll.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        if last > 0 { gaps.append(now - last) }
        last = now
        let t = now - began
        guard t < seconds else {
            finish()
            return
        }
        let range = max((scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height, 0)
        // (To the end and back twice, easing at each turn as a hand does.)
        let y = range * (1 - cos(t / seconds * 4 * .pi)) / 2
        scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func finish() {
        link?.invalidate()
        link = nil
        let wall = CACurrentMediaTime() - began
        let cpu = processCPUSeconds() - cpu0
        let sorted = gaps.sorted()
        guard !sorted.isEmpty else { return }
        let usual = sorted[sorted.count / 2]
        let late = gaps.filter { $0 > usual * 1.5 }.count
        let range = max((scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height, 0)
        let line = String(
            format:
                "frames %d  usual %.2f ms  mean %.2f ms  p95 %.2f ms  p99 %.2f ms  worst %.2f ms  late %d (%.1f%%)  cpu %.0f%%  list %.0f pt\n",
            gaps.count, usual * 1000, gaps.reduce(0, +) / Double(gaps.count) * 1000,
            sorted[min(sorted.count - 1, sorted.count * 95 / 100)] * 1000,
            sorted[min(sorted.count - 1, sorted.count * 99 / 100)] * 1000, (sorted.last ?? 0) * 1000, late,
            Double(late) / Double(gaps.count) * 100,
            cpu / wall * 100, range)
        if let handle = FileHandle(forWritingAtPath: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: file, atomically: true, encoding: .utf8)
        }
        ScrollBench.running = nil
    }
}

/// The CPU time this process has used so far (user and system), in seconds.
func processCPUSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(
        usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
}

/// What the graphics chip is asked to hold during a bench (`BENCH_GPU=1`): every texture and buffer made on the device,
/// by kind, for finding what the "IOAccelerator" memory is.
enum GPUCount {
    private struct Made {
        var label: String
        var bytes: Int
    }
    private static var made: [Made] = []
    private static let lock = NSLock()

    private static func bytesPerPixel(_ format: MTLPixelFormat) -> Int {
        switch format {
        case .r8Unorm, .a8Unorm, .r8Snorm, .r8Uint, .stencil8: return 1
        case .r16Float, .rg8Unorm, .r16Unorm, .depth16Unorm: return 2
        case .rgba16Float, .rg32Float, .rgba16Unorm, .depth32Float_stencil8: return 8
        case .rgba32Float: return 16
        default: return 4
        }
    }

    private static func note(_ label: String, _ bytes: Int) {
        lock.lock()
        made.append(Made(label: label, bytes: bytes))
        lock.unlock()
    }

    static func watch(_ device: MTLDevice) {
        guard let cls: AnyClass = object_getClass(device) else { return }
        let textureSelector = NSSelectorFromString("newTextureWithDescriptor:")
        if let method = class_getInstanceMethod(cls, textureSelector) {
            typealias Fn = @convention(c) (AnyObject, Selector, MTLTextureDescriptor) -> AnyObject?
            let original = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            let block: @convention(block) (AnyObject, MTLTextureDescriptor) -> AnyObject? = { this, d in
                let faces = d.textureType == .typeCube || d.textureType == .typeCubeArray ? 6 : 1
                var bytes = 0
                for level in 0..<max(d.mipmapLevelCount, 1) {
                    bytes += max(d.width >> level, 1) * max(d.height >> level, 1) * max(d.depth >> level, 1)
                }
                bytes *= bytesPerPixel(d.pixelFormat) * faces * d.arrayLength * max(d.sampleCount, 1)
                let target = d.usage.contains(.renderTarget)
                note(
                    "texture \(target ? "target" : "picture") format \(d.pixelFormat.rawValue) \(d.width)x\(d.height) mips \(d.mipmapLevelCount) samples \(d.sampleCount) faces \(faces)",
                    bytes)
                return original(this, textureSelector, d)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        let lengthSelector = NSSelectorFromString("newBufferWithLength:options:")
        if let method = class_getInstanceMethod(cls, lengthSelector) {
            typealias Fn = @convention(c) (AnyObject, Selector, Int, UInt) -> AnyObject?
            let original = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            let block: @convention(block) (AnyObject, Int, UInt) -> AnyObject? = { this, length, options in
                note("buffer", length)
                return original(this, lengthSelector, length, options)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        let bytesSelector = NSSelectorFromString("newBufferWithBytes:length:options:")
        if let method = class_getInstanceMethod(cls, bytesSelector) {
            typealias Fn = @convention(c) (AnyObject, Selector, UnsafeRawPointer, Int, UInt) -> AnyObject?
            let original = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            let block: @convention(block) (AnyObject, UnsafeRawPointer, Int, UInt) -> AnyObject? = {
                this, pointer, length, options in
                note("buffer", length)
                return original(this, bytesSelector, pointer, length, options)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }

    static func report() {
        lock.lock()
        let all = made
        lock.unlock()
        var kinds: [String: (count: Int, bytes: Int)] = [:]
        for m in all {
            let kind = m.label == "buffer" ? "buffers" : m.label.split(separator: " ").prefix(4).joined(separator: " ")
            let k = kinds[kind] ?? (0, 0)
            kinds[kind] = (k.count + 1, k.bytes + m.bytes)
        }
        print(String(format: "GPU made: %.0f MB in all", Double(all.reduce(0) { $0 + $1.bytes }) / 1_048_576))
        for (kind, v) in kinds.sorted(by: { $0.value.bytes > $1.value.bytes }) {
            print(String(format: "  %6.1f MB  %4d  %@", Double(v.bytes) / 1_048_576, v.count, kind))
        }
        let rows = Int(ProcessInfo.processInfo.environment["REPORT_ROWS"] ?? "25") ?? 25
        for m in all.sorted(by: { $0.bytes > $1.bytes }).prefix(rows) {
            print(String(format: "  %6.1f MB  %@", Double(m.bytes) / 1_048_576, m.label))
        }
    }
}
