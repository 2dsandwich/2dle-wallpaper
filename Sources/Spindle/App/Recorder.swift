import AVFoundation
import AppKit
import Metal
import SceneKit

/// A short film of the scene as it stands, to keep or to send to somebody: 1920 dots across, sixty pictures a
/// second, written out as a movie in Movies/2dle. It stops by itself after half a minute if nobody stops it first.
/// (There is no sound in it: the music is not 2dle's to copy.)
///
/// The pictures are not taken off the screen. Each time the wallpaper has drawn a frame it hands the scene over
/// (`capture`), and the scene is drawn once more, at the film's own size, into a picture that never goes on screen:
/// so the film is the same whatever is in front of the desktop, whatever quality the wallpaper is being drawn at,
/// and it costs the wallpaper nothing it can be seen to lose.
final class Recorder {
    /// The longest a film runs, in seconds; how wide it is, in dots; and how many pictures it has in a second.
    static let longest = 30.0
    static let width = 1920
    static let rate = 60
    /// Posted while one is being made (its object: how many seconds there are of it so far), and when it is done
    /// (its object: the file, or nothing if it could not be made).
    static let ticked = Notification.Name("SpindleRecordingTicked")
    static let finished = Notification.Name("SpindleRecordingFinished")

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var file: URL?
    private var folder: URL?
    private var name = ""
    private var began: Double?
    private var clock: Timer?
    private var failed = false
    /// (Everything to do with the film's file is done on this queue, one thing after another.)
    private let queue = DispatchQueue(label: "2dle.recorder", qos: .userInitiated)

    // What draws the film's pictures: a renderer of its own, somewhere to draw (smoothed, then brought down to one
    // sample), and a few pictures to draw into in turn, since one is still being read while the next is drawn.
    private var renderer: SCNRenderer?
    private var commands: MTLCommandQueue?
    private var smooth: MTLTexture?
    private var frames: [MTLTexture] = []
    private var busy: [Bool] = []
    private var size = (width: 0, height: 0)
    private let lock = NSLock()

    private(set) var running = false

