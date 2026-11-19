import AppKit
import SceneKit
import simd

/// The Stahl House (スタール邸): Pierre Koenig's Case Study House #22 (1959-60), the steel-and-glass L on its hillside
/// above Los Angeles, laid out from Koenig's own plan (research SPEC in the session's `stahlref/research`). The lens is
/// seated in bedroom 2, in the bedroom wing, 2.1 m behind its south glass, looking south-east (bearing 142) across the
/// pool at the living wing; the record desk stands flush on that glass, a planting bed and a low planter box just
/// outside it. Across the L-shaped pool, left to right: the living wing's kitchen (honey ply), the dining table and the
/// coloured-glass etagere, the stone-hood fireplace, the living room, and its glass corner cantilevered 10 ft over the
/// hill with the city below. Everything is white-painted steel: 4-inch columns, 12-inch headers whose stubs run past the
/// corner, a ribbed 5-inch deck under an 8 ft overhang with one row of downlights and a thin fascia.
///
/// The house's grid is the room's own axes (`along` = -z, `across` = +x), laid from `gridOrigin`; `planA`/`planB` turn
/// a place on Koenig's plan into it.
/// The light follows the hour: a hazy midday; at the end of the day the low sun behind us on the right lights the living
/// wing's west face and the terrace warm under a lavender and pink sky (the sun is never in the frame); after dark the
/// city's grid of lights, the pool lit from within, the living wing a lantern, and the arc lamp over the desk.
/// The weather is Los Angeles' own (round 14, `StahlScene+Weather.swift`): the weather where the Mac is, taken to what the
/// Hollywood Hills would make of it, or the day's own.
enum StahlScene {
    /// The living-room floor and the terrace (one slab, inside and out), the table's top being 0; the water outside.
    static let floorY: Float = -0.66
    static let terraceY: Float = -0.66
    static let waterY: Float = -0.735
    /// The bedroom's ceiling, the underside of its deck's ribs (the 12-inch header over the glass from `headY` to it); it
    /// shades the table at midday and runs out as the overhang.
    static let ceilingY: Float = roofY - deckDeep
    /// The room's glass wall (along x, at `glassZ`), and the table pushed against it. The lens is turned to it
    /// (`wallTurn`), so it runs diagonally across the frame along the terrace's joints (the owner: "the wall should go
    /// parallel with this line"): the sliding door's stile near on the right, the wall going away to the left.
    static let glassZ: Float = -0.357
    static var tableWide: Float { tableRight - tableLeft }
    static let tableDeep: Float = 0.70
    /// The table's back edge stands this far off the pane (a finger's gap: it is pushed against the glass, not into it).
    static let tableGap: Float = 0.005
    /// The sliding doors' bronze sill along the glass's foot: from `sillOut` (outside) to `sillRoom` (its room-side face),
    /// `sillHigh` tall; the living room's carpet runs up to it, its top at `carpetTop`.
    static let sillOut: Float = glassZ - 0.035, sillRoom: Float = glassZ + 0.026, sillHigh: Float = 0.020
    static let carpetTop: Float = floorY + 0.011
    static var tableMidZ: Float { glassZ + tableGap + tableDeep / 2 }
    /// The sliding door's stile (near, at the frame's right edge) and the first mullion, ten feet from the room's west
    /// wall (plan x 3.05), where they stand in the glass (x): clear of the table's ends.
    static let stileX: (Float, Float) = (0.712, 0.782)
    static let mullionX: (Float, Float) = (1.60 - 3.05 - 0.022, 1.60 - 3.05 + 0.022)
    /// How far the lens is turned to the right of square to the wall (negative: to the left): so that the glass lies along
    /// the house's grid (`across`), which keeps the reference's 37.5 degrees to the lens.
    static let wallTurn: Float = deg(-37.5)
    /// The lens's way ahead (level), and to its right.
    static var forward: SIMD3<Float> { SIMD3(sin(wallTurn), 0, -cos(wallTurn)) }
    static var rightward: SIMD3<Float> { SIMD3(cos(wallTurn), 0, sin(wallTurn)) }

    // MARK: The house's grid

    /// How far the house's grid is turned from the lens: the bedroom wing runs along `along` (away, to the right), the
    /// pool's long sides along `across` (towards us, to the right). Worked out from the reference's vanishing points.
    /// (37.5 degrees from the lens's way ahead, which is itself `wallTurn` round from the room's: 0, so the room's glass
    /// runs along `across` and the house is one grid.)
    static let gridTurn: Float = deg(37.5) + wallTurn
    static var along: SIMD3<Float> { SIMD3(sin(gridTurn), 0, -cos(gridTurn)) }
    static var across: SIMD3<Float> { SIMD3(cos(gridTurn), 0, sin(gridTurn)) }
    /// The grid's origin: where the reference was laid out from, three metres straight ahead of the lens and in its
    /// frame, carried round with the lens.
    static var gridOrigin: SIMD3<Float> {
        let e = eye(.close)
        return SIMD3(e.x, 0, e.z) + forward * 3.0
    }
    /// A place on the grid: `a` along the wing, `b` across it (the wing's glass at `facadeB`, the terrace towards us).
    static func site(_ a: Float, _ b: Float, _ y: Float = terraceY) -> SIMD3<Float> {
        gridOrigin + along * a + across * b + SIMD3(0, y, 0)
    }
    /// Where a point is on the grid (a, b).
    static func grid(_ p: SIMD3<Float>) -> SIMD2<Float> {
        SIMD2(simd_dot(p - gridOrigin, along), simd_dot(p - gridOrigin, across))
    }
    /// The grid's origin and axes as shader code: `float2(a, b)` of a world point's `xz` (named `xz`).
    static func gridCode(_ xz: String) -> String {
        let o = gridOrigin, a = along, b = across
        return "float2(dot(\(xz) - float2(\(o.x), \(o.z)), float2(\(a.x), \(a.z))), dot(\(xz) - float2(\(o.x), \(o.z)), float2(\(b.x), \(b.z))))"
    }

    // MARK: Koenig's plan

    /// The house is laid out from Koenig's own plan (research SPEC, `stahlref/research/dl2/planta2_big.png`): plan x is
    /// metres east and plan y metres south of bedroom 2's outside north-west corner, and the scene's world is that plan
    /// turned 180 degrees about the lens (X = 1.60 - x, Z = 5.74 - y). The lens sits in bedroom 2, 2.1 m behind its
    /// south glass, looking south-east (bearing 142) across the pool at the living wing. On the grid a = y - 6.40 (south,
    /// away from us) and b = 2.13 - x (west, to the right).
    static func planA(_ y: Float) -> Float { gridOrigin.z - (5.74 - y) }
    static func planB(_ x: Float) -> Float { (1.60 - x) - gridOrigin.x }

