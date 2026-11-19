import AppKit
import SceneKit

/// How every scene is photographed: on colour negative film of the Portra kind, through a
/// fast normal lens. Gentle contrast with real blacks, open shadows, colour a shade under
/// life, a trace of grain, and highlights that keep their tone instead of burning out.
enum FilmLook {
    /// Aperture blades: the shape a light well out of focus takes.
    static let blades = 9
    /// Depth of field against a scene's own aperture (under 1 goes soft sooner).
    static let aperture: CGFloat = 0.52
    /// Grain: how much, and how coarse. (Laid over the picture by `GrainOverlay`, where it holds still.)
    static let grain: CGFloat = 0.07, grainSize: CGFloat = 2.0
    /// Fall-off into the corners and glow round lights, both against the scene's own.
    private static let vignette: CGFloat = 0.75, bloom: CGFloat = 1.10
    /// How hard the curve is through the middle, where black sits (0 is a true black), and the gamma of the whole.
    /// (The toe is in linear light: 0.0029 is about 12 of 255 on the screen. It was 0.022, about 41, with the shadows'
    /// tint on top: the owner saw every dark corner as a milky white, 2026-10-18.)
    private static let contrast = 0.22, toe = 0.0029, gamma = 1.0, saturation = 0.92
    /// A little of each layer's dye in its neighbours: rows are the red, green and blue that come out.
    private static let mix: [[Double]] = [[0.97, 0.03, 0.00], [0.02, 0.96, 0.02], [0.00, 0.06, 0.94]]
    /// What is added in the shadows and in the highlights (red, green, blue).
    private static let shade = [0.0005, 0.001, 0.0008], light = [0.022, 0.012, -0.012]

    private static var made: [SIMD2<Double>: CGImage] = [:]
    private static let lock = NSLock()

    /// The film's rendering as a colour cube: 64 slices of blue side by side, red across and green down each.
    /// `blacks` is how much of the film's lift in the shadows a scene keeps (1: all of it, as every scene had it; less
    /// for a deeper black, `RemadeSceneEnvironment.blacks`).
    /// `warmth` turns that lift from the film's near neutral towards a warm brown-black (a scene's `blacksWarmth`).
    static func cube(blacks: Double = 1, warmth: Double = 0) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = made[SIMD2(blacks, warmth)] { return cached }
        // (The cube is applied to linear light, so this toe is what black comes out as: at 0.4 of the film's, about 6
        // of 255. Warmed, the same amount of it leans red and away from blue.)
        let lean = [1 + 0.45 * warmth, 1 + 0.02 * warmth, 1 - 0.55 * warmth]
        let toes = lean.map { Self.toe * blacks * $0 }
        let shade = (0..<3).map { Self.shade[$0] * blacks * lean[$0] }
        // (64 steps, not 32: on linear light the first step of 32 ran from black to about 50 of 255 on the screen, and
        // the curve drawn straight across each step put a crease into a lamp's fall-off at every step's edge.)
        let n = 64
        let width = n * n
        let height = n
        // (Sixteen bits a channel: the cube is applied to linear light, where one step of eight bits near black is about
        // thirteen of the screen's, so the soft fall-off of a lamp or a fire across a dark wall came out in bands, the
        // "lighting lines": owner, 2026-10-18.)
        var pixels = [UInt16](repeating: 65535, count: width * height * 4)
        func curve(_ x: Double, _ toe: Double) -> Double {
            // (Every scene is exposed a third of a stop under and brought back up here, in the middle
            // only: what used to burn out to white keeps its tone, as it does on negative film.)
            let x = pow(x, 0.86)
            // A toe that holds a little density, a steeper middle, a long shoulder.
            let s = x * x * (3 - 2 * x)
            let y = x + (s - x) * contrast
            return toe + (0.992 - toe) * pow(max(y, 0), gamma)
        }
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let source = [Double(r) / Double(n - 1), Double(g) / Double(n - 1), Double(b) / Double(n - 1)]
                    var c = (0..<3).map { k in mix[k][0] * source[0] + mix[k][1] * source[1] + mix[k][2] * source[2] }
                    c = (0..<3).map { curve(min(max(c[$0], 0), 1), toes[$0]) }
                    let luma = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
                    // Colour is fullest in the middle tones and falls away towards black and white.
                    let chroma = saturation * (0.94 + 0.16 * (1 - pow(abs(luma * 2 - 1), 1.5)) - 0.10 * pow(luma, 3))
                    c = c.map { luma + ($0 - luma) * chroma }
                    let dark = pow(1 - luma, 2.2)
                    let bright = pow(luma, 2.0)
                    for k in 0..<3 { c[k] += shade[k] * dark + light[k] * bright }
                    let i = (g * width + b * n + r) * 4
                    for k in 0..<3 { pixels[i + k] = UInt16(max(0, min(65535, (c[k] * 65535).rounded()))) }
                }
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let image = pixels.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 16, bytesPerRow: width * 8,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)?
                .makeImage()
        }
        made[SIMD2(blacks, warmth)] = image
        return image
    }

    /// Dresses a scene's camera: film, fall-off, glow and aperture.
    /// `aperture` is the scene's own (0 where nothing is thrown out of focus).
    static func apply(
        to camera: SCNCamera, aperture: CGFloat, focus: CGFloat, blacks: CGFloat = 1, warmth: CGFloat = 0
    ) {
        if let cube = cube(blacks: Double(blacks), warmth: Double(warmth)) {
            camera.colorGrading.contents = cube
            camera.colorGrading.intensity = 1
        }
        // (The grain is not the renderer's, which moves: see GrainOverlay.)
        camera.grainIntensity = 0
        camera.vignettingIntensity *= vignette
        camera.exposureOffset -= 0.30
        camera.bloomIntensity *= DrawingQuality.current.glow ? bloom * 0.62 : 0
        camera.bloomThreshold += 0.25
        // (At every quality: a scene made to have its background out of focus is another picture with it sharp, and the
        // pass is a small one. `minimum` takes fewer samples for it.)
        // (`SPINDLE_NODOF=1` leaves everything sharp, for looking at what is far off in a test render.)
        if aperture > 0, ProcessInfo.processInfo.environment["SPINDLE_NODOF"] == nil {
            camera.wantsDepthOfField = true
            camera.focusDistance = focus
            camera.fStop = aperture * Self.aperture
            camera.apertureBladeCount = blades
            camera.focalBlurSampleCount = DrawingQuality.current.glow ? 18 : 10
        }
    }
}
