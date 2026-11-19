import AppKit
import SceneKit
import simd

extension AlpineScene {
    // MARK: What the view is doing

    /// Everything out of the window that follows the hour and the weather, and how it is shown now.
    final class View {
        var sky: SCNMaterial?
        var ranges: [SCNMaterial] = []
        /// The far village's lights in the valley, shown after dark only.
        var village: [SCNNode] = []
        var frost: [SCNMaterial] = []
        var weathered: [SCNMaterial] = []
        var animated: [SCNMaterial] = []
        var outdoorsMaterials: [SCNMaterial] = []
        var weather = Outdoors.Weather()
        var lamp: (node: SCNNode, light: SCNLight, full: CGFloat, glows: [SCNNode])? { didSet { said = [] } }
        var spill: (node: SCNNode, light: SCNLight, full: CGFloat)? { didSet { said = [] } }
        var logs: (node: SCNNode, light: SCNLight, full: CGFloat)? { didSet { said = [] } }
        var murk: (node: SCNNode, light: SCNLight, full: CGFloat)? { didSet { said = [] } }
        var firs: [(material: SCNMaterial, far: Float)] = []
        var bank: SCNNode?
        /// What is shown, eased towards what the hour and the weather want.
        private var shown: [Float]? = nil
        private var said: [Float] = []

        /// The look the hour and the weather call for, as one list of numbers (so that it can be eased as a whole):
        /// sky top (3), sky low (3), day picture, evening picture, stars, range shadow (3), range light (3), range as
        /// photographed, range brightness, veil, frost light (3), frost amount.
        private func wanted() -> [Float] {
            let hour = Daylight.hour ?? Daylight.hour(of: design)
            let moment = Daylight.moment(at: hour)
            typealias C = SIMD3<Float>
            // The four looks it moves between. (Range: the colours its shadows and its lights are graded to, where it is
            // not shown as photographed.)
            let day = (
                top: C(0.13, 0.28, 0.56), low: C(0.58, 0.68, 0.82), dark: C(0.50, 0.54, 0.62),
                light: C(0.86, 0.88, 0.92), bright: Float(0.92)
            )
            // (Alpenglow: the snow in the last sun pink, the faces turned from it cold blue.)
            let gold = (
                top: C(0.40, 0.40, 0.54), low: C(0.80, 0.64, 0.58), dark: C(0.22, 0.25, 0.46),
                light: C(0.96, 0.74, 0.70), bright: Float(1.0)
            )
            let dusk = (
                top: C(0.08, 0.10, 0.22), low: C(0.30, 0.27, 0.38), dark: C(0.20, 0.22, 0.32),
                light: C(0.50, 0.55, 0.72), bright: Float(0.95)
            )
            let night = (
                top: C(0.018, 0.035, 0.11), low: C(0.045, 0.07, 0.15), dark: C(0.022, 0.030, 0.055),
                light: C(0.30, 0.35, 0.48), bright: Float(0.9)
            )
            let w = Daylight.looks(at: moment, low: (0.33, 0.58))
            func blend(_ a: C, _ b: C, _ c: C, _ d: C) -> C { a * w.day + b * w.gold + c * w.dusk + d * w.night }
            var top = blend(day.top, gold.top, dusk.top, night.top)
            var low = blend(day.low, gold.low, dusk.low, night.low)
            var dark = blend(day.dark, gold.dark, dusk.dark, night.dark)
            var light = blend(day.light, gold.light, dusk.light, night.light)
            var bright = day.bright * w.day + gold.bright * w.gold + dusk.bright * w.dusk + night.bright * w.night
            let level = w.day + 0.7 * w.gold + 0.32 * w.dusk + 0.06 * w.night
            // Weather: cloud takes the colour out of the sky and the light off the peaks, and it is darker than a clear day;
            // fog, rain and snow veil the range in the colour of the air, leaving a ghost of its ridge.
            let grey = min(weather.cloud + 0.5 * weather.fog + 0.6 * weather.rain + 0.6 * weather.snow, 1)
            let overcastTop = C(0.36, 0.39, 0.44) * level
            let overcastLow = C(0.46, 0.49, 0.54) * level
            top += (overcastTop - top) * grey
            low += (overcastLow - low) * grey
            let pictured = 1 - smoothstep(0.15, 0.75, grey)
            let flat = C(repeating: (dark.x + dark.y + dark.z + light.x + light.y + light.z) / 6) * C(0.93, 0.97, 1.03)
            dark += (flat * 0.75 - dark) * grey * 0.8
            light += (flat * 1.05 - light) * grey * 0.8
            bright *= 1 - 0.30 * grey
            let veil = min(0.97 * weather.fog + 0.50 * weather.snow + 0.30 * weather.rain + 0.12 * weather.cloud, 0.93)
            // How dark the valleys are under the peaks: a little by day, more at sunset, deep at night.
            let valleys = 0.92 * w.day + 0.72 * w.gold + 0.6 * w.dusk + 0.38 * w.night
            let stars =
                smoothstep(0.02, 0.10, moment >= 1 ? min(moment - 1, 2 - moment) : 0)
                * (1 - smoothstep(0.1, 0.6, weather.cloud + weather.fog + weather.rain + weather.snow))
            // The frost on the glass shows by the light of the sky behind it, and by the lamp's at night.
            // (Its own light by day and in a fog, the lamp's warm light after dark, when the cold is hardest and it is thickest.)
            // (Never the lamp's orange: lit warm, the frost ferns along the foot of the glass read as dry grass in the
            // valley, and the mist of drops along the bottom as an amber haze over it. Frost is cold, white-blue,
            // and at night only a faint glimmer.)
            let frostLight =
                low * 0.55 + C(0.30, 0.31, 0.33) * level + C(0.13, 0.15, 0.20) * (1 - min(level * 1.4, 1))
                + C(0.10, 0.10, 0.11) * min(weather.fog + weather.snow, 1)
            let frostAmount: Float = 1
            // (Chosen as they are to be seen; the shaders work in linear light.)
            func lin(_ c: C) -> C { C(pow(c.x, 2.2), pow(c.y, 2.2), pow(c.z, 2.2)) }
            top = lin(top)
            low = lin(low)
            dark = lin(dark)
            light = lin(light)
            // The lamp: lit as the scene was lit (when no hour is kept), from dusk to dawn, and a little when cloud or fog
            // makes the day dark: then it is a glow in the room, not what lights it.
            let gloom = Daylight.state(at: hour, design: design).gloom
            let murk = smoothstep(0.72, 1.0, weather.cloud + 0.7 * weather.fog)
            let lit = Daylight.hour == nil ? 1 : max(smoothstep(0.46, 0.54, gloom), 0.2 * murk)
            let closed =
                min(1.5 * weather.fog + 0.5 * weather.snow + 0.5 * weather.rain + 0.3 * weather.cloud, 1.5) * level
            // The air the far trees go into: the valley's, dimmer than the sky over it.
            let air = low * (0.30 + 0.45 * w.day) + C(0.5, 0.52, 0.56) * min(weather.fog, 1) * level * 0.6
            let backlit = min(w.gold + w.dusk + w.night, 1)
            return [
                top.x, top.y, top.z, low.x, low.y, low.z, w.day * pictured, w.gold * pictured, stars,
                dark.x, dark.y, dark.z, light.x, light.y, light.z, w.day * (1 - 0.7 * grey), bright, veil,
                frostLight.x, frostLight.y, frostLight.z, frostAmount, lit, valleys, closed, air.x, air.y, air.z,
                backlit,
            ]
        }

