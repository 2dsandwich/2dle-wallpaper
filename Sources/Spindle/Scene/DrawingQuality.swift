import CoreGraphics

/// How much is spent on the picture. `normal` is the picture as it was made to be seen. `minimum` is for a Mac that is
/// struggling, and shows it: no soft shade where things meet, coarser shadows, a softer picture and half the frames,
/// for a small part of the work. `maximum` spends more than is needed: finer shadows, smoother edges, and the rain and
/// the fire at the full rate.
enum DrawingQuality: String, CaseIterable {
    case minimum, normal, maximum

    /// What the next stage is built with. (Set by the app from its settings; the screen saver leaves it at `normal`.)
    static var current = DrawingQuality.normal

    var title: String {
        L(
            ["minimum": "Minimum", "normal": "Normal", "maximum": "Maximum"][rawValue] ?? rawValue,
            ["minimum": "最低", "normal": "標準", "maximum": "最高"][rawValue] ?? rawValue)
    }
    /// Taps for each shadow. (Fewer than sixteen breaks a soft edge into copies unless the edge is made harder too: see `shadowScale`.)
    var shadowSamples: Int { self == .minimum ? 8 : (self == .maximum ? 20 : 16) }
    /// How fine the shadows are: the size of the picture each light keeps of what it can see, each way. (The blur is
    /// counted in that picture's own dots, so it is scaled with it and a shadow stays as soft as it was meant to be.)
    /// (Half as fine again at `maximum`: twice as fine cost a quarter of the frames on a 3600-pixel display.)
    var shadowScale: CGFloat { self == .minimum ? 0.5 : (self == .maximum ? 1.5 : 1) }
    /// The shade where one thing meets another, drawn from what is on screen: about half of a frame's work, where it is drawn.
    var ambientOcclusion: CGFloat { self == .minimum ? 0 : 1.15 }
    /// How much of the display's pixels the scene is drawn for, each way: all of them at `maximum`, four fifths at
    /// `normal`, three fifths at `minimum`. That is on a Retina display, which has pixels to spare. On a display with
    /// few of them to the point (an ordinary monitor) a slanted edge is a staircase however carefully each pixel is
    /// filled, so there `normal` and `maximum` draw the scene larger than the display and bring it down, which is
    /// what smooths it.
    func scale(density: CGFloat) -> CGFloat {
        if density >= 1.9 { return self == .minimum ? 0.6 : (self == .normal ? 0.8 : 1) }
        return self == .minimum ? 0.7 : (self == .normal ? 1.4 : 2)
    }
    /// The most frames in a second.
    var frames: Int { self == .minimum ? 30 : 60 }
    /// Samples at each pixel, for smooth edges.
    var edgeSamples: Int { self == .minimum ? 2 : 4 }
    /// Rain, fire and the like are drawn at a slower pace of their own, except here.
    var fullRateAmbience: Bool { self == .maximum }
    /// How well a texture holds up seen along a surface (the grain of a desk running away from the eye): the most the
    /// graphics chip offers, except at `minimum`, where it softens with distance.
    var anisotropy: CGFloat { self == .minimum ? 2 : 16 }
    /// The glow round bright things: a pass over the whole picture, and `minimum` goes without it. (The background out
    /// of focus, in the two scenes that have it, is kept at every quality: see `FilmLook.apply`.)
    var glow: Bool { self != .minimum }
}