    /// The living wing across the pool (its west glass along `facadeB`, its east glass `wingBackB`, 20 ft apart): the
    /// roof's west overhang 8 ft out (`fasciaB`), the east one 2.6 ft (`backFasciaB`). Its columns on the 20 ft grid
    /// (`columnsA`: plan y 6.10, 12.19, 18.29), the last bay cantilevered 10 ft to the glass corner (`cornerA`, y 21.34),
    /// the header beams running on 0.8 m past it as stubs (`stubA`), the deck 2 m (`wingA1`). The roof starts behind the
    /// frame's left (`wingA0`). The glass's head and the deck's top.
    static let facadeB = planB(12.19), wingBackB = planB(18.29)
    /// (The owner's plan, round 10: the dashed overhang line 2.6 m out on the west and the south, 0.6 m on the east.)
    static var fasciaB: Float { facadeB + 2.6 }
    static var backFasciaB: Float { wingBackB - 0.6 }
    static let columnsA: [Float] = [planA(6.10), planA(12.19), planA(18.29)]
    static let cornerA = planA(21.34)
    static var stubA: Float { cornerA + 0.8 }
    static var wingA1: Float { cornerA + 2.6 }
    static var wingA0: Float { columnsA[0] - 1.6 }
    static let roofY: Float = 2.32, headY: Float = 1.88
    /// The roof's Robertson steel deck seen from under it, painted cream-white: a deep rib every 0.24 m (`deckPitch`)
    /// running east-west, square to the living wing's long edge, out to the fascia (owner, round 11, with a photograph of
    /// the real overhang); its flat bottom `deckBottom` wide, its webs `deckWeb` across, `deckDeep` from the rib's bottom
    /// up to the deck's top between the ribs.
    static let deckPitch: Float = 0.24, deckBottom: Float = 0.055, deckWeb: Float = 0.022, deckDeep: Float = 0.127
    /// The overhang's recessed downlights: one row 1.2 m out from the glass, one in the middle of each 10 ft pane.
    static var downlightRowB: Float { facadeB + 1.2 }
    static let downlightStep: Float = 3.05

    /// The pool and the spa (round 10, from the owner's main floor plans, measured against their 20 ft bays and scale
    /// bar). Plan rectangles (x0, x1, y0, y1): the main body, 9.7 x 5.8 m, from bedroom 2's west line, its south-east
    /// corner cut away (`waterPlan` 0 and 1); the narrow arm running south along the living wing from under the east
    /// bench block (2); the channel under the west bench block, right outside our glass (3). The spa is a separate
    /// square let into the terrace south of the arm, 1.5 m off the living wing's glass. On the grid each is `a` (south)
    /// by `b` (west). The coping pads are `coping` wide and overhang the water by `nose`.
    static let waterPlan: [(Float, Float, Float, Float)] = [
        (0, 7.75, 8.6, 14.4), (7.75, 10.7, 8.6, 12.25), (9.15, 10.7, 6.45, 8.6), (0, 3.1, 6.45, 8.6),
    ]
    static let spaPlan: (Float, Float, Float, Float) = (9.15, 10.7, 13.55, 15.2)
    typealias GridRect = (a: (Float, Float), b: (Float, Float))
    static func gridRect(_ p: (Float, Float, Float, Float)) -> GridRect { ((planA(p.2), planA(p.3)), (planB(p.1), planB(p.0))) }
    static let waterRects: [GridRect] = waterPlan.map(gridRect)
    /// The main body (its deep part to the south-west) and the arm's south part, by name.
    static let poolA = waterRects[0].a, poolB = waterRects[0].b
    static let armA = waterRects[1].a, armB = waterRects[1].b
    static let spaA = gridRect(spaPlan).a, spaB = gridRect(spaPlan).b
    static let coping: Float = 0.6, nose: Float = 0.12
    /// The raised concrete bench block straddling the arm's north end in front of the bedrooms (plan). (The west one,
    /// over the channel right behind the desk, is gone: owner, round 11, "delete the concrete slab behind the desk".)
    static let benchPlan: [(Float, Float, Float, Float)] = [(8.85, 11.1, 6.9, 7.85)]
    static let benchHigh: Float = 0.42
    /// Where the terrace's joints are laid from: the pool's north-east corner, a coping's width out.
    static var jointOrigin: SIMD2<Float> { SIMD2(armA.0 - coping, armB.0 - coping) }
    /// Is a grid place over the pool's water?
    static func inPool(_ a: Float, _ b: Float) -> Bool {
        waterRects.contains { a > $0.a.0 && a < $0.a.1 && b > $0.b.0 && b < $0.b.1 }
    }
    /// How far a grid place is from the pool's or the spa's water (0 over it).
    static func toWater(_ a: Float, _ b: Float) -> Float {
        func rect(_ r: GridRect) -> Float {
            let da = max(r.a.0 - a, 0, a - r.a.1), db = max(r.b.0 - b, 0, b - r.b.1)
            return (da * da + db * db).squareRoot()
        }
        return (waterRects + [(spaA, spaB)]).map(rect).min() ?? 9
    }
    /// The same as shader code (named `hg`), as a float.
    static var toWaterCode: String {
        (waterRects + [(spaA, spaB)]).map {
            "length(max(max(float2(\($0.a.0), \($0.b.0)) - hg, hg - float2(\($0.a.1), \($0.b.1))), 0.0))"
        }.reduce("9.0") { "min(\($0), \($1))" }
    }

    /// The terrace's free outer edge (the owner's plans, round 10): a straight-ish west side about 6.1 m west of
    /// bedroom 2, rounding at the south-west into a soft hand-formed south edge about 17.5 m south of the bedroom wing's
    /// north wall, running to the living wing's west glass. Points (b, a) along the south edge; `westB` is the west side.
    static let edgePoints: [SIMD2<Float>] = [
        SIMD2(planB(-6.10), planA(14.6)), SIMD2(planB(-5.85), planA(15.9)), SIMD2(planB(-5.25), planA(16.5)),
        SIMD2(planB(-4.3), planA(16.8)), SIMD2(planB(-2.1), planA(17.1)), SIMD2(planB(1.0), planA(17.55)),
        SIMD2(planB(3.2), planA(17.7)), SIMD2(planB(5.1), planA(17.45)), SIMD2(planB(7.6), planA(17.4)),
        SIMD2(planB(9.5), planA(17.5)), SIMD2(planB(12.19), planA(17.5)),
    ]
    static let westB = planB(-6.10)
    /// Where the terrace's free south edge is (a) at a place across it (b): a Catmull-Rom curve through `edgePoints`,
    /// with a slow waver of its own (it was formed by hand). Past the west side there is no terrace.
    static func edgeAt(_ b: Float) -> Float {
        let p = edgePoints
        if b > westB + 0.001 { return planA(6.0) }
        if b >= p[0].x { return p[0].y }
        if b <= p[p.count - 1].x { return p[p.count - 1].y }
        var i = 0
        while i < p.count - 2 && b < p[i + 1].x { i += 1 }
        let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
        let t = (b - p1.x) / (p2.x - p1.x)
        let t2 = t * t, t3 = t2 * t
        let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
            + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
        // (Formed by hand: a slow swell and smaller bites, enough to be seen from the room as a soft wavy line; none
        //  where it meets the living wing's planter.)
        let waver = 0.10 * sin(0.85 * b + 0.4) + 0.06 * sin(2.3 * b + 1.7) + 0.03 * sin(5.9 * b + 0.3)
        return y + waver * smoothstep(facadeB + 0.9, facadeB + 2.0, b)
    }