        /// Takes what is shown towards what is wanted (all the way, with `snap`), and tells the materials what has changed.
        func refresh(snap: Bool) {
            let target = wanted()
            var now = shown ?? target
            if snap { now = target } else { for i in now.indices { now[i] += (target[i] - now[i]) * 0.06 } }
            shown = now
            // (Only what has changed is written: anything written makes the scene draw again.)
            let rounded = now.map { ($0 * 2000).rounded() / 2000 }
            guard rounded != said else { return }
            said = rounded
            func v3(_ i: Int) -> NSValue { NSValue(scnVector3: SCNVector3(now[i], now[i + 1], now[i + 2])) }
            if let sky {
                sky.setValue(v3(0), forKey: "skyTop")
                sky.setValue(v3(3), forKey: "skyLow")
                sky.setValue(NSNumber(value: now[6]), forKey: "skyDay")
                sky.setValue(NSNumber(value: now[7]), forKey: "skyEvening")
                sky.setValue(NSNumber(value: now[8]), forKey: "starsOut")
            }
            for range in ranges {
                range.setValue(v3(9), forKey: "rangeDark")
                range.setValue(v3(12), forKey: "rangeLight")
                range.setValue(NSNumber(value: now[15]), forKey: "rangePhoto")
                range.setValue(NSNumber(value: now[16]), forKey: "rangeBright")
                range.setValue(NSNumber(value: now[17]), forKey: "rangeVeil")
                range.setValue(v3(3), forKey: "rangeAir")
            }
            if let lamp {
                lamp.light.intensity = lamp.full * CGFloat(now[22])
                if let spill {
                    spill.light.intensity = spill.full * CGFloat(now[22])
                    spill.node.isHidden = now[22] < 0.01  // (a light at nothing still costs its shading)
                }
                if let logs {
                    // (As the stage has its skies: the sky's light at the hour, a little more under cloud.)
                    let hour = Daylight.hour ?? Daylight.hour(of: design)
                    let sky = min(Daylight.state(at: hour, design: design).sky, 1.25)
                    logs.light.intensity = logs.full * CGFloat(sky * (1 + 0.35 * min(weather.cloud, 1)))
                    logs.node.isHidden = now[22] > 0.5
                }
                lamp.node.isHidden = now[22] < 0.01
                // (By day the lamp is out: no flame and no glow round it.)
                for glow in lamp.glows { glow.isHidden = now[22] < 0.05 }
                for body in AlpineScene.lampBody { body.setValue(NSNumber(value: now[22]), forKey: "lampGlow") }
            }
            if let murk {
                murk.light.intensity = murk.full * CGFloat(now[24])
                murk.node.isHidden = now[24] < 0.01
            }
            for range in ranges { range.setValue(NSNumber(value: now[23]), forKey: "rangeValleys") }
            // The village's lights come on as the valley goes dark (and are lost in fog or snow).
            let lights = now[8] > 0 ? min(now[8] * 1.6, 1) : 0
            for light in village where abs(Float(light.opacity) - lights) > 0.004 {
                light.opacity = CGFloat(lights)
                light.isHidden = lights < 0.01
            }
            // The far trees go into the air of the valley as the range does, the further the more.
            for fir in firs {
                fir.material.setValue(v3(25), forKey: "firAir")
                fir.material.setValue(
                    NSNumber(value: min(fir.far * 0.18 + now[17] * (0.15 + 0.75 * fir.far), 0.95)), forKey: "firVeil")
                fir.material.setValue(NSNumber(value: now[28]), forKey: "firBacklit")
            }
            for pane in frost {
                pane.multiply.contents = NSColor(
                    srgbRed: CGFloat(min(now[18], 1)), green: CGFloat(min(now[19], 1)), blue: CGFloat(min(now[20], 1)),
                    alpha: 1)
                pane.transparency = CGFloat(now[21])
            }
        }
    }