    /// Starts a film in `folder`, named for `name`. The file itself is begun with the first picture, when its shape is known.
    func start(in folder: URL, named name: String) {
        guard !running else { return }
        self.folder = folder
        self.name = name
        began = nil
        failed = false
        running = true
        let clock = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.running else { return }
            let seconds = self.began.map { CACurrentMediaTime() - $0 } ?? 0
            if seconds >= Self.longest || self.failed {
                self.stop()
                return
            }
            NotificationCenter.default.post(name: Self.ticked, object: seconds)
        }
        RunLoop.main.add(clock, forMode: .common)
        self.clock = clock
    }

    /// One picture of the film: the scene as it stands, seen from `pointOfView`, as wide over high as `aspect`.
    /// Called wherever the scene has just been drawn (not the main thread, as a rule), and not to be called twice at once.
    func capture(scene: SCNScene, pointOfView: SCNNode, device: MTLDevice, aspect: CGFloat) {
        guard running, !failed else { return }
        let now = CACurrentMediaTime()
        if renderer == nil || renderer?.device !== device { prepare(device: device, aspect: aspect) }
        guard let renderer, let commands, let smooth else {
            failed = true
            return
        }
        // (A picture that is still being read is not drawn over: with none free, this frame is let go by.)
        lock.lock()
        let free = busy.firstIndex(of: false)
        if let free { busy[free] = true }
        lock.unlock()
        guard let free, let buffer = commands.makeCommandBuffer() else { return }
        let target = frames[free]
        renderer.scene = scene
        renderer.pointOfView = pointOfView
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = smooth
        pass.colorAttachments[0].resolveTexture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        renderer.render(
            atTime: now, viewport: CGRect(x: 0, y: 0, width: size.width, height: size.height), commandBuffer: buffer,
            passDescriptor: pass)
        if target.storageMode == .managed, let blit = buffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        let first = began ?? now
        if began == nil { began = now }
        let seconds = now - first
        buffer.addCompletedHandler { [weak self] _ in
            self?.queue.async {
                self?.write(target, at: seconds)
                self?.lock.lock()
                self?.busy[free] = false
                self?.lock.unlock()
            }
        }
        buffer.commit()
    }

    private func prepare(device: MTLDevice, aspect: CGFloat) {
        // (Even both ways, which is what the film's format wants.)
        size = (Self.width, Int((CGFloat(Self.width) / max(aspect, 0.2)).rounded()) / 2 * 2)
        func target(samples: Int) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb, width: size.width, height: size.height, mipmapped: false)
            d.usage = [.renderTarget]
            if samples > 1 {
                d.textureType = .type2DMultisample
                d.sampleCount = samples
                d.storageMode = .private
            } else {
                d.storageMode = device.hasUnifiedMemory ? .shared : .managed
            }
            return device.makeTexture(descriptor: d)
        }
        renderer = SCNRenderer(device: device, options: nil)
        renderer?.autoenablesDefaultLighting = false
        commands = device.makeCommandQueue()
        smooth = target(samples: 4)
        frames = (0..<4).compactMap { _ in target(samples: 1) }
        busy = frames.map { _ in false }
        if frames.count < 4 { smooth = nil }
    }

    /// (On the queue.) Puts one drawn picture into the film, beginning the film's file if this is the first.
    private func write(_ picture: MTLTexture, at seconds: Double) {
        guard running || writer != nil, !failed else { return }
        if writer == nil {
            guard let folder else {
                failed = true
                return
            }
            let file = folder.appendingPathComponent(name + ".mov")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: file)
                let writer = try AVAssetWriter(outputURL: file, fileType: .mov)
                let input = AVAssetWriterInput(
                    mediaType: .video,
                    outputSettings: [
                        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: picture.width,
                        AVVideoHeightKey: picture.height,
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: 24_000_000, AVVideoExpectedSourceFrameRateKey: Self.rate,
                            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                        ],
                    ])
                input.expectsMediaDataInRealTime = true
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: picture.width,
                        kCVPixelBufferHeightKey as String: picture.height,
                    ])
                guard writer.canAdd(input) else {
                    failed = true
                    return
                }
                writer.add(input)
                guard writer.startWriting() else {
                    failed = true
                    return
                }
                writer.startSession(atSourceTime: .zero)
                self.writer = writer
                self.input = input
                self.adaptor = adaptor
                self.file = file
            } catch {
                failed = true
                return
            }
        }
        guard let input, let adaptor, input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let bytes = CVPixelBufferGetBaseAddress(buffer) {
            picture.getBytes(
                bytes, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                from: MTLRegionMake2D(0, 0, picture.width, picture.height), mipmapLevel: 0)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        // (Stamped with when it was really drawn: a Mac that cannot keep up makes a film that stutters, not one that runs fast.)
        adaptor.append(buffer, withPresentationTime: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    /// Ends the film and says where it is (see `finished`).
    func stop() {
        guard running else { return }
        running = false
        clock?.invalidate()
        clock = nil
        queue.async { [self] in
            let writer = self.writer
            let file = self.file
            let bad = failed
            input?.markAsFinished()
            self.writer = nil
            input = nil
            adaptor = nil
            self.file = nil
            guard let writer, !bad else {
                DispatchQueue.main.async { NotificationCenter.default.post(name: Self.finished, object: nil) }
                return
            }
            writer.finishWriting {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Self.finished, object: writer.status == .completed ? file : nil)
                }
            }
        }
    }

    /// For `--record-test <folder>`: two seconds of a scene, drawn and written as the app would, to see that a film
    /// can be made at all. Says how it went.
    static func test(stage: Stage, device: MTLDevice, folder: String) -> String {
        let recorder = Recorder()
        var made: URL??
        let watch = NotificationCenter.default.addObserver(forName: finished, object: nil, queue: .main) {
            made = .some($0.object as? URL)
        }
        defer { NotificationCenter.default.removeObserver(watch) }
        recorder.start(in: URL(fileURLWithPath: folder, isDirectory: true), named: "record-test")
        let until = CACurrentMediaTime() + 2
        var drawn = 0
        while CACurrentMediaTime() < until {
            stage.update(atTime: CACurrentMediaTime())
            recorder.capture(scene: stage.scene, pointOfView: stage.cameraNode, device: device, aspect: 1.54)
            drawn += 1
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 120))
        }
        recorder.stop()
        while made == nil { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        guard case .some(.some(let file)) = made else { return "FAIL nothing written" }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        return "\(size > 50_000 ? "PASS" : "FAIL") \(drawn) pictures drawn, \(size) bytes, \(file.lastPathComponent)"
    }
}