    /// The moment of the day the scene is lit for (13h in October: see `Daylight`).
    static let design: Float = 0.59
    /// How strong the outdoor sun is at the stage sun's full strength.
    static let outdoorPower: Float = 1350
    /// What a spot's intensity is to make the light a directional one of `outdoorPower` gave (see `addOutdoorSun`).
    /// (Measured: the sunlit terrace at 13 h the same to a level of 255 as the directional light gave it.)
    static let outdoorSpotGain: Float = 11
    /// The camera: seated, level, turned 37.5 degrees to the left of square to the glass, in front of and to the right of
    /// the table, so that its front edge falls some 12 degrees across the frame; stepping straight back for the others.
    static func eye(_ framing: Framing) -> SIMD3<Float> {
        let close = SIMD3<Float>(1.30, 0.45, 1.72)
        switch framing {
        case .close: return close
        case .mid: return close - forward * 0.35
        case .wide: return close - forward * 0.75
        }
    }
    static var eye: SIMD3<Float> { eye(.close) }
    static let yaw: Float = -wallTurn
    /// The sun as it goes over the house in October at 34 N (SPEC 5.2): at the scene's moment (about 13:45) bearing 194,
    /// 43 degrees up, ahead and well to the right of the lens (which looks along 142); it rises at about 102 (behind
    /// the living wing, out of the frame on the left) and sets at about 258, behind us on the right (`swing` -156,
    /// `lift` 55). It is never in the frame: at the end of the day it lights the living wing's west face and the terrace
    /// from behind the lens, warm, with the lavender and pink of the sky away from it ahead. The stage's sun (a spot,
    /// which loses its light with distance) lights the room, the table and what is on it; out of doors its direction,
    /// colour and strength are carried by a light of the scene's own, a directional one (`View.outdoorSun`), which
    /// lights only what is out there (`outdoorCategory`).
    static let sunAim = SIMD3<Float>(0, 0, -0.6)
    static let sunAt = sunAim + simd_normalize(SIMD3<Float>(0.242 * cos(deg(43)), sin(deg(43)), -0.970 * cos(deg(43)))) * 9.3
    /// The bearing (compass degrees) a world direction looks along: the plan's north is +Z, its east -X.
    static func bearing(_ d: SIMD3<Float>) -> Float {
        let b = atan2(-d.x, d.z) * 180 / .pi
        return b < 0 ? b + 360 : b
    }
    static let sunReach: CGFloat = 15.0
    /// What is out of doors (the terrace, the pool's coping, the wing, the plants): lit by the outdoor sun, not the stage's.
    static let outdoorCategory = 64
    /// The middle of what the outdoor sun's shadows cover.
    static var outdoorMiddle: SIMD3<Float> { site(7.0, -5.5, 0) }
    /// The arc lamp's hood, over the table (just above the close frame), and the lamp's light (just under the hood).
    static let hoodAt = SIMD3<Float>(-0.20, 1.18, 0.20)

    // MARK: The lens

    /// The reference's lens: on a 16:9 frame it takes in `halfWidth` (the tangent) either side of straight ahead, about a
    /// 42 mm lens, level, shifted so the horizon is `horizonDown` of the way down.
    static let halfWidth: Float = 0.4292
    static let horizonDown: Float = 0.375
    /// How the frame lies (tangents above and below level): a 16:9 screen is the reference; a narrower one takes in as
    /// much across and a little more above and below; a wider one as much up and down and more across.
    static func window(_ framing: Framing, aspect: Float) -> (up: Float, down: Float) {
        let reference: Float = 16.0 / 9.0
        let tall16 = 2 * halfWidth / reference
        let tall = aspect < reference ? 2 * halfWidth / aspect : tall16
        let more = (tall - tall16) / 2
        return (horizonDown * tall16 + more, (1 - horizonDown) * tall16 + more)
    }

    /// The projection of a level lens shifted down: ndc y from `up` to `-down`, ndc x as wide as the aspect asks.
    static func lens(_ framing: Framing, aspect: Float, far: Float) -> SCNMatrix4 {
        let w = window(framing, aspect: aspect)
        let t = w.up, b = -w.down
        let n: Float = 0.10
        let r = aspect * (t - b) / 2
        var m = SCNMatrix4Identity
        m.m11 = CGFloat(1 / r)
        m.m22 = CGFloat(2 / (t - b))
        m.m32 = CGFloat((t + b) / (t - b))
        m.m33 = CGFloat(-(far + n) / (far - n))
        m.m34 = -1
        m.m43 = CGFloat(-2 * far * n / (far - n))
        m.m44 = 0
        return m
    }

    /// The vertical field of view that covers the whole shifted frame from the lens's axis (for sheets that ride in
    /// front of the lens), in radians.
    static func coveringFov(_ framing: Framing, aspect: Float) -> Float {
        let w = window(framing, aspect: aspect)
        return 2 * atan(max(w.up, w.down)) * 1.04
    }

    /// `STAHL_SKIP=garden,rooms,night` leaves those parts out of a test build (to measure what each costs).
    static func skips(_ part: String) -> Bool {
        (ProcessInfo.processInfo.environment["STAHL_SKIP"] ?? "").split(separator: ",").contains { $0 == part }
    }

