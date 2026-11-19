import AppKit
import ImageIO

/// Locates bundled assets. Inside the .app they live in Contents/Resources; when the bare
/// executable is run from `.build/` we walk up to the package root instead.
enum Resources {
    static var bundleOverride: Bundle?
    static let root: URL = {
        if let resourceURL = bundleOverride?.resourceURL { return resourceURL }
        let fm = FileManager.default
        // (Only for test runs and a bare build: an installed app reads its own, so that nothing outside it can point its
        // sign-in at another server.)
        if CommandLine.arguments.contains("--snapshot") || !Bundle.main.bundlePath.hasSuffix(".app"),
            let env = ProcessInfo.processInfo.environment["SPINDLE_RESOURCES"]
        {
            return URL(fileURLWithPath: env)
        }
        if let res = Bundle.main.resourceURL,
            fm.fileExists(atPath: res.appendingPathComponent("textures").path)
        {
            return res
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("Resources")
            if fm.fileExists(atPath: candidate.appendingPathComponent("textures").path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
    }()

    static func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    static func image(_ relativePath: String) -> CGImage? {
        loadImage(at: url(relativePath))
    }
}

func loadImage(at url: URL, maxPixelSize: Int? = nil) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    if let maxPixelSize {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        if let image { Packing.note(image, from: url, maxPixelSize: maxPixelSize) }
        return image
    }
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    // (So that its packed texture is found on the disk by the file alone: see `Packing`.)
    if let image { Packing.note(image, from: url, maxPixelSize: nil) }
    return image
}

func loadImage(data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

@discardableResult
func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

@discardableResult
func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.9) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    return CGImageDestinationFinalize(dest)
}
