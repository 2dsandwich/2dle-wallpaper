import CryptoKit
import ImageIO
import Metal
import SceneKit

/// The pictures of a stage, packed for the graphics chip (light pass 2, 2026-10-19).
///
/// SceneKit makes every picture a texture of 4 bytes a pixel (with its mip maps a third more), and those textures were
/// most of a scene's memory. Here a stage's pictures are made textures of our own, handed to SceneKit as `MTLTexture`
/// contents, in one of two ways:
/// - compressed, at every quality: ASTC with 4x4 blocks (its finest), a byte a pixel, encoded once by ImageIO and
///   kept on the disk (`folder`), so that a launch or a wake from a rest reads them and encodes nothing. Each picture
///   is decoded again as it is encoded and compared with itself; one that does not come back close enough
///   (`passes`) is never compressed, and the file says so.
/// - at half size each way at `minimum` (its largest mip level left off), compressed or not.
/// Left as SceneKit makes them: the covers, the record's label and lettering and anything printed with the
/// never-clip shader (`Mat.holdsHighlights`), normal maps (only halved, at `minimum`), one-channel pictures (already a
/// byte a pixel), a diffuse picture with any transparency or on a see-through material (see `apply`), transparent
/// slots, pictures of more than 8 bits a channel, small ones, the Library's still, the lights' gobos and anything set
/// after the stage is built.
/// The textures are laid out as SceneKit lays out its own (found by reading SceneKit's back: sRGB for the colour
/// slots and shader pictures, linear for the rest, alpha premultiplied in linear light, mip maps by the same rule and
/// made the same way). `SPINDLE_PACK=raw` makes them uncompressed, for checking that: drawn with them, a frame is the
/// same but for a few levels on some edge pixels (`--pack-test`).
/// (`SPINDLE_PACK=0` leaves every picture to SceneKit, for comparing; `SPINDLE_PACK_CACHE=<folder>` keeps the
/// compressed pictures somewhere else; `SPINDLE_PACK_REPORT=1` says what is encoded, how well, and what is not packed.)
enum Packing {
    enum Mode { case off, raw, compressed }
    /// (Held, a stage is built with SceneKit's own pictures, for `--pack-test` to pack afterwards.)
    static var held = false
    static var mode: Mode = {
        switch ProcessInfo.processInfo.environment["SPINDLE_PACK"] {
        case "0": return .off
        case "raw": return .raw
        default: return .compressed
        }
    }()
    private static let device = MTLCreateSystemDefaultDevice()
    private static let queue = device?.makeCommandQueue()
    /// ASTC is drawn by every Apple graphics chip (not by Intel Macs', which keep SceneKit's pictures, halved at `minimum`).
    private static let astc = device?.supportsFamily(.apple2) == true
    private static let lock = NSLock()
    /// Bump when the encoding or the file changes: files of another version are not read.
    private static let version: UInt32 = 3
    /// Pictures smaller than this (in pixels) are left as they are.
    private static let smallest = 128 * 128

    // MARK: Where a picture came from

    /// Pictures read from our files, and the file each came from (its path, size and date): such a picture is found on
    /// the disk by that alone, without decoding it.
    private static let origins = NSMapTable<AnyObject, NSString>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
    /// Drawn pictures already looked at, and what their pixels hash to.
    private static let hashes = NSMapTable<AnyObject, NSString>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
    /// Textures made, by what they were made of (each kept only while something holds it).
    private static let made = NSMapTable<NSString, AnyObject>(keyOptions: .strongMemory, valueOptions: .weakMemory)

    /// Called as a picture is read from a file (`loadImage`).
    static func note(_ image: CGImage, from url: URL, maxPixelSize: Int?) {
        guard mode != .off, let stamp = fileStamp(url) else { return }
        lock.lock()
        origins.setObject("\(stamp)|\(maxPixelSize ?? 0)" as NSString, forKey: image)
        lock.unlock()
    }

    /// Notes what a drawn picture's pixels hash to (its layout too), and returns it: what it is found by on the disk.
    @discardableResult
    static func noteDrawn(_ image: CGImage, bytes: UnsafePointer<UInt8>?, count: Int) -> String? {
        guard mode != .off, let bytes else { return nil }
        var hash = SHA256()
        hash.update(data: UnsafeRawBufferPointer(start: bytes, count: count))
        let layout = "\(image.width)x\(image.height) \(image.bytesPerRow) \(image.bitsPerPixel) \(image.bitmapInfo.rawValue)"
        hash.update(data: Data(layout.utf8))
        let key = "drawn:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
        lock.lock()
        hashes.setObject(key as NSString, forKey: image)
        lock.unlock()
        return key
    }