    // MARK: Out of the window

    /// The snow on the sill outside, and the range and the sky beyond.
    static func addOutside(to root: SCNNode, view: View) {
        let o = opening
        // The sill outside: a heavy board, and the day's snow lying on it, drifted higher towards the corners and cut by
        // the wind, grey-blue in its own shade.
        let timber = Mat.scanned("dark_wood", scale: SIMD2(4, 0.2), tint: rgb(0.42, 0.33, 0.26), normalStrength: 1.2)
        timber.setValue(NSNumber(value: Float(1.5)), forKey: "wetDeep")
        timber.setValue(NSNumber(value: Float(1)), forKey: "wetPatchy")
        view.weathered.append(timber)
        // (The board itself is under the snow, out of sight: only the snow on it shows through the glass.)
        let board = SCNNode(
            SCNBox(width: CGFloat(o.width + 0.4), height: 0.04, length: 0.22, chamferRadius: 0.004), material: timber)
        board.categoryBitMask = outside
        board.at(0, o.y0 - 0.075, glassZ - 0.13).adding(to: root)
        let snow = CourtyardScene.snowMaterial(repeats: SIMD2(8, 1.6))
        snow.multiply.contents = rgb(0.64, 0.66, 0.72)
        snow.normal.intensity = 1.3
        snow.isDoubleSided = true
        // (Banked up against the outside of the glass, over the casement's bottom rail, and falling away to the board's
        // edge. It lay low on the board before, below the rail's top: through the glass the rail's outer half showed as a
        // flat brown band the width of the window, ruled straight under the trees like the edge of a picture.)
        // (Its heights are from the rail's top, where the node stands, so that the weather's deeper snow raises it from there.)
        let railTop: Float = 0.10
        // (A shelf of snow: thin over the rail's top at the glass, rising a little to a flat top with wind ripples on it,
        // and breaking off in a ragged lip over the board's edge, where it wanders in and out. Rounded up against the
        // glass in a crest, it read as a roll of cotton wool in every pane.)
        let heap = Mesh.surface(uCount: 700, vCount: 64, wrapU: false) { u, v in
            let x = (u - 0.5) * (o.width + 0.36)
            let corners = pow(abs(u - 0.5) * 2, 4) + 0.6 * mullions.map { exp(-pow((x - $0) / 0.06, 2)) }.max()!
            let lying =
                0.008 + 0.005 * CourtyardScene.snowNoise(x / 0.20, 0.4, 31)
                + 0.003 * CourtyardScene.snowNoise(x / 0.06, 2.2, 32) + 0.010 * corners
            // (Its far edge breaks off in bites and tongues at several sizes, and rounds over slowly, as a wind-cut
            // cornice does; the top is wind-carved into lumps and scoops a few centimetres across, so it is never a
            // flat band with one ruled edge.)
            let lipAt =
                0.26 + 0.09 * CourtyardScene.snowNoise(x / 0.13, 5.1, 35) + 0.05 * CourtyardScene.snowNoise(x / 0.04, 7.3, 36)
                + 0.025 * CourtyardScene.snowNoise(x / 0.013, 9.7, 37)
            let ripples =
                0.0060 * CourtyardScene.snowNoise(x / 0.055 + v * 1.5, v * 4.5, 33)
                + 0.0025 * CourtyardScene.snowNoise(x / 0.018, v * 11, 34)
                + 0.0010 * CourtyardScene.snowNoise(x / 0.006, v * 25, 38)
            let rise = smoothstep(0, 0.10, v)
            let fall = smoothstep(lipAt - 0.06, lipAt + 0.16, v)
            let y = 0.004 + (lying * (1 + 0.15 * v) + ripples) * rise * (1 - fall) - 0.12 * fall * fall
            return SIMD3(x, y, glassZ - 0.004 - v * 0.29)
        }
        let bank = SCNNode(heap, material: snow)
        bank.categoryBitMask = outside
        bank.castsShadow = false
        bank.simdPosition = SIMD3(0, o.y0 + railTop, 0)
        bank.adding(to: root)
        view.bank = bank
        view.outdoorsMaterials += [timber, snow]

        // The range and the sky, far off, set up as seen from the lens: the photograph's foot just under the sill's line,
        // as wide as the window shows it.
        let distance: Float = 15
        let foot = deg(-29.6)
        let half = deg(14.5)
        let wide = 2 * distance * tan(half)
        let high = wide / plateAspect
        let pitch = foot + atan(high / 2 / distance)
        let towards = SIMD3<Float>(0, sin(pitch), -cos(pitch))
        let plate = SCNNode()
        plate.simdPosition = eye + towards * distance
        plate.simdLook(at: eye, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, 1))
        root.addChildNode(plate)
        let range = rangeMaterial()
        // (Taller than the photograph by `headroom` above it, with nothing there: the highest peak touches the photograph's
        // top, and the plate's edge cut it off flat.)
        let rangeHigh = high * (1 - plateCut)
        let rangeNode = SCNNode(
            SCNPlane(width: CGFloat(wide * spread), height: CGFloat(rangeHigh * (1 + headroom))), material: range)
        rangeNode.simdPosition = SIMD3(0, -plateCut / 2 * high + rangeHigh * headroom / 2, 0)
        rangeNode.castsShadow = false
        rangeNode.renderingOrder = -1
        plate.addChildNode(rangeNode)
        // The near slope below the cabin, in front of the range's foot: snow and young spruce heavy with it, rising over
        // the photograph's cut foot so that the mountains stand behind a hillside, not on the sill. (Graded with the range.)
        let slope = rangeMaterial(picture: nearSlope(), across: 5.2, head: 0)
        let slopeHigh = rangeHigh * 0.42
        let slopeNode = SCNNode(SCNPlane(width: CGFloat(wide * spread), height: CGFloat(slopeHigh)), material: slope)
        slopeNode.simdPosition = SIMD3(0, -plateCut / 2 * high - rangeHigh / 2 + slopeHigh / 2 + rangeHigh * 0.64, 0.05)
        slopeNode.castsShadow = false
        slopeNode.renderingOrder = 0
        plate.addChildNode(slopeNode)