    static func make() -> RemadeSceneEnvironment {
        let root = SCNNode()
        root.name = "stahl"
        let view = View()
        addRoom(to: root, view: view)
        // (The view first: the wing's glass mirrors its city.)
        addView(to: root, view: view)
        let out = SCNNode()
        out.name = "outdoors"
        root.addChildNode(out)
        addOutside(to: out, view: view)
        addWing(to: out, view: view)
        addHillside(to: out, view: view)
        if !skips("garden") { addGarden(to: out, view: view) }
        out.enumerateHierarchy { node, _ in node.categoryBitMask = outdoorCategory }
        addRain(to: root, view: view)
        addOutdoorSun(to: root, view: view)
        addFloorBounce(to: root, view: view)
        addLamp(to: root)
        if planView { if planSite { addSiteMarks(to: root) } else { addPlanMarks(to: root) } }
        if let dbg = ProcessInfo.processInfo.environment["STAHL_DBG"] {
            root.enumerateHierarchy { n, _ in if dbg.split(separator: ",").contains(where: { n.name == String($0) }) { n.isHidden = true } }
        }

        // (No drink on this desk: owner, round 13, "delete this cup in the stahl house". With no cup in the room the
        //  stage's drink cycle has nothing to fill, take away or serve: `Stage.drink` stays nil.)
        let book = paperback()
        // (Its yellow cover, right under the lamp, burnt past white at night: the print a little dimmer.)
        book.enumerateHierarchy { node, _ in
            for m in node.geometry?.materials ?? [] { m.multiply.contents = rgb(0.84, 0.84, 0.84) }
        }
        book.simdEulerAngles = SIMD3(0, deg(-14), 0)
        book.simdPosition = SIMD3(-0.075, 0, 0.245)
        let shades = sunglasses()
        shades.simdEulerAngles = SIMD3(0, deg(20), 0)
        shades.simdPosition = SIMD3(-0.060, 0.0225, 0.235)
        let magazine = DeskThings.magazine(issue: 3)
        // (On the desk's free left end: the desk is 70 cm deep, and in front of the pile it would hang over the edge.)
        magazine.simdEulerAngles = SIMD3(0, deg(-8), 0)
        magazine.simdPosition = SIMD3(-0.80, 0, 0.040)

        let things = [book, shades, magazine]
        var made = RemadeSceneEnvironment(
            root: root,
            props: things,
            // (What the lid, the glass and the chrome reflect: a bright, open room.)
            environmentName: "bloem_olive_house",
            environmentIntensity: 0.72,
            lights: [
                // 0. The sun, far off and wide, so that its light reaches the terrace, the pool and the wing; soft, through
                //    the day's haze (see `sunAt`).
                .init(
                    position: sunAt, target: sunAim, color: rgb(1.0, 0.95, 0.87), intensity: 300, cone: 64,
                    shadows: true, range: sunReach, shadowAlpha: 0.52,
                    shadowRadius: 5.0, category: ~outdoorCategory),
                // 1. The sky: a broad, hazy light from the glass, no shadow.
                .init(
                    position: SIMD3(0, 3.2, -3.2), target: SIMD3(0, 0, 0.2), color: rgb(0.80, 0.86, 0.96), intensity: 95,
                    cone: 110, shadows: false, range: 10),
                // 2. The room's own light thrown back from its pale ceiling and walls and off the bright terrace: a soft
                //    warm light from in front and above, so that what faces us (the covers) is lit by something. (No
                //    shadow.)
                .init(
                    position: SIMD3(0.1, 1.5, 3.2), target: SIMD3(0, 0.1, -0.1), color: rgb(1.0, 0.94, 0.84), intensity: 40,
                    cone: 80, shadows: false, range: 7),
                // (The lamp's light after dark is the scene's own, `addLamp`: lit only at night, so no pool of light
                //  on the table at dawn or sunset without a lamp on to make it.)
            ],
            daytime: .init(
                design: design, suns: [(0, -156, 55)], skies: [1, 2], nightLights: [], hourTint: 0.6,
                lowSunHold: 0.8),
            nightLamps: [],
            glassAir: (poolsideLidMarks(), 0.35),
            lidClarity: 0.34,
            restStrength: 1.4,
            // (No moon: at night the lamps and the pool are the light, and the city.)
            moonlight: 0,
            animated: view.animated,
            tick: { time in view.tick(time) },
            cameraFar: 400,
            ambientFrameRate: 30,
            artworkGain: 0.84,
            blacks: 0.48,
            blacksWarmth: 0.6,
            exposure: 0.12,
            contrast: 0.31,
            saturation: 1.04,
            bloom: 0.14,
            vignette: 0.30,
            keyDirection: sunAt - sunAim,
            keyColor: SIMD3(0.20, 0.18, 0.15),
            fillDirection: SIMD3(0.3, 0.8, 0.6),
            fillColor: SIMD3(0.012, 0.020, 0.022)
        )
        // (The deck's hook, once the stage's lights are in: see `handle(_:in:)`.)
        made.handling.lit = handle
        made.handling.lid = quietLid
        // The weather (round 14): the stage is told the generic part of it (cloud over the sun, rain, the ground wet: its
        // light, flare and shafts follow), and the scene shows the rest itself (`View.tick`).
        made.weatherFrom = { stageWeather(sky()) }
        made.weather = { _ in view.weatherChanged() }
        tintBounce(view.bounced + [view.ceiling].compactMap { $0 })
        return made
    }