    private static func fileStamp(_ url: URL) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = a[.size] as? Int, let date = a[.modificationDate] as? Date
        else { return nil }
        return "file:\(url.path)|\(size)|\(date.timeIntervalSince1970)"
    }

    // MARK: Holding SceneKit back

    /// SceneKit makes a copy of a picture the moment a property is given it (two, in fact, held by the material for as
    /// long as it lives), and lets them go only once it has made its texture of it. Given a texture of ours instead
    /// before drawing, the copies stay: a stage's pictures packed were as heavy as before. So while a stage is built,
    /// SceneKit is not told of the pictures its properties are given (its private `_updateC3DImageWithContents:`,
    /// which does that, is held back on the building thread; the property itself holds the picture as always and
    /// says so if asked). Once the stage is packed, whatever was not packed is handed on to SceneKit as it would have
    /// been (`finish`); so is anything drawn while the stage is built (`handOn(under:)`, the Library's still).
    /// Should a later macOS not have that method, nothing is held back and packing still works, heavier.
    private typealias Update = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    private static var originalUpdate: Update?
    private static let updateSelector = NSSelectorFromString("_updateC3DImageWithContents:")
    private static let heldKey = "2dle.packing.held"
    private final class Held { var list: [(property: SCNMaterialProperty, contents: AnyObject)] = [] }

    private static let parentIvar = class_getInstanceVariable(SCNMaterialProperty.self, "_parent")
    private static let installed: Bool = {
        guard let method = class_getInstanceMethod(SCNMaterialProperty.self, updateSelector) else { return false }
        let original = unsafeBitCast(method_getImplementation(method), to: Update.self)
        originalUpdate = original
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { property, contents in
            if let contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID,
                let held = Thread.current.threadDictionary[heldKey] as? Held,
                let property = property as? SCNMaterialProperty,
                // (A material's own: a light's gobo, or the scene's environment, picture handed on later did not
                // reach the light or the scene.)
                let parentIvar, object_getIvar(property, parentIvar) is SCNMaterial
            {
                held.list.append((property, contents))
                return
            }
            original(property, updateSelector, contents)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
        return true
    }()

    /// Holds SceneKit back from the pictures given on this thread from now (a stage beginning to be built). Returns
    /// whether it does.
    static func begin() -> Bool {
        guard mode != .off, !held, ProcessInfo.processInfo.environment["SPINDLE_PACK_NOHOLD"] == nil, device != nil, Thread.current.threadDictionary[heldKey] == nil, installed else {
            return false
        }
        Thread.current.threadDictionary[heldKey] = Held()
        return true
    }

    /// Hands every picture still held back on to SceneKit, and holds back no more.
    static func finish() {
        handOn(under: nil)
        Thread.current.threadDictionary[heldKey] = nil
    }

    /// Hands the pictures held back of everything under `root` (of everything, given nil) on to SceneKit.
    static func handOn(under root: SCNNode?) {
        guard let held = Thread.current.threadDictionary[heldKey] as? Held, let original = originalUpdate,
            !held.list.isEmpty
        else { return }
        var wanted: Set<ObjectIdentifier>?
        if let root {
            var set = Set<ObjectIdentifier>()
            root.enumerateHierarchy { node, _ in
                for material in (node.geometry?.materials ?? []) + ScenePieces.materials(welded: node) {
                    for p in Keeping.properties(of: material) { set.insert(ObjectIdentifier(p)) }
                }
                if let gobo = node.light?.gobo { set.insert(ObjectIdentifier(gobo)) }
            }
            wanted = set
        }
        var kept: [(property: SCNMaterialProperty, contents: AnyObject)] = []
        var due: [(property: SCNMaterialProperty, contents: AnyObject)] = []
        for entry in held.list {
            if let wanted, !wanted.contains(ObjectIdentifier(entry.property)) {
                kept.append(entry)
            } else {
                due.append(entry)
            }
        }
        held.list = kept
        // (Given again through the property itself, nothing held back meanwhile: a picture handed only to the method
        // held back left the material as it had been, a see-through dust sheet drawn a shade differently until it
        // was given something else.)
        Thread.current.threadDictionary[heldKey] = nil
        defer { Thread.current.threadDictionary[heldKey] = held }
        var done = Set<ObjectIdentifier>()
        for entry in due.reversed() where done.insert(ObjectIdentifier(entry.property)).inserted {
            // (Only what the property still holds: it may have been given something since.)
            guard (entry.property.contents as AnyObject?) === entry.contents else { continue }
            entry.property.contents = nil
            entry.property.contents = entry.contents
        }
        _ = original
    }

    // MARK: A stage's pictures

    /// What kind of picture a property holds, as SceneKit draws it.
    struct Use {
        var colour: Bool  // sRGB (diffuse, multiply, emission, shader pictures) or linear (roughness, masks, normals)
        var compressible: Bool
        var mipmapped: Bool
        /// The diffuse and transparent slots: SceneKit reads a picture's alpha there (see `apply`).
        var alphaMatters = false
    }

    /// A picture to be packed where it is used.
    struct Job {
        var property: SCNMaterialProperty
        var material: SCNMaterial
        var use: Use
        var label: String
    }

    /// Packs the pictures of everything under `root` (and halves them at `minimum`). Runs once a stage is built.
    static func pack(_ root: SCNNode) {
        guard mode != .off, !held, device != nil else { return }
        let halve = DrawingQuality.current == .minimum
        guard mode == .raw || (astc && mode == .compressed) || halve else { return }
        prune()
        for job in jobs(root) { apply(job, halve: halve) }
    }

    /// Lets go of what was kept for textures since let go of. (A map table with weak keys drops its entries for keys
    /// gone only as it pleases, and keeps their values, here the pictures, till then.)
    private static func prune() {
        lock.lock()
        defer { lock.unlock() }
        let live = NSMapTable<AnyObject, Source>(
            keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
        for key in sources.keyEnumerator().allObjects {
            if let source = sources.object(forKey: key as AnyObject) { live.setObject(source, forKey: key as AnyObject) }
        }
        sources = live
        opacity = opacity.filter { made.object(forKey: $0.key) != nil }
    }

    /// Every picture under `root` that may be packed.
    static func jobs(_ root: SCNNode) -> [Job] {
        var seen = Set<ObjectIdentifier>()
        var list: [Job] = []
        root.enumerateHierarchy { node, _ in
            // (The record's label and lettering are the subject, and the Library's still is drawn again as the hour
            // moves: both as they came.)
            if node.name == "label" || node.name == "deadwax" || node.name == "live" { return }
            for material in (node.geometry?.materials ?? []) + ScenePieces.materials(welded: node)
            where seen.insert(ObjectIdentifier(material)).inserted {
                list += jobs(material, at: node.name ?? "-")
            }
        }
        return list
    }

    /// Whether SceneKit makes mip maps of a property's picture: with a linear mip filter, or a nearest one on a picture
    /// that is not clamped both ways. (Found by reading back the textures SceneKit makes.)
    static func mipmapped(_ p: SCNMaterialProperty) -> Bool {
        p.mipFilter == .linear || (p.mipFilter == .nearest && !(p.wrapS == .clamp && p.wrapT == .clamp))
    }

    private static func jobs(_ m: SCNMaterial, at place: String) -> [Job] {
        let text = (m.shaderModifiers ?? [:]).values.joined(separator: "\n")
        // (Covers, the label and the sleeves' print: the never-clip shader marks them.)
        if text.contains("printExposure") { return [] }
        var list: [Job] = []
        func add(_ p: SCNMaterialProperty, _ slot: String, colour: Bool, compressible: Bool, kind: Character) {
            guard kinds.contains(kind), p.contents != nil else { return }
            var use = Use(colour: colour, compressible: compressible, mipmapped: mipmapped(p))
            use.alphaMatters = p === m.diffuse || p === m.transparent
            list.append(Job(property: p, material: m, use: use, label: "\(m.name ?? "?")@\(place).\(slot)"))
        }
        for (p, slot) in [
            (m.diffuse, "diffuse"), (m.multiply, "multiply"), (m.emission, "emission"),
            (m.selfIllumination, "selfIllumination"), (m.ambient, "ambient"),
        ] {
            add(p, slot, colour: true, compressible: true, kind: "c")
        }
        for (p, slot) in [
            (m.roughness, "roughness"), (m.metalness, "metalness"), (m.ambientOcclusion, "ambientOcclusion"),
            // (Not the clear coat's: its roughness drew a little differently from a texture of ours, on the 911's paint.)
            (m.transparent, "transparent"),
        ] {
            add(p, slot, colour: false, compressible: true, kind: "l")
        }
        add(m.normal, "normal", colour: false, compressible: false, kind: "n")
        add(m.clearCoatNormal, "clearCoatNormal", colour: false, compressible: false, kind: "n")
        // (Not the pictures handed to a shader modifier by name. SceneKit has made its copies of each before the stage
        // can hold it back (the property has no material yet when it is given its picture), so packing them saved
        // nothing; some shaders read a picture as shapes, not colours, where compression showed (the Boathouse lake's
        // ripples moved the lit windows mirrored in it); and packed, a picture settled beside them drew a shade
        // differently, which `--settle-test` caught.)
        return list
    }
    /// (`SPINDLE_PACK_KINDS=cln`: which kinds of property are packed, for finding what changes a picture: colour,
    /// linear, normal maps. All of them unless said.)
    private static let kinds = ProcessInfo.processInfo.environment["SPINDLE_PACK_KINDS"] ?? "cln"

    /// Packs one picture where it is used (if it is to be). Returns whether it was.
    ///
    /// The diffuse and transparent slots are never given a texture of ours: there SceneKit reads a picture's alpha, and
    /// with a texture it cannot tell the picture is opaque. It took such a material for one that may be see-through:
    /// it drew it a little differently (out of the ambient occlusion, its colours taken as not premultiplied) and,
    /// even with blending set so that it drew the same, at about a fifth more of the graphics chip's time a frame
    /// (measured: the Café 8.8 -> 10.9 ms at Normal, raw or compressed alike, and even in a format with no alpha at
    /// all). So those pictures stay SceneKit's own, and at `minimum` it is given a picture of half the size instead
    /// (`halfPicture`), which it makes its own texture of as before.
    @discardableResult
    static func apply(_ job: Job, halve: Bool) -> Bool {
        let property = job.property
        let use = job.use
        guard var contents = property.contents else { return false }
        // (Packed already, by a stage before this one: a model's material, kept. If it was packed for another quality,
        // it is put back as it came and packed again.)
        if !(contents is URL), CFGetTypeID(contents as CFTypeRef) != CGImage.typeID || isHalf(contents) {
            lock.lock()
            let source = sources.object(forKey: contents as AnyObject)
            lock.unlock()
            guard let source else { return false }
            if source.halved == halve { return true }
            property.contents = source.contents
            contents = source.contents
        }
        var picture: Picture?
        if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            picture = Picture(image: contents as! CGImage)  // swiftlint:disable:this force_cast
        } else if let url = contents as? URL {
            picture = Picture(url: url)
        }
        guard let picture else {
            if report, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
                let image = contents as! CGImage  // swiftlint:disable:this force_cast
                Swift.print(
                    "skip \(job.label): bpp \(image.bitsPerPixel) bpc \(image.bitsPerComponent) space \(image.colorSpace?.name as String? ?? "nil")"
                )
            } else if report, contents is URL {
                Swift.print("skip \(job.label): url \(contents)")
            }
            return false
        }
        guard picture.width * picture.height >= smallest else { return false }
        let made: AnyObject
        if use.alphaMatters {
            guard halve, let half = halfPicture(picture) else { return false }
            made = half
        } else {
            let compress = use.compressible && !picture.gray && astc && mode == .compressed
            guard compress || halve || mode == .raw else { return false }
            guard let texture = texture(for: picture, use: use, compress: compress, halve: halve) else {
                if report { Swift.print("skip \(job.label): \(picture.width)x\(picture.height) not packed (gate or key)") }
                return false
            }
            made = texture.texture
        }
        lock.lock()
        sources.setObject(Source(contents: contents as AnyObject, halved: halve), forKey: made)
        lock.unlock()
        property.contents = made
        return true
    }

    /// What each texture (or half-size picture) of ours was made of, and how: for packing it again at another quality.
    private final class Source {
        let contents: AnyObject
        let halved: Bool
        init(contents: AnyObject, halved: Bool) {
            self.contents = contents
            self.halved = halved
        }
    }
    private static var sources = NSMapTable<AnyObject, Source>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)

    /// Half-size pictures made here (each kept only while something holds it).
    private static let halves = NSMapTable<NSString, AnyObject>(keyOptions: .strongMemory, valueOptions: .weakMemory)
    private static func isHalf(_ contents: Any) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sources.object(forKey: contents as AnyObject) != nil
    }

    /// The picture at half its size each way, drawn by Core Graphics in its own colour space, its pixels in a file of
    /// the cache mapped back (so they are not the app's memory, and are not drawn again at the next build).
    private static func halfPicture(_ picture: Picture) -> CGImage? {
        guard let key = picture.key else { return nil }
        let name = "half|\(key)" as NSString
        lock.lock()
        if let ready = halves.object(forKey: name) {
            lock.unlock()
            return (ready as! CGImage)  // swiftlint:disable:this force_cast
        }
        lock.unlock()
        let w = max(picture.width / 2, 1)
        let h = max(picture.height / 2, 1)
        let channels = picture.gray ? 1 : 4
        let digest = SHA256.hash(data: Data("\(version)|\(name)".utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder?.appendingPathComponent(digest + ".half")
        // (Drawn in the picture's own colour space, so that SceneKit takes it just as it took the picture.)
        guard
            let source = picture.image
                ?? picture.url.flatMap({ CGImageSourceCreateWithURL($0 as CFURL, nil) }).flatMap({
                    CGImageSourceCreateImageAtIndex($0, 0, nil)
                }),
            let space = source.colorSpace
        else { return nil }
        let info = picture.gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        let size = w * h * channels
        var data: NSData?
        if let file, let kept = try? NSData(contentsOf: file, options: .alwaysMapped), kept.length == size {
            touch(file)
            data = kept
        } else {
            var bytes = [UInt8](repeating: 0, count: size)
            let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
                guard
                    let ctx = CGContext(
                        data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * channels,
                        space: space, bitmapInfo: info)
                else { return false }
                ctx.interpolationQuality = .high
                ctx.setBlendMode(.copy)
                ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            if let file {
                let temporary = file.appendingPathExtension("part")
                if (try? Data(bytes).write(to: temporary)) != nil {
                    _ = try? FileManager.default.replaceItemAt(file, withItemAt: temporary)
                }
                data = try? NSData(contentsOf: file, options: .alwaysMapped)
            }
            if data == nil { data = NSData(bytes: bytes, length: size) }
        }
        guard let data, let provider = CGDataProvider(data: data),
            let half = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8 * channels, bytesPerRow: w * channels,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil,
                shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let ready = halves.object(forKey: name) { return (ready as! CGImage) }  // swiftlint:disable:this force_cast
        halves.setObject(half, forKey: name)
        return half
    }



    /// A picture to be packed: a drawn one, or one of our files (by its URL, or decoded from it).
    private struct Picture {
        var image: CGImage?
        var url: URL?
        var width = 0, height = 0
        var gray = false

        init?(image: CGImage) {
            guard image.bitsPerComponent == 8, let space = image.colorSpace else { return nil }
            gray = space.model == .monochrome
            guard gray ? image.bitsPerPixel == 8 : (image.bitsPerPixel == 32 || image.bitsPerPixel == 24) else { return nil }
            guard gray || Self.plainRGB(space) else { return nil }
            self.image = image
            width = image.width
            height = image.height
        }

        /// RGB in any colour space: SceneKit takes the values as they are, whatever the space says, and so are they
        /// drawn here, in their own space (checked with `SPINDLE_PACK=raw`).
        static func plainRGB(_ space: CGColorSpace) -> Bool { space.model == .rgb }

        init?(url: URL) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int
            else { return nil }
            gray = (p[kCGImagePropertyColorModel] as? String) == (kCGImagePropertyColorModelGray as String)
            if (p[kCGImagePropertyDepth] as? Int ?? 8) != 8 { return nil }
            self.url = url
            width = w
            height = h
        }

        /// What finds it on the disk: its file, or a hash of its pixels.
        var key: String? {
            if let url { return fileStamp(url).map { "\($0)|0" } }
            guard let image else { return nil }
            lock.lock()
            let known = (origins.object(forKey: image) ?? hashes.object(forKey: image)) as String?
            lock.unlock()
            if let known { return known }
            // (A picture moved out of memory has its hash noted as it is moved (`noteDrawn`, from `Tex.settled`):
            // asked for its data, Core Graphics keeps a copy of all of it for as long as the picture lives.)
            guard let data = image.dataProvider?.data else { return nil }
            return noteDrawn(image, bytes: CFDataGetBytePtr(data), count: CFDataGetLength(data))
        }

        /// Its pixels as SceneKit lays them out: rows from the top, sRGB RGBA with alpha premultiplied (or one grey).
        func pixels() -> [UInt8]? {
            if report { Swift.print("decode \(width)x\(height) url \(url?.lastPathComponent ?? "-") file \(image?.utType as String? ?? "-")") }
            guard
                let image = image
                    ?? url.flatMap({ CGImageSourceCreateWithURL($0 as CFURL, nil) }).flatMap({
                        CGImageSourceCreateImageAtIndex($0, 0, nil)
                    })
            else { return nil }
            guard let own = image.colorSpace, gray ? own.model == .monochrome : Self.plainRGB(own),
                image.bitsPerComponent == 8
            else { return nil }
            let w = image.width
            let h = image.height
            let channels = gray ? 1 : 4
            var bytes = [UInt8](repeating: 0, count: w * h * channels)
            let space = gray ? (image.colorSpace ?? CGColorSpaceCreateDeviceGray()) : CGColorSpace(name: CGColorSpace.sRGB)!
            let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
            let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
                guard
                    let ctx = CGContext(
                        data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * channels,
                        space: space, bitmapInfo: info)
                else { return false }
                ctx.setBlendMode(.copy)
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            // SceneKit premultiplies in linear light, then encodes as sRGB again: so does this, where a pixel is not
            // opaque. (Core Graphics premultiplies the encoded values: semi-transparent pixels came out darker, and a
            // decal's edges and the desk's wear changed.)
            if !gray {
                let table = Picture.premultiplied
                for i in stride(from: 0, to: bytes.count, by: 4) {
                    let a = Int(bytes[i + 3])
                    guard a < 255 else { continue }
                    for c in 0..<3 { bytes[i + c] = table[a << 8 | Int(bytes[i + c])] }
                }
            }
            return bytes
        }

        /// For each alpha and each colour premultiplied in sRGB (alpha << 8 | colour), the colour premultiplied in
        /// linear light and encoded as sRGB.
        static let premultiplied: [UInt8] = {
            func linear(_ e: Double) -> Double { e <= 0.04045 ? e / 12.92 : pow((e + 0.055) / 1.055, 2.4) }
            func encoded(_ l: Double) -> Double { l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055 }
            var table = [UInt8](repeating: 0, count: 256 * 256)
            for a in 1..<256 {
                for p in 0..<256 {
                    let straight = min(Double(p) / Double(a), 1)
                    let value = encoded(linear(straight) * Double(a) / 255) * 255
                    table[a << 8 | p] = UInt8(max(0, min(255, value.rounded())))
                }
            }
            return table
        }()
    }

    // MARK: Textures

    /// A texture made, and whether its picture is opaque throughout.
    struct Made {
        var texture: MTLTexture
        var opaque: Bool
    }
    /// Whether each texture made is of an opaque picture (by the same names as `made`).
    private static var opacity: [NSString: Bool] = [:]

    private static func texture(for picture: Picture, use: Use, compress: Bool, halve: Bool) -> Made? {
        guard let key = picture.key else { return nil }
        let start = halve && min(picture.width, picture.height) >= 2 ? 1 : 0
        let name = "\(key)|\(use.colour)|\(use.mipmapped)|\(start)|\(compress)|\(picture.gray)" as NSString
        lock.lock()
        if let ready = made.object(forKey: name) as? MTLTexture, let opaque = opacity[name] {
            lock.unlock()
            return Made(texture: ready, opaque: opaque)
        }
        lock.unlock()
        var result: Made?
        if compress {
            let blocks = compressed(key: key, picture: picture, colour: use.colour)
            if let blocks, !blocks.levels.isEmpty,
                let texture = upload(blocks, colour: use.colour, mipmapped: use.mipmapped, start: start)
            {
                result = Made(texture: texture, opaque: blocks.opaque)
            } else if start == 0 {
                // (One that does not compress well is left to SceneKit, unless it is to be halved.)
                return nil
            }
        }
        if result == nil { result = plain(picture, colour: use.colour, mipmapped: use.mipmapped, start: start) }
        guard let result else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let ready = made.object(forKey: name) as? MTLTexture, let opaque = opacity[name] {
            return Made(texture: ready, opaque: opaque)
        }
        made.setObject(result.texture, forKey: name)
        opacity[name] = result.opaque
        return result
    }

    /// Whether pixels (RGBA, or one grey) are opaque throughout.
    private static func opaque(_ pixels: [UInt8], gray: Bool) -> Bool {
        if gray { return true }
        return pixels.withUnsafeBufferPointer { p in
            var i = 3
            while i < p.count {
                if p[i] != 255 { return false }
                i += 4
            }
            return true
        }
    }

    /// The picture uncompressed, with its mip maps made on the graphics chip (as SceneKit makes them), from `start`.
    private static func plain(_ picture: Picture, colour: Bool, mipmapped: Bool, start: Int) -> Made? {
        guard let pixels = picture.pixels(), let full = chain(pixels, picture, colour: colour, levels: start > 0 || mipmapped)
        else { return nil }
        let solid = opaque(pixels, gray: picture.gray)
        if start == 0 && (mipmapped || full.mipmapLevelCount == 1) { return Made(texture: full, opaque: solid) }
        guard let device, let queue else { return nil }
        let levels = mipmapped ? full.mipmapLevelCount - start : 1
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: full.pixelFormat, width: max(full.width >> start, 1), height: max(full.height >> start, 1),
            mipmapped: false)
        d.mipmapLevelCount = levels
        d.usage = .shaderRead
        d.storageMode = .shared
        d.swizzle = full.swizzle
        guard let made = device.makeTexture(descriptor: d), let buffer = queue.makeCommandBuffer(),
            let blit = buffer.makeBlitCommandEncoder()
        else { return nil }
        blit.copy(
            from: full, sourceSlice: 0, sourceLevel: start, to: made, destinationSlice: 0, destinationLevel: 0,
            sliceCount: 1, levelCount: levels)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        return Made(texture: made, opaque: solid)
    }

    /// The picture as a texture with every mip level (or only its own).
    private static func chain(_ pixels: [UInt8], _ picture: Picture, colour: Bool, levels: Bool) -> MTLTexture? {
        guard let device, let queue else { return nil }
        let format: MTLPixelFormat =
            picture.gray ? (colour ? .r8Unorm_srgb : .r8Unorm) : (colour ? .rgba8Unorm_srgb : .rgba8Unorm)
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: picture.width, height: picture.height, mipmapped: levels)
        d.usage = .shaderRead
        d.storageMode = .shared
        if picture.gray { d.swizzle = MTLTextureSwizzleChannels(red: .red, green: .red, blue: .red, alpha: .one) }
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        let row = picture.width * (picture.gray ? 1 : 4)
        pixels.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, picture.width, picture.height), mipmapLevel: 0,
                withBytes: raw.baseAddress!, bytesPerRow: row)
        }
        if levels, texture.mipmapLevelCount > 1, let buffer = queue.makeCommandBuffer(),
            let blit = buffer.makeBlitCommandEncoder()
        {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            buffer.commit()
            buffer.waitUntilCompleted()
        }
        return texture
    }

    // MARK: Compressed

    /// Every mip level of a picture, compressed (from the disk, or encoded now and written there); no levels where it
    /// does not compress well enough.
    private struct Blocks {
        var width: Int, height: Int
        var opaque: Bool
        var levels: [Data]
    }

    private static func compressed(key: String, picture: Picture, colour: Bool) -> Blocks? {
        let digest = SHA256.hash(data: Data("\(version)|\(key)|\(colour)".utf8)).map { String(format: "%02x", $0) }
            .joined()
        let file = folder?.appendingPathComponent(digest + ".astc")
        if let file, let kept = read(file) {
            touch(file)
            return kept
        }
        // (Not there: made now. A picture of ours is encoded once, ever.)
        let made = encode(picture, colour: colour)
        if let file, let made { write(made, to: file) }
        return made
    }

    private static func encode(_ picture: Picture, colour: Bool) -> Blocks? {
        // (The mip maps are made as SceneKit makes them: a colour picture's in linear light.)
        guard let pixels = picture.pixels(), let full = chain(pixels, picture, colour: colour, levels: true) else {
            return nil
        }
        var blocks = Blocks(
            width: picture.width, height: picture.height, opaque: opaque(pixels, gray: picture.gray), levels: [])
        for level in 0..<full.mipmapLevelCount {
            let w = max(picture.width >> level, 1)
            let h = max(picture.height >> level, 1)
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            full.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: level)
            // (The picture, and each of its mip levels down to 64x64, must come back as it was, or it is not compressed at
            // all: a shader that blurs a picture by reading its smaller levels, the Boathouse's lake mirroring the shore, showed
            // the difference of those levels.)
            guard let packed = encode(bytes, width: w, height: h),
                (level > 0 && w * h < 64 * 64) || passes(packed, against: bytes, width: w, height: h)
            else {
                blocks.levels = []
                return blocks
            }
            blocks.levels.append(packed)
        }
        return blocks
    }


    /// One level, ASTC 4x4, by ImageIO. (Its rows go from the bottom: the picture is turned over first.)
    private static func encode(_ bytes: [UInt8], width w: Int, height h: Int) -> Data? {
        var flipped = [UInt8](repeating: 0, count: bytes.count)
        let row = w * 4
        for y in 0..<h {
            flipped.replaceSubrange((h - 1 - y) * row..<(h - y) * row, with: bytes[y * row..<(y + 1) * row])
        }
        // (The alpha is passed as it is, premultiplied, called straight, so that nothing is done to it.)
        let opaque = !stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] != 255 }
        guard let provider = CGDataProvider(data: Data(flipped) as CFData),
            let image = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: row,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.last).rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "org.khronos.astc" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination, image,
            // (0x44 is 4x4, ImageIO's own word for it before macOS 26 named it.)
            [kCGImagePropertyASTCBlockSize: 0x44, kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let expected = ((w + 3) / 4) * ((h + 3) / 4) * 16
        let data = out as Data
        // (The file's header: its magic number, then the block's size, which must be 4x4x1.)
        guard data.count == expected + 16, data[4] == 4, data[5] == 4, data[6] == 1 else { return nil }
        return data.subdata(in: 16..<data.count)
    }

    /// Whether a level, decoded again, is close enough to what it was made of: over the whole picture and in its worst
    /// places. (A picture of fine, sharp-edged detail, such as small print or a noise of single pixels, does not pass.)
    static var threshold = Double(ProcessInfo.processInfo.environment["SPINDLE_PACK_PSNR"] ?? "") ?? 40
    private static func passes(_ blocks: Data, against bytes: [UInt8], width w: Int, height h: Int) -> Bool {
        guard let device, let queue, let decoder else { return false }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .astc_4x4_ldr, width: w, height: h, mipmapped: false)
        d.usage = .shaderRead
        d.storageMode = .shared
        let o = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        o.usage = [.shaderWrite, .shaderRead]
        o.storageMode = .shared
        guard let packed = device.makeTexture(descriptor: d), let out = device.makeTexture(descriptor: o),
            let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder()
        else { return false }
        blocks.withUnsafeBytes { raw in
            packed.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: raw.baseAddress!,
                bytesPerRow: ((w + 3) / 4) * 16)
        }
        encoder.setComputePipelineState(decoder)
        encoder.setTexture(packed, index: 0)
        encoder.setTexture(out, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var back = [UInt8](repeating: 0, count: w * h * 4)
        out.getBytes(&back, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let score = Score(back, bytes, width: w, height: h)
        if report { Swift.print(String(format: "pack %dx%d psnr %.1f worst-block %.1f", w, h, score.psnr, score.worst)) }
        // (`SPINDLE_PACK_DUMP=<folder>`: a picture that fails, and what came back, for looking at.)
        if let folder = ProcessInfo.processInfo.environment["SPINDLE_PACK_DUMP"], score.psnr < threshold {
            for (pixels, side) in [(bytes, "in"), (back, "out")] {
                if let provider = CGDataProvider(data: Data(pixels) as CFData),
                    let image = CGImage(
                        width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                    let out = CGImageDestinationCreateWithURL(
                        URL(fileURLWithPath: folder).appendingPathComponent("\(w)x\(h)-\(Int(score.psnr))-\(side).png")
                            as CFURL, "public.png" as CFString, 1, nil)
                {
                    CGImageDestinationAddImage(out, image, nil)
                    CGImageDestinationFinalize(out)
                }
            }
        }
        return score.psnr >= threshold && score.worst >= threshold - 8
    }
    static let report = ProcessInfo.processInfo.environment["SPINDLE_PACK_REPORT"] != nil

    /// How far apart two pictures are: the PSNR over all of it, and over its worst 16x16 patch.
    struct Score {
        var psnr: Double, worst: Double
        init(_ a: [UInt8], _ b: [UInt8], width w: Int, height h: Int) {
            var total = 0.0
            var worstPatch = 0.0
            let patch = 16
            for py in stride(from: 0, to: h, by: patch) {
                for px in stride(from: 0, to: w, by: patch) {
                    var sum = 0.0
                    var n = 0
                    for y in py..<min(py + patch, h) {
                        for x in px..<min(px + patch, w) {
                            let i = (y * w + x) * 4
                            for c in 0..<4 {
                                let e = Double(Int(a[i + c]) - Int(b[i + c]))
                                sum += e * e
                            }
                            n += 4
                        }
                    }
                    total += sum
                    worstPatch = max(worstPatch, sum / Double(max(n, 1)))
                }
            }
            let mse = total / Double(w * h * 4)
            psnr = 10 * log10(65025 / max(mse, 1e-6))
            worst = 10 * log10(65025 / max(worstPatch, 1e-6))
        }
    }

    private static let decoder: MTLComputePipelineState? = {
        guard let device,
            let library = try? device.makeLibrary(
                source: """
                    #include <metal_stdlib>
                    using namespace metal;
                    kernel void unpack(texture2d<float, access::read> a [[texture(0)]],
                                       texture2d<float, access::write> b [[texture(1)]],
                                       uint2 g [[thread_position_in_grid]]) {
                        if (g.x >= a.get_width() || g.y >= a.get_height()) return;
                        b.write(a.read(g), g);
                    }
                    """, options: nil),
            let function = library.makeFunction(name: "unpack")
        else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }()

    private static func upload(_ blocks: Blocks, colour: Bool, mipmapped: Bool, start: Int) -> MTLTexture? {
        guard let device, start < blocks.levels.count else { return nil }
        let count = mipmapped ? blocks.levels.count - start : 1
        let w = max(blocks.width >> start, 1)
        let h = max(blocks.height >> start, 1)
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colour ? .astc_4x4_srgb : .astc_4x4_ldr, width: w, height: h, mipmapped: false)
        d.mipmapLevelCount = count
        d.usage = .shaderRead
        d.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        for level in 0..<count {
            let lw = max(w >> level, 1)
            let lh = max(h >> level, 1)
            let data = blocks.levels[start + level]
            guard data.count == ((lw + 3) / 4) * ((lh + 3) / 4) * 16 else { return nil }
            data.withUnsafeBytes { raw in
                texture.replace(
                    region: MTLRegionMake2D(0, 0, lw, lh), mipmapLevel: level, withBytes: raw.baseAddress!,
                    bytesPerRow: ((lw + 3) / 4) * 16)
            }
        }
        return texture
    }

    // MARK: On the disk

    /// `~/Library/Caches/2dle/Textures`: one file a picture, read back at every build; past `limit` the files least
    /// recently read go. (Losing the folder only costs encoding them again.)
    private static let folder: URL? = {
        let env = ProcessInfo.processInfo.environment["SPINDLE_PACK_CACHE"]
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let folder = env.map({ URL(fileURLWithPath: $0) }) ?? caches?.appendingPathComponent("2dle/Textures")
        else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) { prune(folder) }
        return folder
    }()
    private static let limit = 1536 * 1024 * 1024

    private static func read(_ file: URL) -> Blocks? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe), data.count >= 24 else { return nil }
        func word(_ at: Int) -> Int {
            Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) })
        }
        guard data.prefix(4) == Data("2DLP".utf8), word(4) == Int(version) else { return nil }
        let w = word(8)
        let h = word(12)
        let flags = word(16)
        let count = word(20)
        var at = 24
        var levels: [Data] = []
        for _ in 0..<count {
            guard at + 4 <= data.count else { return nil }
            let n = word(at)
            at += 4
            guard at + n <= data.count else { return nil }
            levels.append(data.subdata(in: at..<at + n))
            at += n
        }
        return Blocks(width: w, height: h, opaque: flags & 1 != 0, levels: levels)
    }

    private static func write(_ blocks: Blocks, to file: URL) {
        var data = Data("2DLP".utf8)
        func word(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        word(Int(version))
        word(blocks.width)
        word(blocks.height)
        word(blocks.opaque ? 1 : 0)
        word(blocks.levels.count)
        for level in blocks.levels {
            word(level.count)
            data.append(level)
        }
        let temporary = file.appendingPathExtension("part")
        do {
            try data.write(to: temporary)
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        } catch { try? FileManager.default.removeItem(at: temporary) }
    }

    private static func touch(_ file: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    }

    private static func prune(_ folder: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        else { return }
        var list = files.compactMap { url -> (URL, Date, Int)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, v.contentModificationDate ?? .distantPast, v.fileSize ?? 0)
        }
        var total = list.reduce(0) { $0 + $1.2 }
        list.sort { $0.1 < $1.1 }
        for (url, _, size) in list where total > limit {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}