        // A village far down the valley: a few warm windows, after dark only. (Each a tiny glow facing the lens.)
        let windowGlow = SCNMaterial()
        windowGlow.lightingModel = .constant
        windowGlow.diffuse.contents = NSColor.black
        windowGlow.emission.contents = Mat.cached("alpine.village.glow") {
            Tex.draw(width: 32, height: 32) { ctx, rect in
                let g = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.rgb(1.0, 0.78, 0.46, 1), Tex.rgb(1.0, 0.60, 0.28, 0.35), Tex.rgb(1.0, 0.5, 0.2, 0)] as CFArray,
                    locations: [0, 0.25, 1])!
                ctx.drawRadialGradient(
                    g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16,
                    options: [])
            }
        }
        windowGlow.emission.intensity = 0.85
        windowGlow.blendMode = .add
        windowGlow.writesToDepthBuffer = false
        windowGlow.readsFromDepthBuffer = true
        var lamps = SeededRandom(seed: 3301)
        for (cx, cy, count) in [(Float(-0.30), Float(0.010), 3), (Float(0.085), Float(0.004), 1), (Float(0.335), Float(0.016), 2)] {
            for _ in 0..<count {
                let size = Float(lamps.range(0.022, 0.036))
                let glow = SCNNode(SCNPlane(width: CGFloat(size), height: CGFloat(size)), material: windowGlow)
                glow.simdPosition = SIMD3(
                    (cx + Float(lamps.range(-0.012, 0.012))) * wide, (cy + Float(lamps.range(-0.006, 0.006))) * high, 0.02)
                glow.castsShadow = false
                glow.renderingOrder = 0
                glow.isHidden = true
                glow.opacity = 0
                plate.addChildNode(glow)
                view.village.append(glow)
            }
        }
        // The sky: bigger each way than the photograph, so that it fills the window above it, and a little further off.
        let skyScale: Float = 3.4
        let behind: Float = 0.3
        let grown = (distance + behind) / distance
        let sky = skyMaterial(scale: skyScale)
        let skyNode = SCNNode(
            SCNPlane(width: CGFloat(wide * skyScale * grown), height: CGFloat(high * skyScale * grown)), material: sky)
        skyNode.simdPosition = SIMD3(0, 0, -behind)
        skyNode.castsShadow = false
        skyNode.renderingOrder = -2
        plate.addChildNode(skyNode)
        view.sky = sky
        view.ranges = [range, slope]

        // The near slope below the window: young spruce with the day's snow on their boughs, nearer and larger than the
        // forest in the photograph, going into the valley's air the further off they stand. (Each tree is a photograph of a scanned tree stood up facing the window.)
        let pictures = (0..<6).compactMap { Resources.image("backdrops/fir_\($0).png") }
        if !pictures.isEmpty {
            var prints: [[SCNMaterial]] = []
            for (band, far) in [Float(0), 0.5, 1].enumerated() {
                prints.append(
                    pictures.map {
                        let print = Mat.decal($0)
                        print.isDoubleSided = true
                        print.setValue(NSValue(scnVector3: SCNVector3(0.5, 0.55, 0.6)), forKey: "firAir")
                        print.setValue(NSNumber(value: far * 0.18), forKey: "firVeil")
                        print.setValue(NSNumber(value: Float(0)), forKey: "firBacklit")
                        // (The pictures were lit pink by a sunset; they are taken back to the dark green of spruce needles,
                        // the snow left pale on the tops of the boughs; then the air of the valley over them.)
                        print.shaderModifiers = [
                            // They sway: a slow, irregular swing in gusts, each tree out of step with the next (its phase
                            // from where it stands), more at the tip than the trunk, and the boughs flutter a little.
                            .geometry: """
                            float swayUp = saturate(1.0 - _geometry.texcoords[0].y);
                            float swayH = swayUp * swayUp;
                            float3 swayAt = scn_node.modelTransform[3].xyz;
                            float swayPh = swayAt.x * 1.37 + swayAt.z * 0.71;
                            float swayT = scn_frame.time;
                            float gust = 0.35 + 0.65 * smoothstep(-0.4, 1.0, sin(swayT * 0.23 + swayPh * 0.4) * sin(swayT * 0.11 + swayPh));
                            float swing = (0.65 * sin(swayT * 0.9 + swayPh) + 0.25 * sin(swayT * 2.1 + swayPh * 2.3)) * gust
                                        + 0.06 * sin(swayT * 6.3 + swayPh * 5.0 + _geometry.position.y * 9.0) * swayUp;
                            // (0.15 of a unit at the tip: at 0.05 a 2 m spruce's tip moved 4 cm, and from the cabin they
                            // stood still. Owner, 2026-10-18: "make the trees wave".)
                            _geometry.position.x += swing * 0.15 * swayH;
                            """,
                            .surface: """
                            #pragma arguments
                            float3 firAir;
                            float firVeil;
                            float firBacklit;
                            #pragma body
                            float firA = _surface.diffuse.a;
                            float firL = dot(_surface.diffuse.rgb, float3(0.30, 0.59, 0.11)) / max(firA, 0.001);
                            float3 needles = float3(0.020, 0.030, 0.026) * (0.7 + 0.9 * firL);
                            float3 lying = float3(0.56, 0.60, 0.68) * firL;
                            float3 firC = mix(needles, lying, smoothstep(0.58, 0.88, firL));
                            // (Against a low sun or the night sky they are all but black: only their outline.)
                            firC *= 1.0 - 0.85 * firBacklit * (1.0 - 0.6 * smoothstep(0.58, 0.88, firL));
                            firC = mix(firC, firAir, firVeil);
                            _surface.diffuse = float4(firC * firA, firA);
                            """
                        ]
                        view.firs.append((print, far))
                        _ = band
                        return print
                    })
            }
            view.outdoorsMaterials += prints.flatMap { $0 }
            var rng = SeededRandom(seed: 1409)
            var stand: [(x: Float, top: Float, z: Float, tall: Float, kind: Int, turned: Bool, band: Int)] = []
            let lowSlope = (eye.y - (o.y0 + 0.10)) / (eye.z - glassZ)
            for _ in 0..<22 {
                let z = Float(rng.range(-9.0, -2.4))
                let spread = (eye.z - z) * 0.50
                // (Their tips just over the snow on the sill, a few of them a little higher: the range stands clear.)
                let line = eye.y - lowSlope * (eye.z - z)
                let top = line + (eye.z - z) * Float(rng.range(0.004, 0.032))
                let band = z > -4 ? 0 : (z > -6.5 ? 1 : 2)
                stand.append(
                    (
                        Float(rng.range(-1, 1)) * spread, top, z, Float(rng.range(1.6, 3.2)),
                        Int(rng.next() % UInt64(pictures.count)), rng.unit() < 0.5, band
                    ))
            }
            for tree in stand.sorted(by: { $0.z < $1.z }) {
                let wide = tree.tall * 640 / 1120
                let card = SCNNode(
                    SCNPlane(width: CGFloat(wide), height: CGFloat(tree.tall)), material: prints[tree.band][tree.kind])
                card.simdScale = SIMD3(tree.turned ? -1 : 1, 1, 1)
                card.castsShadow = false
                card.renderingOrder = 1
                card.at(tree.x, tree.top - tree.tall * 0.45, tree.z).adding(to: root)
            }
        }
    }

    /// The sky for the hour: the day photograph's own sky (with its high cloud), the evening photograph's sky at sunset,
    /// a gradient from the horizon up at dusk and night, and the stars over it.
    private static func skyMaterial(scale: Float) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Mat.cached("alpine.sky.blank") {
            Tex.draw(width: 4, height: 4) { ctx, rect in
                ctx.setFillColor(Tex.gray(1))
                ctx.fill(rect)
            }
        }
        m.writesToDepthBuffer = true
        func picture(_ name: String) -> SCNMaterialProperty {
            let property = SCNMaterialProperty(contents: Resources.image(name) as Any)
            property.mipFilter = .linear
            return property
        }
        m.setValue(picture("backdrops/alpine_sky_day.jpg"), forKey: "skyDayPicture")
        m.setValue(picture("backdrops/alpine_sky_evening.jpg"), forKey: "skyEveningPicture")
        m.setValue(
            SCNMaterialProperty(contents: Mat.cached("backdrop.alpine.stars") { Tex.alpineStars() }), forKey: "skyStars"
        )
        m.setValue(NSNumber(value: scale), forKey: "skyScale")
        let cirrus = SCNMaterialProperty(contents: Mat.cached("alpine.cirrus.1") {
            // Thin high cloud: long soft streaks, combed one way, in drifts. (Tiles both ways.)
            Tex.blur(
                Tex.draw(width: 1024, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 4242)
                    for _ in 0..<260 {
                        let x = rng.range(0, 1024)
                        let y = rng.range(0, 512)
                        let long = rng.range(80, 360)
                        let thick = rng.range(3, 14)
                        let a = rng.range(0.04, 0.16)
                        for dx in [-1024.0, 0, 1024.0] {
                            for dy in [-512.0, 0, 512.0] {
                                ctx.setFillColor(Tex.gray(1, a))
                                ctx.fillEllipse(in: CGRect(x: x + dx, y: y + dy, width: long, height: thick))
                            }
                        }
                    }
                }, radius: 9)
        })
        cirrus.wrapS = .repeat
        cirrus.wrapT = .repeat
        cirrus.mipFilter = .linear
        m.setValue(cirrus, forKey: "skyCirrus")
        m.setValue(NSValue(scnVector3: SCNVector3(0.02, 0.07, 0.27)), forKey: "skyTop")
        m.setValue(NSValue(scnVector3: SCNVector3(0.30, 0.43, 0.65)), forKey: "skyLow")
        m.setValue(NSNumber(value: Float(1)), forKey: "skyDay")
        m.setValue(NSNumber(value: Float(0)), forKey: "skyEvening")
        m.setValue(NSNumber(value: Float(0)), forKey: "starsOut")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            texture2d<float> skyDayPicture;
            texture2d<float> skyEveningPicture;
            texture2d<float> skyStars;
            texture2d<float> skyCirrus;
            float skyScale;
            float3 skyTop;
            float3 skyLow;
            float skyDay;
            float skyEvening;
            float starsOut;
            #pragma body
            constexpr sampler skyClamp(filter::linear, mip_filter::linear, address::clamp_to_edge);
            constexpr sampler skyWrap(filter::linear, mip_filter::linear, address::repeat);
            // (Where this point is on the day photograph: 0 to 1 across and down it.)
            float2 skyP = (_surface.diffuseTexcoord - 0.5) * skyScale + 0.5;
            // (Mirrored: the photograph's sun-glare stands on the right, where the sun is.)
            skyP.x = 1.0 - skyP.x;
            float skyUp = saturate((0.62 - skyP.y) / 1.3);
            float3 skyCol = mix(skyLow, skyTop, pow(skyUp, 0.55));
            float skySide = smoothstep(-0.30, 0.03, skyP.x) * smoothstep(1.30, 0.97, skyP.x);
            // (Above the photograph its top carries on and gives way to the sky's own colour slowly: no edge.)
            // (Only the photograph's upper sky: lower down it has a peak of its own, which floated over the range in another
            // haze, and its foot was filled with smeared columns.)
            // (Fading out below the photograph's clear upper sky, never stretched down: held at one row, it drew the
            // columns of that row down the sky.)
            // (By day the sky is the hour's gradient with thin high cloud over it, drifting: the photograph's sky had one
            // round cloud in it that read as a cartoon, and below it smeared columns.)
            float2 cirrusAt = float2(skyP.x * 1.3 + scn_frame.time * 0.0015, skyP.y * 3.2);
            float cirrus = skyCirrus.sample(skyWrap, cirrusAt).r * (1.0 - smoothstep(0.05, 0.55, skyP.y + 0.5 * skyUp * 0.0));
            skyCol = mix(skyCol, float3(0.94, 0.95, 0.97) * (0.85 + 0.15 * skyUp), saturate(cirrus * 2.2) * 0.65 * (skyDay + 0.3 * skyEvening));
            // (The evening photograph is wider for its height: it spans the day photograph's width and nine tenths of its height.)
            float2 skyQ = float2(skyP.x, skyP.y / 0.907);
            skyCol = mix(skyCol, skyEveningPicture.sample(skyClamp, skyQ).rgb,
                         skyEvening * skySide * smoothstep(-0.55, 0.06, skyQ.y) * (1.0 - smoothstep(0.10, 0.26, skyQ.y)));
            float2 starUV = float2(fract(skyQ.x + 0.43), skyQ.y < 0.0 ? fmod(-skyQ.y, 0.42) + 0.02 : skyQ.y);
            // (Fewer middling stars: most go down towards the faint, the few bright ones stay. A sky of stars that are all
            // much of a brightness reads as noise.)
            float3 star = skyStars.sample(skyWrap, starUV).rgb;
            float starL = max(star.r, max(star.g, star.b));
            skyCol += star * 1.15 * pow(saturate(starL), 0.8) * starsOut;
            _surface.diffuse = float4(skyCol * 1.2, 1.0);
            """
        ]
        return m
    }

    /// The range, cut out of its sky, graded for the hour: as photographed by day; at sunset the snow lit pink and gold
    /// and the shade purple; at night grey-blue in the moonlight, its ridge always paler than the sky behind it; and under
    /// cloud or falling snow flattened and veiled in the colour of the air.
    private static let spread: Float = 2.2
    private static let headroom: Float = 0.3
    private static func rangeMaterial(picture slopePicture: CGImage? = nil, across: Float? = nil, head: Float? = nil)
        -> SCNMaterial
    {
        let m = SCNMaterial()
        m.lightingModel = .constant
        // (The photograph is read in the shader, so that past its ends it can go on mirrored: SceneKit's mirror wrap did
        // not take with a transformed picture, and the range stopped dead in the right-hand pane.)
        m.diffuse.contents = NSColor.white
        let photograph = slopePicture ?? Resources.image("backdrops/alpine_range.png")
        let picture = SCNMaterialProperty(contents: photograph.map { $0 as Any } ?? NSNull())
        picture.mipFilter = .linear
        m.setValue(picture, forKey: "rangePicture")
        // (The plate is `spread` times the photograph's width, `headroom` taller above it with nothing there (the highest
        // peak touches the photograph's top, and the plate's edge cut it off flat). Mirrored as the sky is, the high
        // peaks to the left; the window sees the photograph from about 0.08 to 0.88 across, and past its ends the
        // photograph turns and runs on, so every pane at every screen's shape has the range behind it.)
        m.setValue(NSNumber(value: across ?? 0.55 * spread), forKey: "rangeAcross")
        m.setValue(NSNumber(value: Float(0.62)), forKey: "rangeMiddle")
        m.setValue(NSNumber(value: head ?? headroom), forKey: "rangeHead")
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        m.setValue(NSValue(scnVector3: SCNVector3(0.2, 0.25, 0.35)), forKey: "rangeDark")
        m.setValue(NSValue(scnVector3: SCNVector3(0.7, 0.75, 0.85)), forKey: "rangeLight")
        m.setValue(NSNumber(value: Float(1)), forKey: "rangePhoto")
        m.setValue(NSNumber(value: Float(1)), forKey: "rangeBright")
        m.setValue(NSNumber(value: Float(0)), forKey: "rangeVeil")
        m.setValue(NSValue(scnVector3: SCNVector3(0.3, 0.4, 0.6)), forKey: "rangeAir")
        m.setValue(NSNumber(value: Float(1)), forKey: "rangeValleys")
        m.setValue(NSNumber(value: Float(0)), forKey: "rangeDepth")
        m.shaderModifiers = [
            .surface: """
            #pragma arguments
            float3 rangeDark;
            float3 rangeLight;
            float rangePhoto;
            float rangeBright;
            float rangeVeil;
            float3 rangeAir;
            float rangeValleys;
            float rangeDepth;
            texture2d<float> rangePicture;
            float rangeAcross;
            float rangeMiddle;
            float rangeHead;
            #pragma transparent
            #pragma body
            constexpr sampler rangeSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
            float2 rangeUV = _surface.diffuseTexcoord;
            float rangeX = rangeMiddle + rangeAcross * (0.5 - rangeUV.x);
            float rangeY = rangeUV.y * (1.0 + rangeHead) - rangeHead;
            float2 rangeD = float2(rangeAcross, 1.0 + rangeHead);
            // (It turns at 0.14 and 0.97 of the photograph, not at its ends, which are low slopes hidden under the sill:
            // turned there, the panes past them had no mountains.)
            float rangeFold = fract((rangeX - 0.14) / 0.83 * 0.5) * 2.0;
            float4 rangeS = rangePicture.sample(
                rangeSampler, float2(0.14 + 0.83 * (1.0 - abs(rangeFold - 1.0)), saturate(rangeY)),
                gradient2d(dfdx(rangeUV) * rangeD, dfdy(rangeUV) * rangeD));
            float rangeA = rangeS.a * step(0.0, rangeY);
            float3 rangeC = rangeS.rgb / max(rangeS.a, 0.001);
            float rangeV = saturate(rangeY);
            float rangeL = dot(rangeC, float3(0.30, 0.59, 0.11));
            // (Snow in the light takes the light's colour, rock and the faces turned away the shade's.)
            float rangeLit = smoothstep(0.30, 0.78, rangeL);
            float3 graded = mix(rangeDark * (0.35 + 0.9 * rangeL), rangeLight * rangeL, rangeLit);
            float3 rangeOut = mix(graded, rangeC, rangePhoto) * rangeBright * 1.2;
            rangeOut *= mix(1.0, rangeValleys, smoothstep(0.30, 0.95, rangeV));
            // (Veiled more the higher up it is: the air thickest over the far peaks, the near slopes clearer.)
            float rangeFar = mix(1.0, 0.80, saturate(rangeV * 1.4));
            rangeOut = mix(rangeOut, rangeAir * 1.2, rangeVeil * rangeFar);
            // (A range further off: more of the air between, and less contrast.)
            rangeOut = mix(rangeOut, rangeAir * 1.1, rangeDepth);
            // The ridge does not stand cut out hard against the sky: right at its edge the air takes it a little.
            rangeA = rangeA * smoothstep(0.0, 0.9, rangeA);
            rangeOut = mix(rangeAir * 1.1, rangeOut, smoothstep(0.15, 1.0, rangeA));
            _surface.diffuse = float4(rangeOut * rangeA, rangeA);
            """
        ]
        return m
    }

    /// The hillside just below the cabin, as a picture to be graded like the range: a snowfield whose top edge rises and
    /// falls, with young spruce on it (the same photographs of scanned trees as the cards outside, taken to dark needles
    /// with snow lying on the boughs), smaller and fewer up the slope. Transparent above the ridge; it repeats across.
    private static func nearSlope() -> CGImage {
        Mat.cached("alpine.nearslope.7") {
            let w = 2048
            let h = 512
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            var rng = SeededRandom(seed: 7707)
            func ridge(_ x: CGFloat) -> CGFloat {
                let t = x / CGFloat(w) * 2 * .pi
                return CGFloat(h) * (0.44 + 0.13 * sin(t + 0.7) + 0.08 * sin(t * 3 + 2.1) + 0.04 * sin(t * 7 + 0.4) + 0.015 * sin(t * 19))
            }
            let snow = Tex.draw(width: w, height: h) { ctx, rect in
                ctx.clear(rect)
                let field = CGMutablePath()
                field.move(to: CGPoint(x: 0, y: 0))
                var x: CGFloat = 0
                while x <= CGFloat(w) {
                    field.addLine(to: CGPoint(x: x, y: ridge(x)))
                    x += 4
                }
                field.addLine(to: CGPoint(x: CGFloat(w), y: 0))
                field.closeSubpath()
                ctx.addPath(field)
                ctx.clip()
                let g = CGGradient(
                    colorsSpace: space, colors: [Tex.rgb(0.66, 0.70, 0.78), Tex.rgb(0.88, 0.90, 0.93)] as CFArray,
                    locations: [0, 1])!
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(h) * 0.45), options: [])
                for _ in 0..<500 {  // wind ripples and hollows
                    let r = rng.range(8, 50)
                    ctx.setFillColor(Tex.rgb(0.55, 0.60, 0.70, rng.range(0.04, 0.12)))
                    ctx.fillEllipse(
                        in: CGRect(x: rng.range(0, CGFloat(w)), y: rng.range(0, CGFloat(h) * 0.55), width: r * 3, height: r * 0.5))
                }
            }
            let firs = (0..<6).compactMap { Resources.image("backdrops/fir_\($0).png") }
            let trees = Tex.draw(width: w, height: h) { ctx, rect in
                ctx.clear(rect)
                guard !firs.isEmpty else { return }
                var stand: [(x: CGFloat, base: CGFloat, tall: CGFloat, k: Int, flip: Bool)] = []
                for _ in 0..<55 {
                    let x = rng.range(0, CGFloat(w))
                    let depth = pow(rng.unit(), 0.7)  // 0 at the ridge, 1 at the foot
                    let base = ridge(x) - 10 - depth * ridge(x) * 0.85
                    stand.append((x, base, 44 + 250 * depth * rng.range(0.7, 1.1), Int(rng.next() % UInt64(firs.count)), rng.unit() < 0.5))
                }
                for tree in stand.sorted(by: { $0.base > $1.base }) {
                    for shift in [CGFloat(0), CGFloat(w), -CGFloat(w)] {
                        let wide = tree.tall * 640 / 1120
                        let at = CGRect(x: tree.x + shift - wide / 2, y: tree.base - tree.tall * 0.05, width: wide, height: tree.tall)
                        guard at.maxX > 0, at.minX < CGFloat(w) else { continue }
                        ctx.saveGState()
                        if tree.flip {
                            ctx.translateBy(x: at.midX, y: 0)
                            ctx.scaleBy(x: -1, y: 1)
                            ctx.translateBy(x: -at.midX, y: 0)
                        }
                        ctx.draw(firs[tree.k], in: at)
                        ctx.restoreGState()
                    }
                }
            }
            // Snow first, the trees over it, each tree's picture taken to the dark green of spruce needles with what is
            // pale in it (the snow on the boughs) kept pale.
            func pixels(_ image: CGImage) -> [UInt8] {
                var p = [UInt8](repeating: 0, count: w * h * 4)
                p.withUnsafeMutableBytes { raw in
                    CGContext(
                        data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
                return p
            }
            let under = pixels(snow)
            let over = pixels(trees)
            var out = [UInt8](repeating: 0, count: w * h * 4)
            for i in 0..<(w * h) {
                let o = i * 4
                let a = Float(over[i * 4 + 3]) / 255
                var r: Float = 0, g: Float = 0, b: Float = 0
                if a > 0.001 {
                    let l = (0.30 * Float(over[i * 4]) + 0.59 * Float(over[i * 4 + 1]) + 0.11 * Float(over[i * 4 + 2])) / 255 / a
                    let lying = max(0, min(1, (l - 0.55) / 0.30))
                    let needles = SIMD3<Float>(0.05, 0.075, 0.065) * (0.7 + 0.9 * l)
                    let snowy = SIMD3<Float>(0.80, 0.83, 0.88) * (0.75 + 0.25 * l)
                    let c = needles + (snowy - needles) * (lying * lying * (3 - 2 * lying))
                    r = c.x * a; g = c.y * a; b = c.z * a
                }
                let ua = Float(under[i * 4 + 3]) / 255
                let oa = a + ua * (1 - a)
                out[o] = UInt8(min(255, (r + Float(under[i * 4]) / 255 * (1 - a)) * 255))
                out[o + 1] = UInt8(min(255, (g + Float(under[i * 4 + 1]) / 255 * (1 - a)) * 255))
                out[o + 2] = UInt8(min(255, (b + Float(under[i * 4 + 2]) / 255 * (1 - a)) * 255))
                out[o + 3] = UInt8(min(255, oa * 255))
            }
            return out.withUnsafeMutableBytes { raw -> CGImage? in
                CGContext(
                    data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            } ?? snow
        }
    }
}