    /// The deck as this scene has it: the sun is found again among the stage's lights, for the water, the city and the
    /// dawn to follow (`View`).
    static func handle(_ rig: TurntableRig, in world: SCNNode) {
        world.enumerateHierarchy { node, _ in
            guard let light = node.light, light.type == .spot else { return }
            if abs(light.zFar - sunReach) < 0.001 { View.current?.sun = (node, light, light.intensity) }
        }
        // The arm and the platter's polished metal are kept out of the lamp's pool (category 16): from over the table it
        // laid a white-hot glint along the platter's rim at any strength the pool could be seen at.
        rig.armYaw.enumerateHierarchy { node, _ in node.categoryBitMask = 16 }
        // (Round 13: the arm's polished metal took the mid-morning sun as a thin line at 245-247 at 10 h, close and wide.
        //  Its parts are held a little down and its polished metal made satin here (the counterweight mirrors the bright
        //  sky), on copies of their materials, so the other scenes' decks are not touched.)
        rig.armYaw.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry, let copy = geometry.copy() as? SCNGeometry else { return }
            copy.materials = geometry.materials.map { material in
                guard let made = material.copy() as? SCNMaterial else { return material }
                // (Its metal a little further down: the counterweight's top rim still took the 10 h sky at 246.)
                let metallic = ((made.metalness.contents as? NSNumber)?.floatValue ?? 0) > 0.3
                let hold: CGFloat = metallic ? 0.86 : 0.92
                if made.multiply.contents == nil {
                    made.multiply.contents = NSColor(white: hold, alpha: 1)
                } else if let c = (made.multiply.contents as? NSColor)?.usingColorSpace(.sRGB) {
                    made.multiply.contents = NSColor(
                        srgbRed: c.redComponent * hold, green: c.greenComponent * hold, blue: c.blueComponent * hold, alpha: 1)
                }
                // (And its polished metal satin: it mirrors the white sky less sharply.)
                if metallic {
                    let rough = (made.roughness.contents as? NSNumber)?.floatValue ?? 0
                    if rough < 0.42 { made.roughness.contents = NSNumber(value: 0.42) }
                }
                return made
            }
            node.geometry = copy
        }
        // (And the deck's other bright metal, the arm's rest and lift, the knobs: from the wide framing a chrome end took
        // the lamp as a burnt-white point.)
        rig.root.enumerateHierarchy { node, _ in
            let chrome = node.geometry?.materials.contains { material in
                guard let amount = material.metalness.contents as? NSNumber, amount.floatValue > 0.4 else { return false }
                guard let tone = (material.diffuse.contents as? NSColor)?.usingColorSpace(.deviceGray) else { return false }
                return tone.whiteComponent > 0.45
            }
            if chrome == true { node.categoryBitMask = 16 }
        }
        rig.spin.enumerateHierarchy { node, _ in
            let metal = node.geometry?.materials.contains { material in
                if let amount = material.metalness.contents as? NSNumber { return amount.floatValue > 0.4 }
                if let tone = (material.metalness.contents as? NSColor)?.usingColorSpace(.deviceGray) {
                    return tone.whiteComponent > 0.4
                }
                return false
            }
            if metal == true { node.categoryBitMask = 16 }
        }
    }

    /// The lid as clear smoked acrylic: a faint smoke in its panels, the room and the sky caught in them at a glance. It
    /// opens to the shared stop (`Props.lidOpen`, 72 degrees) at its normal size: kept clearer than the other scenes'
    /// (it stands over the bright pool and read as a big milky pane).
    /// Its edges are the deck's own (`Props.coverShell` draws the sheet's thickness in its shader). (The 5 mm bronze
    /// tubes that were laid round it here, under the panels' alpha, drew it as a copper wire box.)
    static func quietLid(_ rig: SCNNode) {
        rig.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] where material.value(forKey: "lidBox") != nil {
                material.setValue(NSNumber(value: Float(0.12)), forKey: "glassBody")
                material.setValue(NSNumber(value: Float(0.45)), forKey: "glassEdge")
                material.setValue(NSNumber(value: Float(0.10)), forKey: "glassSheen")
                material.setValue(NSNumber(value: Float(0.22)), forKey: "glassGleam")
                material.setValue(NSValue(scnVector3: SCNVector3(0.016, 0.013, 0.010)), forKey: "glassHue")
            }
        }
    }

    /// The sun out of doors: a light that follows the stage's sun (`View.tick`), lighting only what is out there, with its
    /// own shadow map over the terrace, the pool, the wing and the planting.
    ///
    /// (Round 13: it is a far, narrow spot, not a directional light. SceneKit fits a directional light's shadow to the
    /// camera's frustum, and this scene's lens is a projection of its own (`lens`, shifted and level): with it the
    /// directional light's shadow map was never applied, so nothing out of doors cast a shadow, for any setting of its
    /// projection, bias or size (with `.deferred` it was, which proved the map itself was drawn). A spot's shadow does
    /// not depend on the camera. 60 m off with a 34-degree cone its rays are within a few degrees of parallel over what
    /// the frame sees.)
    static let outdoorSunReach: Float = 60
    static func addOutdoorSun(to root: SCNNode, view: View) {
        let light = SCNLight()
        light.type = .spot
        light.color = rgb(1.0, 0.96, 0.89)
        light.intensity = 0
        light.spotInnerAngle = 30
        light.spotOuterAngle = 34
        light.castsShadow = true
        light.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.shadowSampleCount = 12
        light.shadowRadius = 2.2
        light.shadowColor = NSColor(white: 0, alpha: 0.80)
        light.shadowBias = 2
        light.zNear = CGFloat(outdoorSunReach - 24)
        light.zFar = CGFloat(outdoorSunReach + 24)
        light.categoryBitMask = outdoorCategory
        let node = SCNNode()
        node.light = light
        node.name = "outdoor sun"
        node.isHidden = true
        root.addChildNode(node)
        view.outdoorSun = node
    }

    /// At either end of the day the low sun comes in under the roof and lies across the room's floor behind the table
    /// and up its back wall: the room throws that warm light back onto what faces us (the cover on its stand, the pile).
    /// A broad, soft spot of the scene's own from the room behind the lens, shadowless, up only with the low sun.
    static let floorBouncePower: Float = 60
    static func addFloorBounce(to root: SCNNode, view: View) {
        let light = SCNLight()
        light.type = .spot
        light.color = rgb(1.0, 0.80, 0.62)
        light.intensity = 0
        light.spotInnerAngle = 20
        light.spotOuterAngle = 100
        light.castsShadow = false
        light.attenuationStartDistance = 1.5
        light.attenuationEndDistance = 4.5
        light.attenuationFalloffExponent = 2
        light.gobo?.contents = ScenePieces.softPoolGobo()
        light.gobo?.intensity = 1
        let node = SCNNode()
        node.light = light
        node.name = "floor bounce"
        // (From the floor in front of the cover, where the low sun lies: the cover faces the room, not the lens.)
        node.simdPosition = SIMD3(-1.10, 1.25, 2.78)
        node.simdLook(at: SIMD3(-0.15, 0.08, 0.0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        node.isHidden = true
        root.addChildNode(node)
        view.floorBounce = node
    }

    // MARK: What follows the hour

    /// Everything out there that follows the hour: the sky and the city, the water; the lamp's hood; and the sun at dawn.
    final class View {
        static weak var current: View?
        var animated: [SCNMaterial] = []
        /// What draws the moving cumulus (`cumulusCode`), and the clock it drifts on: the scene's ambience clock
        /// (`tick`'s time, which the stage gives modulo 192 s) counted on past each wrap, so the deck never jumps back.
        var clouded: [SCNMaterial] = []
        private var cloudBase: Double = 0
        private var cloudLast: Float = -1
        private var cloudSaid = SIMD2<Float>(-1, -1)
        /// The room models whose shared materials this build has finished (`roomModel`).
        var finishedModels = Set<String>()
        /// The cloud picture, one for every material that mirrors or draws the sky (one texture, not four).
        lazy var clouds: CGImage? = Resources.image("backdrops/stahl_clouds.jpg")
        var water: SCNMaterial?
        var city: SCNMaterial?
        /// The glass (the room in it).
        var glass: SCNMaterial?
        /// The coping, which the pool's light glows on after dark.
        var coping: SCNMaterial?
        /// The bedroom wing's glass (the sky in it), and what glows in its rooms after dark (a lamp left on).
        var wingGlasses: [SCNMaterial] = []
        var wingNight: [SCNMaterial] = []
        /// The terrace's concrete and the coping: the light the sky and the house throw on them at either end of the day.
        var terrace: [SCNMaterial] = []
        /// What takes the light thrown back off the sunlit terrace as a glow (the wing's roof, its white steel).
        var bounced: [SCNMaterial] = []
        /// The succulents' leaves, which the sun shines through (its direction and strength).
        var planting: [SCNMaterial] = []
        /// The ceiling, lit from below by what the sun and sky throw back off the terrace and the floor.
        var ceiling: SCNMaterial?
        /// Our own overhang's downlights (lit after dark, `night`).
        var ourLights: [SCNMaterial] = []
        /// The arc lamp's light (the scene's own), on only at night.
        var lamp: SCNNode?
        /// The bedside lamp behind us after dark (`addLamp`).
        var bedside: SCNNode?
        /// The lamp's hood inside, glowing after dark.
        var hood: SCNMaterial?
        /// The outdoor sun (`addOutdoorSun`), which follows the stage's.
        var outdoorSun: SCNNode?
        /// The low sun's light come back off the sunlit floor of the room, onto what faces us (`addFloorBounce`).
        var floorBounce: SCNNode?
        /// The stage's sun (found by `handle`), and the strength it was made with.
        var sun: (node: SCNNode, light: SCNLight, made: CGFloat)?
        private var said: [Float] = []
        private var dawnSaid: Float = -1

        init() { View.current = self }

        /// The weather (round 14): every material that takes it (`wxA`, `wxB`), the concrete that goes wet (and the sky in
        /// its film), the planting that moves in the wind, the rain's veils; what is shown now, eased towards what is wanted.
        var weathered: [SCNMaterial] = []
        var wetted: [SCNMaterial] = []
        var swaying: [SCNMaterial] = []
        var rainSheets: [(node: SCNNode, material: SCNMaterial, near: Bool)] = []
        private var air: Air?
        private var airWanted = Air()
        private var airAt: Double = 0
        private var skyLooked: Double = -1e9
        /// The weather the scene is showing, or going to (`StahlScene.sky`).
        private(set) var skyShown: Sky?

        /// The stage has had word of the weather (`Outdoors.sky`): it is looked at again at the next frame.
        func weatherChanged() { skyLooked = -1e9 }

        /// The weather eased towards what is wanted: it comes over in a quarter of a minute or so (the stage's own glide is
        /// sixteen seconds); the first time, straight to it (a still shows the weather, not a change of it).
        private func followWeather() -> Air {
            let now = CACurrentMediaTime()
            if now - skyLooked > 30 {
                skyLooked = now
                let sky = StahlScene.sky()
                skyShown = sky
                airWanted = Air(sky)
            }
            guard let shown = air else {
                air = airWanted
                airAt = now
                return airWanted
            }
            let dt = Float(min(max(now - airAt, 0), 1))
            airAt = now
            guard shown != airWanted else { return shown }
            let k = 1 - exp(-dt / 4.5)
            var l = shown.list
            let w = airWanted.list
            for i in l.indices {
                l[i] += (w[i] - l[i]) * k
                if abs(w[i] - l[i]) < 0.002 { l[i] = w[i] }
            }
            let eased = Air(list: l)
            air = eased
            return eased
        }

        /// The stage's sun as the stage would have it at an hour (its road over the house: `lightDaylight`), for the last
        /// of the low sun just after the stage has put it out.
        static func stageSunDirection(at hour: Double) -> SIMD3<Float> {
            let state = Daylight.state(at: hour, design: design)
            let offset = sunAt - sunAim
            let reach = simd_length(offset)
            let height = asin(min(max(offset.y / reach, -1), 1))
            let turned = atan2(offset.x, offset.z) + deg(-156) * state.along
            let lifted = min(max(height + deg(55) * state.higher, deg(5)), deg(76))
            return simd_normalize(SIMD3(sin(turned) * cos(lifted), sin(lifted), cos(turned) * cos(lifted)))
        }

        /// Once a frame: the clouds' drift, and the hour's look, written only when it has changed.
        func tick(_ time: Float) {
            driftClouds(time)
            let a = followWeather()
            let hour = Daylight.hour ?? Daylight.hour(of: design)
            let moment = Daylight.moment(at: hour)
            typealias C = SIMD3<Float>
            var w = Daylight.looks(at: moment, low: (0.20, 0.52))
            // The last minutes before sunrise are given a sun of their own (the stage's is the moon until it is up).
            let toDawn = moment >= 1 ? 2 - moment : 9
            let dawn: Float = Daylight.hour == nil ? 0 : 1 - smoothstep(0.0, 0.026, toDawn)
            raiseDawn(dawn)
            // The last of the low sun (round 14): the house stands high on its hill and the golden hour is the scene's
            // own: the low sun keeps the terrace and the living wing for the first twenty minutes after the stage has put
            // its sun out at sunset (`grace`), going as it goes down. (`sunUp`: the golden hour's palette, not the
            // afterglow's.)
            let (_, set) = Daylight.day()
            let clock = hour - 24 * (hour / 24).rounded(.down)
            let grace: Float = moment >= 1 && moment < 1.5 ? 1 - smoothstep(Float(set) + 0.08, Float(set) + 0.40, Float(clock)) : 0
            let sunUp: Float = moment < 1 ? 1 : grace
            // (While the last of the sun is on the house the sky is the golden hour's, not yet the afterglow's dusk.)
            w.gold += w.dusk * grace
            w.dusk *= 1 - grace
            var toSun = simd_normalize(sunAt - sunAim)
            var sunColour = C(1.0, 0.95, 0.86)
            var sunPower: Float = 1
            if let sun, !sun.node.isHidden, moment < 1 || dawn > 0 {
                toSun = simd_normalize(sun.node.simdWorldPosition - sunAim)
                if let c = (sun.light.color as? NSColor)?.usingColorSpace(.sRGB) {
                    sunColour = C(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
                }
                sunPower = Float(sun.light.intensity / max(sun.made, 1))
            } else if grace > 0.001 {
                toSun = Self.stageSunDirection(at: Double(set) - 0.01)
                sunColour = C(1.0, 0.62, 0.34)
                sunPower = 0.55 * grace * (1 - 0.92 * a.cloud)
            } else {
                sunPower = 0
            }
            // The weather on the sun: under a grey sky there is next to no sun (the stage has greyed and halved its own:
            // out of doors it all but goes), smog and the marine layer's high grey soften it. (A Santa Ana's clean amber sun
            // is held a shade down in the golden hour: on the white ledge it burnt past 245 in the red.)
            let direct = (1 - 0.90 * a.cloud) * (1 - 0.22 * a.haze) * (1 - 0.06 * a.santa * w.gold)
            // THE GOLDEN HOUR: how much of it there is (the low sun up, and the weather letting it make one).
            let goldW = w.gold * sunUp * min(a.gold, 1.15)
            let early: Float = moment < 0.5 || moment > 1.5 ? w.gold : 0
            let lightDir = toSun
            // The outdoor sun takes the stage sun's direction, colour and strength (outside, where the spot does not reach).
            // (Round 12, review: "at 7 h the house gets no sun": the morning sun is a warm low light again, a little held
            //  back towards neutral so the concrete stays concrete, and as strong as the evening's.)
            var lightColour = simd_mix(sunColour * C(1.0, 0.98, 0.95), C(1.0, 0.86, 0.70), C(repeating: 0.45 * early))
            // (The golden hour's own colour, round 14: an amber in the evening, a paler gold in the morning; deeper in a
            //  Santa Ana's clean air.)
            let goldTone = early > 0 ? C(1.0, 0.74, 0.48) : C(1.0, 0.64, 0.34) * C(1, 1 - 0.04 * a.santa, 1 - 0.10 * a.santa)
            lightColour = simd_mix(lightColour, goldTone, C(repeating: min(0.85 * goldW, 0.9)))
            let lightPower = sunPower * (1 + 0.35 * early) * direct
            func blend(_ a: C, _ b: C, _ c: C, _ d: C) -> C { a * w.day + b * w.gold + c * w.dusk + d * w.night }
            // The sky as the water mirrors it, low (some 8 degrees up) and high (linear light): the plate's own gradient.
            let skyLow = blend(C(0.62, 0.74, 0.90), C(0.98, 0.62, 0.48), C(0.26, 0.20, 0.36), C(0.020, 0.024, 0.050))
            let skyTop = blend(C(0.12, 0.30, 0.72), C(0.34, 0.34, 0.66), C(0.05, 0.07, 0.20), C(0.004, 0.007, 0.024))
            // (The city's lights go out with the dawn: before sunrise they fade through the dusk and are gone by the gold.)
            let evening = moment >= 1 && moment < 1.5
            let lightsOn = min(w.night + (evening ? 0.8 * w.dusk + 0.45 * w.gold * (1 - sunUp) : 0.35 * w.dusk), 1)
            // (Under a dark rain sky the house's lamps come on in the afternoon: the living wing a lit box in the grey.)
            let murk = smoothstep(0.6, 1.0, a.cloud) * (0.35 + 0.65 * min(a.rain, 1)) * (1 - w.night)
            let lampOn: Float = Daylight.hour == nil ? 0 : min(w.night + 0.85 * w.dusk + (moment > 0.5 ? 0.80 * w.gold : 0) + 0.75 * murk, 1)
            let poolOn: Float = Daylight.hour == nil ? 0 : min(w.night + 0.85 * w.dusk + (moment > 0.5 ? 0.15 * w.gold : 0) + 0.25 * murk, 1)
            let s = sunColour * sunPower * direct * simd_mix(C(1, 1, 1), goldTone, C(repeating: 0.7 * goldW))
            // The sun as the sky shows it: the light's bearing, at its true height (the light itself stays 5 degrees up).
            if moment < 1 {
                let flat = simd_normalize(SIMD2(toSun.x, toSun.z))
                let el = deg(47) * sin(.pi * moment) - deg(0.8)
                toSun = C(flat.x * cos(el), sin(el), flat.y * cos(el))
            } else if grace > 0.001 {
                let flat = simd_normalize(SIMD2(toSun.x, toSun.z))
                let el = -deg(1.5) * (1 - grace)
                toSun = C(flat.x * cos(el), sin(el), flat.y * cos(el))
            } else {
                toSun = C(0.3, -0.3, -0.9)
            }
            let morning: Float = moment < 0.5 ? 1 : 0
            let lowStage: Float = Daylight.hour == nil ? 0 : Daylight.lowSun(at: Daylight.hour, design: design)
            let low: Float = max(lowStage * min(sunPower * 1.2, 1), grace * 0.7) * direct
            let values: [Float] = [
                w.day, w.gold, w.dusk, w.night, skyLow.x, skyLow.y, skyLow.z, skyTop.x, skyTop.y, skyTop.z, lightsOn, lampOn,
                toSun.x, toSun.y, toSun.z, s.x, s.y, s.z, morning, lightDir.x, lightDir.y, lightDir.z, lightPower, low,
                sunUp, goldW, lightColour.x, lightColour.y, lightColour.z,
            ] + a.list
            let rounded = values.map { ($0 * 1000).rounded() / 1000 }
            guard rounded != said else { return }
            said = rounded
            func v3(_ c: C) -> NSValue { NSValue(scnVector3: SCNVector3(c.x, c.y, c.z)) }
            let looks = NSValue(scnVector4: SCNVector4(w.day, w.gold, w.dusk, w.night))
            // The weather's arguments, for every shader that takes them.
            let wxA = NSValue(scnVector4: SCNVector4(a.haze, a.marine, a.cloud, a.rain))
            let wxB = NSValue(scnVector4: SCNVector4(a.santa, min(a.gold, 1.15), a.wet, sunUp))
            for m in weathered {
                m.setValue(wxA, forKey: "wxA")
                m.setValue(wxB, forKey: "wxB")
            }
            // The grey sky in the wet concrete's film (and the city's glow in it after dark).
            let wetSky = (blend(C(0.60, 0.62, 0.66), C(0.52, 0.48, 0.48), C(0.15, 0.14, 0.18), C(0.030, 0.028, 0.036))
                + C(0.12, 0.07, 0.035) * w.night) * (1 - 0.25 * min(a.rain, 1))
            for m in wetted { m.setValue(v3(wetSky), forKey: "wetSky") }
            for m in swaying { m.setValue(NSNumber(value: a.wind), forKey: "windGain") }
            for sheet in rainSheets {
                sheet.material.setValue(NSNumber(value: a.rain), forKey: "dropAmount")
                let amount = min(a.rain * (sheet.near ? 1.6 : 2.2), 1) * (0.55 + 0.45 * (w.day + w.gold) + 0.25 * lampOn)
                sheet.node.opacity = CGFloat(amount)
                sheet.node.isHidden = amount < 0.004
            }
            if let water {
                water.setValue(v3(skyLow), forKey: "skyLow")
                water.setValue(v3(skyTop), forKey: "skyTop")
                water.setValue(v3(toSun), forKey: "toSun")
                water.setValue(v3(s), forKey: "sunLight")
                water.setValue(NSNumber(value: poolOn), forKey: "poolLamp")
                water.setValue(NSNumber(value: lampOn), forKey: "spaLamp")
                coping?.setValue(NSNumber(value: lampOn), forKey: "poolLamp")
                water.setValue(looks, forKey: "looks")
                water.setValue(NSNumber(value: morning), forKey: "morning")
            }
            for wingGlass in wingGlasses {
                wingGlass.setValue(looks, forKey: "looks")
                wingGlass.setValue(v3(toSun), forKey: "toSun")
                wingGlass.setValue(NSNumber(value: morning), forKey: "morning")
            }
            for m in wingNight { m.setValue(NSNumber(value: lampOn), forKey: "wingLamp") }
            if let city {
                city.setValue(looks, forKey: "looks")
                city.setValue(NSNumber(value: morning), forKey: "morning")
                city.setValue(v3(s), forKey: "sunLight")
                city.setValue(v3(toSun), forKey: "toSun")
                city.setValue(NSNumber(value: lightsOn), forKey: "lightsOn")
            }
            hood?.emission.intensity = CGFloat(0.55 * min(w.night + 0.6 * w.dusk, 1))
            for m in planting {
                m.setValue(v3(lightDir), forKey: "sunDir")
                m.setValue(NSNumber(value: lightPower * (0.45 * w.day + 1.1 * w.gold)), forKey: "sunThrough")
            }
            if let floorBounce, let light = floorBounce.light {
                floorBounce.isHidden = low < 0.01
                light.intensity = CGFloat(floorBouncePower * low)
                light.color = NSColor(
                    srgbRed: 1.0, green: CGFloat(0.80 - 0.10 * goldW), blue: CGFloat(0.62 - 0.14 * goldW), alpha: 1)
            }
            if let outdoorSun, let light = outdoorSun.light {
                outdoorSun.isHidden = lightPower < 0.002
                outdoorSun.simdPosition = outdoorMiddle + simd_normalize(lightDir) * outdoorSunReach
                outdoorSun.simdLook(at: outdoorMiddle, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
                light.color = NSColor(
                    srgbRed: CGFloat(lightColour.x), green: CGFloat(lightColour.y), blue: CGFloat(lightColour.z), alpha: 1)
                // (At the end of the day the low sun rakes the terrace, the columns and the planting from low ahead: held
                //  up out of doors, so its long shadows read. In the golden hour a little less: its amber is mostly red,
                //  and the coping's face burnt past 245 in the red.)
                light.intensity = CGFloat(outdoorSpotGain * outdoorPower * lightPower * (1 + 1.1 * w.gold * (1 - 0.5 * early)) * (1 - 0.30 * min(goldW, 1)))
                // (Smog and the high grey over the marine layer soften its shadows.)
                light.shadowRadius = CGFloat(2.2 * (1 + 1.6 * a.haze + 1.4 * a.marine + 3.0 * a.cloud))
            }
            // (Not the desk's lamp in the murk of a rainy afternoon: with its shadow map it cost a sixth of the frame, and the
            //  covers read in the grey daylight.)
            let lampNight: Float = Daylight.hour == nil ? 0 : min(w.night + 0.6 * w.dusk, 1)
            if let lamp, let light = lamp.light {
                lamp.isHidden = lampNight < 0.01
                light.intensity = CGFloat(42 * lampNight)
            }
            if let bedside, let light = bedside.light {
                bedside.isHidden = lampNight < 0.01
                light.intensity = CGFloat(16 * lampNight)
            }
            // The terrace's light thrown back: less of it with no sun on the terrace (a grey sky), gold off a terrace in the
            // low sun, a cool grey under rain cloud.
            let bounce = (0.50 * w.day + 0.38 * w.gold + 0.10 * w.dusk) * (1 - 0.40 * a.cloud)
            var tint = simd_mix(C(1, 1, 1), C(1.10, 0.84, 0.60), C(repeating: 0.85 * min(goldW, 1)))
            tint = simd_mix(tint, C(0.93, 0.97, 1.04), C(repeating: 0.6 * a.cloud * (1 - w.night)))
            for m in bounced { m.setValue(v3(tint), forKey: "bounceTint") }
            ceiling?.setValue(v3(tint), forKey: "bounceTint")
            // The terrace's own fill: in the evening the house's warm west faces and the lit sky behind us throw a warm
            // light back on it; in the morning the open sky over the basin, cool; under a grey sky the grey sky itself,
            // from everywhere.
            var fill = early > 0 ? C(0.58, 0.64, 0.76) * 0.22 * early : C(1.0, 0.80, 0.60) * 0.16 * w.gold
            fill = fill * (1 - a.cloud) + wetSky * 0.30 * a.cloud * (w.day + 0.6 * w.gold + 0.3 * w.dusk)
            fill += C(0.10, 0.06, 0.03) * goldW * (1 - early)
            for m in terrace { m.setValue(v3(fill), forKey: "terraceFill") }
            ceiling?.setValue(NSNumber(value: bounce), forKey: "bounce")
            for m in bounced { m.setValue(NSNumber(value: bounce), forKey: "bounce") }
            ceiling?.setValue(NSNumber(value: lampNight), forKey: "night")
            for m in ourLights { m.setValue(NSNumber(value: lampOn), forKey: "night") }
            if let glass {
                glass.setValue(NSNumber(value: lampNight), forKey: "roomLamp")
                glass.setValue(NSNumber(value: (w.day + 0.6 * w.gold + 0.2 * w.dusk) * (1 - 0.35 * a.cloud)), forKey: "roomDay")
            }
        }

        /// The cumulus deck's place: wind times the clock, in whole tiles of its picture (taken modulo 1 here, in double
        /// precision, so the shader's numbers stay small and the drift never steps). Written each frame it moves (the
        /// scene draws its ambience at 30 a second while a record is paused, 5 behind a window).
        private func driftClouds(_ time: Float) {
            if cloudLast >= 0, time < cloudLast - 1 { cloudBase += 192 }
            cloudLast = time
            let clock = cloudBase + Double(time)
            let shift = SIMD2<Double>(
                (clock * cloudWind.x).truncatingRemainder(dividingBy: 1),
                (clock * cloudWind.y).truncatingRemainder(dividingBy: 1))
            let now = SIMD2<Float>(Float(shift.x), Float(shift.y))
            guard now != cloudSaid else { return }
            cloudSaid = now
            let value = NSValue(point: NSPoint(x: shift.x, y: shift.y))
            for m in clouded { m.setValue(value, forKey: "cloudShift") }
        }

        /// The sun before sunrise: the stage's own sun light, taken out of the night and stood low ahead on the left, out of the frame
        /// (only while the hour is in the last minutes before sunrise; the stage takes it back with the day).
        private func raiseDawn(_ dawn: Float) {
            guard let sun else { return }
            if dawn < 0.004 {
                if dawnSaid > 0 {
                    dawnSaid = 0
                    if sun.light.intensity > 0, sun.node.isHidden == false, Daylight.hour.map({ Daylight.moment(at: $0) >= 1 }) == true {
                        sun.light.intensity = 0
                        sun.node.isHidden = true
                    }
                }
                return
            }
            let wanted = sun.made * CGFloat(1.1 * dawn)
            guard abs(dawn - dawnSaid) > 0.002 || abs(sun.light.intensity - wanted) > 0.5 || sun.node.isHidden else {
                return
            }
            dawnSaid = dawn
            // (Rising at about bearing 100, behind the living wing on the left, out of the frame.)
            let compass = deg(100), height = deg(5)
            let reach: Float = 40
            sun.node.simdPosition = sunAim + SIMD3(-sin(compass) * cos(height), sin(height), cos(compass) * cos(height)) * reach
            sun.node.simdLook(at: sunAim, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            sun.light.color = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.34, alpha: 1)
            sun.light.intensity = wanted
            sun.node.isHidden = false
        }
    }
}
