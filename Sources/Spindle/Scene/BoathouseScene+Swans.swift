import AppKit
import SceneKit
import simd

extension BoathouseScene {
    // MARK: Swans

    /// Trumpeter swans far out on the lake: a pair and a single one, small in the frame, drifting and turning, now and
    /// then putting their heads under; every few minutes, at no set time, one of them (the pair together) runs off
    /// across the water with its wings beating and climbs away low over the lake until it is gone past the far shore,
    /// and a while later new ones come gliding in and land, throwing spray. None after dark.
    ///
    /// Everything they do is worked out in their vertex shaders from the frame's own time (`swanState`): nothing is
    /// written to the scene for them, so they cost no frame that is not drawn anyway (the lake draws at its own steady
    /// rate), they stand still while nothing is drawn, and they go on from wherever the time has got to.
    ///
    /// They are seventy to ninety metres out, past the lake's picture (a sphere 26 m round the dock), so each is drawn
    /// as its own scale model nearer the lens along the same line of sight (`swanProxy`): from the lens it is the same
    /// picture, and it stays in front of the lake's picture.
    static func addSwans(to root: SCNNode, view: View) {
        let model = swanGeometry()
        // A pair (the second a few metres off its mate, a moment behind it) and a single one, each with its own
        // stretch of water, its own round of minutes between flights, and its own place in that round.
        let swans: [(home: SIMD2<Float>, id: Float, period: Float, phase: Float, side: Float)] = [
            (bearingAt(6, 88), 1, 330, 40, 0),
            (bearingAt(6, 88), 1, 330, 41.4, 3.2),
            (bearingAt(-13, 72), 2, 445, 120, 0),
        ]
        for (index, swan) in swans.enumerated() {
            for part in 0..<2 {
                let m = SCNMaterial()
                m.lightingModel = .constant
                // (A picture, so that the shader is given the texture coordinates that tell the parts apart.)
                m.diffuse.contents = Mat.cached("boathouse.swan.white.1") { Tex.draw(width: 4, height: 4) { ctx, rect in
                    ctx.setFillColor(Tex.gray(1))
                    ctx.fill(rect)
                } }
                m.isDoubleSided = true
                m.setValue(NSValue(scnVector3: SCNVector3(swan.home.x, swan.home.y, swan.id)), forKey: "swanHome")
                m.setValue(NSValue(scnVector3: SCNVector3(swan.period, swan.phase, swan.side)), forKey: "swanTimes")
                m.setValue(NSNumber(value: lakeClock), forKey: "swanClock")
                m.setValue(NSNumber(value: Float(1)), forKey: "swanAwake")
                m.setValue(NSNumber(value: water), forKey: "swanWater")
                m.setValue(NSNumber(value: Float(part == 1 ? 1 : 0)), forKey: "swanFlip")
                for key in ["swanSun", "swanSky", "swanAir", "swanMistLit"] {
                    m.setValue(NSValue(scnVector3: SCNVector3(0.5, 0.5, 0.5)), forKey: key)
                }
                m.setValue(NSValue(scnVector3: SCNVector3(sunDesign)), forKey: "swanToSun")
                m.setValue(NSNumber(value: Float(0)), forKey: "swanHaze")
                m.setValue(NSNumber(value: Float(0)), forKey: "swanMist")
                m.setValue(NSNumber(value: Float(part == 1 ? 0.55 : 1)), forKey: "swanShade")
                m.shaderModifiers = [.geometry: swanBody, .surface: swanLook]
                let geometry = model.copy() as! SCNGeometry
                geometry.materials = [m]
                let node = SCNNode(geometry: geometry)
                node.renderingOrder = part == 1 ? -4 : 0
                // (Its points are moved far from where the mesh lies: SceneKit must not leave it out as off screen.)
                node.geometry?.boundingBox = (SCNVector3(-30, -10, -30), SCNVector3(30, 30, 30))
                node.castsShadow = false
                node.categoryBitMask = outside
                node.name = "swan.\(index).\(part)"
                root.addChildNode(node)
                view.swans.append(m)
            }
        }
    }

    /// A point on the water so far out at a bearing (degrees right of ahead), as (x, z).
    static func bearingAt(_ bearing: Float, _ distance: Float) -> SIMD2<Float> {
        SIMD2(sin(deg(bearing)) * distance, -cos(deg(bearing)) * distance)
    }

    /// One swan as one mesh, its parts told apart by the first texture coordinate (0 the body, 1 the neck and head, 2
    /// the bill, 3 and 4 the left and right wing, 5 spray) and posed in the vertex shader: the body as it is, in the swan's own
    /// metres (x right, y up from the water, z ahead); the neck, head and bill as a tube along a curve the shader lays
    /// (the second coordinate how far along it, the position the point's place round it); the wings as flat panels (the
    /// position their span and chord), folded on the back or spread and beating.
    static func swanGeometry() -> SCNGeometry {
        var mesh = MeshBuilder()
        // The body: a long egg, fuller at the breast, the tail lifted, the back flat; its underside is laid on the water
        // by the shader.
        let along = 18, round = 14
        let base = UInt32(mesh.positions.count)
        for i in 0...along {
            let u = Float(i) / Float(along) * .pi
            let z = -0.52 * cos(u) + 0.02
            let r = pow(sin(u), 0.75)
            let breast: Float = z > 0 ? 1 + 0.10 * sin(u) : 1
            for j in 0..<round {
                let a = Float(j) / Float(round) * 2 * .pi
                let x = 0.22 * r * cos(a) * breast
                var y = 0.10 + 0.16 * r * sin(a) * (sin(a) > 0 ? 0.85 : 1.1)
                y += 0.10 * Self.smooth(-0.22, -0.50, z) * (0.6 + 0.4 * sin(a))
                let n = simd_normalize(SIMD3(x / 0.048, (y - 0.10) / 0.026, z / 0.27))
                mesh.vertex(SIMD3(x, y, z), n, SIMD2(0, 0))
            }
        }
        for i in 0..<UInt32(along) {
            for j in 0..<UInt32(round) {
                let a = base + i * UInt32(round) + j
                let b = base + i * UInt32(round) + (j + 1) % UInt32(round)
                let c = a + UInt32(round), d = b + UInt32(round)
                mesh.triangle(a, c, d)
                mesh.triangle(a, d, b)
            }
        }
        // The neck, head and bill: rings along the curve, each its radius.
        let steps = 30, ring = 8
        let neckBase = UInt32(mesh.positions.count)
        for i in 0...steps {
            let s = Float(i) / Float(steps) * 1.32
            let r: Float
            if s < 0.92 {
                r = 0.062 - 0.026 * s / 0.92
            } else if s < 1.16 {
                let q = (s - 0.92) / 0.24
                r = 0.036 + 0.012 * sin(q * .pi)
            } else {
                r = 0.026 * (1 - (s - 1.16) / 0.16) + 0.005
            }
            for j in 0..<ring {
                let a = Float(j) / Float(ring) * 2 * .pi
                let p = SIMD3<Float>(cos(a) * r, sin(a) * r * (s > 1.16 ? 0.6 : 1), 0)
                mesh.vertex(p, SIMD3(cos(a), sin(a), 0), SIMD2(s > 1.17 ? 2 : 1, s))
            }
        }
        for i in 0..<UInt32(steps) {
            for j in 0..<UInt32(ring) {
                let a = neckBase + i * UInt32(ring) + j
                let b = neckBase + i * UInt32(ring) + (j + 1) % UInt32(ring)
                let c = a + UInt32(ring), d = b + UInt32(ring)
                mesh.triangle(a, c, d)
                mesh.triangle(a, d, b)
            }
        }
        // The wings: span from the shoulder out (metres), chord from the leading edge back (a share of its width).
        for side in [Float(3), 4] {
            let w0 = UInt32(mesh.positions.count)
            let spans = 8, chords = 3
            for i in 0...spans {
                for j in 0...chords {
                    let span = Float(i) / Float(spans) * 1.12
                    mesh.vertex(SIMD3(span, Float(j) / Float(chords), 0), SIMD3(0, 1, 0), SIMD2(side, 0))
                }
            }
            for i in 0..<UInt32(spans) {
                for j in 0..<UInt32(chords) {
                    let a = w0 + i * UInt32(chords + 1) + j
                    let b = a + 1, c = a + UInt32(chords + 1), d = c + 1
                    mesh.triangle(a, c, d)
                    mesh.triangle(a, d, b)
                }
            }
        }
        // Spray: small flecks of water thrown up behind its feet as it runs off or lands (part 5; folded away to
        // nothing the rest of the time). Seen side on and end on.
        var rng = SeededRandom(seed: 7713)
        for k in 0..<18 {
            let c = SIMD3<Float>(Float(rng.range(-0.35, 0.35)), Float(rng.range(0.02, 0.30)), Float(rng.range(-1.8, -0.2)))
            let r = Float(rng.range(0.04, 0.09))
            let s0 = UInt32(mesh.positions.count)
            for (dx, dy, dz) in [(Float(0), Float(-1), Float(-1)), (0, 1, -1), (0, 1, 1), (0, -1, 1), (-1, -1, 0), (-1, 1, 0), (1, 1, 0), (1, -1, 0)] {
                mesh.vertex(c + SIMD3(dx, dy, dz) * r, SIMD3(0, 1, 0), SIMD2(5, Float(k)))
            }
            mesh.triangle(s0, s0 + 1, s0 + 2)
            mesh.triangle(s0, s0 + 2, s0 + 3)
            mesh.triangle(s0 + 4, s0 + 5, s0 + 6)
            mesh.triangle(s0 + 4, s0 + 6, s0 + 7)
        }
        return mesh.geometry()
    }

    static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Where a swan is and what it is doing at the frame's moment, worked out from its round of minutes: gliding in and
    /// landing, then afloat (drifting, turning, dipping its head), then running off across the water and climbing away,
    /// then gone until its round comes again. Sets `swP` (its place on or over the water, real metres), `swH` (its
    /// heading: 0 is ahead, away from the dock), `swSpread` (its wings: 0 folded, 1 spread), `swFlap` (their beat,
    /// radians), `swPitch`, `swDip` (its head under), `swFly` (its neck stretched out), `swShow`, `swOnWater`,
    /// `swSpeed` (m/s) and `swSpray`.
    static let swanState = """
        float swT = swanClock >= 0.0 ? swanClock : scn_frame.time;
        float swPer = swanTimes.x;
        float swLocal = swT + swanTimes.y;
        float swCycle = floor(swLocal / swPer);
        float swTau = swLocal - swCycle * swPer;
        // (Its own chances for this round: a golden-ratio sequence, the same on every machine.)
        float swR1 = fract(swCycle * 0.618034 + swanHome.z * 0.3719);
        float swR2 = fract(swCycle * 0.414214 + swanHome.z * 0.7071);
        float2 swHome = swanHome.xy;
        float2 swAway = normalize(swHome);
        float2 swAcross = float2(-swAway.y, swAway.x);
        // (Afloat: a slow wander about its stretch of water, facing the way it goes.)
        float swA = 0.011 + 0.003 * swanHome.z, swB = 0.0083 + 0.002 * swanHome.z;
        float2 swDrift = swHome + swAcross * (9.0 * sin(swA * swT + swanHome.z)) + swAway * (2.5 * sin(swB * swT + 1.7 * swanHome.z));
        swDrift += swAcross * swanTimes.z;
        float2 swVel = swAcross * (9.0 * swA * cos(swA * swT + swanHome.z)) + swAway * (2.5 * swB * cos(swB * swT + 1.7 * swanHome.z));
        float swDriftH = atan2(swVel.x, -swVel.y);
        float swLand = 20.0;
        float swGo = swLand + (0.45 + 0.35 * swR1) * (swPer - swLand - 70.0);
        float3 swP = float3(swDrift.x, 0.0, swDrift.y);
        float swH = swDriftH;
        float swSpread = 0.0, swFlap = 0.0, swPitch = 0.0, swFly = 0.0, swShow = 1.0, swOnWater = 1.0;
        float swSpeed = length(swVel), swSpray = 0.0;
        // (Now and then its head goes under for a few seconds.)
        float swDip = smoothstep(0.80, 0.93, sin(swT * (0.047 + 0.011 * swanHome.z) + 2.3 * swanHome.z + swanTimes.z));
        float swWing = swT * 6.2832 * 2.3;
        if (swTau < swLand) {
            // Gliding in from over the far shore and landing on its feet, throwing spray, then settling.
            float swS = swTau / swLand;
            float2 swTurn = float2(cos((swR2 - 0.5) * 1.1), sin((swR2 - 0.5) * 1.1));
            float2 swFrom2 = swAway * swTurn.x + swAcross * swTurn.y;
            float swT0 = swT - swTau + swLand;
            float2 swAt = swHome + swAcross * (9.0 * sin(swA * swT0 + swanHome.z) + swanTimes.z) + swAway * (2.5 * sin(swB * swT0 + 1.7 * swanHome.z));
            float swTouch = 0.80;
            float swIn = min(swS / swTouch, 1.0);
            float swSkid = max(swS - swTouch, 0.0) / (1.0 - swTouch);
            float swReach = 300.0 * (1.0 - swIn) + 9.0 * (1.0 - smoothstep(0.0, 1.0, swSkid)) * step(swTouch, swS) + 9.0 * step(swS, swTouch);
            float2 swXZ = swAt + swFrom2 * swReach;
            swP = float3(swXZ.x, 22.0 * pow(1.0 - swIn, 1.6), swXZ.y);
            swH = atan2(-swFrom2.x, swFrom2.y);
            swSpread = 1.0 - smoothstep(0.86, 1.0, swS);
            swFlap = 0.14 + 0.14 * sin(swWing * 0.5) * step(swS, 0.7) + 0.45 * smoothstep(0.70, 0.80, swS) * (1.0 - smoothstep(0.86, 0.95, swS)) * sin(swWing);
            swPitch = 0.10 + 0.25 * smoothstep(0.65, 0.80, swS) * (1.0 - smoothstep(0.82, 0.95, swS));
            swFly = 1.0 - smoothstep(0.80, 0.92, swS);
            swOnWater = step(swTouch, swS);
            swSpeed = swOnWater > 0.5 ? 5.0 * (1.0 - swSkid) : 14.0;
            swSpray = swOnWater * (1.0 - smoothstep(0.0, 0.7, swSkid));
            swDip = 0.0;
        } else if (swTau > swGo) {
            float swU = swTau - swGo;
            float2 swTurn = float2(cos((swR1 - 0.5) * 1.0), sin((swR1 - 0.5) * 1.0));
            float2 swDir = swAway * swTurn.x + swAcross * swTurn.y;
            float2 swStart = swHome + swAcross * (9.0 * sin(swA * (swT - swU) + swanHome.z) + swanTimes.z) + swAway * (2.5 * sin(swB * (swT - swU) + 1.7 * swanHome.z));
            float swHeadTo = atan2(swDir.x, -swDir.y);
            float swDH = swHeadTo - swDriftH;
            swDH = swDH - 6.2832 * floor((swDH + 3.1416) / 6.2832);
            swH = swDriftH + swDH * smoothstep(0.0, 1.6, swU);
            float swRun = 7.0;
            float swDist;
            float swUp = 0.0;
            if (swU < swRun) {
                // Running across the water, wings beating, feet pattering.
                swDist = 0.65 * swU * swU;
                swSpeed = 1.3 * swU;
                swSpray = smoothstep(1.0, 2.5, swU);
                swPitch = 0.16;
            } else {
                // Climbing away low over the lake.
                float swF = swU - swRun;
                swDist = 31.9 + 9.1 * swF + 0.12 * swF * swF;
                swUp = 1.1 * swF + 0.012 * swF * swF;
                swSpeed = 14.0;
                swPitch = 0.07;
                swOnWater = 0.0;
                // (Gone once it is past the far shore.)
                float swFar = length(swStart + swDir * swDist);
                swShow = step(swFar, 880.0);
            }
            swDip = 0.0;
            swSpread = smoothstep(0.0, 0.6, swU);
            swFlap = 0.12 + 0.62 * sin(swWing);
            swFly = smoothstep(0.0, 1.2, swU);
            float2 swXZ = swStart + swDir * swDist;
            swP = float3(swXZ.x, swUp, swXZ.y);
            swOnWater = swU < swRun ? 1.0 : 0.0;
        }
        swShow *= step(0.5, swanAwake);
        swDip *= 1.0 - swFly;
        swP.y += swanWater;
        """

    /// Real metres to the swan's scale model nearer the lens on the same line of sight (see `addSwans`): `swK` for the
    /// swan whose middle is at `swMid`, from the lens at `swCam`.
    static let swanProxy = """
        float3 swCam = scn_frame.inverseViewTransform[3].xyz;
        float3 swMid = swP + float3(0.0, 0.3, 0.0);
        float swD = max(length(swMid - swCam), 1.0);
        float swK = (9.0 + 14.0 * (1.0 - exp(-max(swD - 40.0, 0.0) / 300.0))) / swD;
        """

    /// The swan's vertex shader: its part posed in its own metres, laid on the water or in the air at its place and
    /// heading, mirrored under the water for its reflection (`swanFlip`), and moved to its scale model.
    static let swanBody = """
        #pragma arguments
        float3 swanHome;
        float3 swanTimes;
        float swanClock;
        float swanAwake;
        float swanWater;
        float swanFlip;
        #pragma body
        \(swanState)
        float swPart = _geometry.texcoords[0].x;
        float3 swL = _geometry.position.xyz;
        float3 swNL = _geometry.normal;
        if (swPart > 0.5 && swPart < 2.5) {
            // The neck and head along a curve in the swan's upright middle plane (z ahead, y up), between three poses:
            // held up in its S, stretched down with the head under, stretched out ahead in flight.
            float swS = _geometry.texcoords[0].y;
            float2 swQ0 = mix(float2(0.34, 0.16), float2(0.34, 0.10), swFly);
            float2 swQ1 = mix(mix(float2(0.58, 0.36), float2(0.62, 0.30), swDip), float2(0.62, 0.12), swFly);
            float2 swQ2 = mix(mix(float2(0.28, 0.84), float2(0.80, 0.10), swDip), float2(0.88, 0.13), swFly);
            float2 swQ3 = mix(mix(float2(0.40, 0.84), float2(0.84, -0.14), swDip), float2(1.10, 0.13), swFly);
            float swC = min(swS, 1.0), swM = 1.0 - swC;
            float2 swBz = swM * swM * swM * swQ0 + 3.0 * swM * swM * swC * swQ1 + 3.0 * swM * swC * swC * swQ2 + swC * swC * swC * swQ3;
            float2 swTn = normalize(3.0 * swM * swM * (swQ1 - swQ0) + 6.0 * swM * swC * (swQ2 - swQ1) + 3.0 * swC * swC * (swQ3 - swQ2) + 0.0001);
            swBz += swTn * max(swS - 1.0, 0.0) * 0.62;
            float3 swNy = float3(0.0, swTn.x, -swTn.y);
            swL = float3(_geometry.position.x, swBz.y, swBz.x) + swNy * _geometry.position.y;
            swNL = normalize(float3(_geometry.normal.x, 0.0, 0.0) + swNy * _geometry.normal.y);
        } else if (swPart > 4.5) {
            // Spray: thrown up and falling back, flickering, only while it runs or lands.
            float swK2 = _geometry.texcoords[0].y;
            float swJ = fract(swT * (1.7 + 0.13 * swK2) + swK2 * 0.37);
            swL = _geometry.position.xyz * float3(1.0, 0.4 + 1.6 * swJ * (1.0 - swJ) * 4.0, 1.0);
            swL = mix(float3(0.0, -0.5, -0.6), swL, step(0.03, swSpray));
            swNL = float3(0.0, 1.0, 0.0);
        } else if (swPart > 2.5) {
            // A wing: from the shoulder, folded along the back, or spread and beating (the outer half lagging).
            float swSide = swPart > 3.5 ? 1.0 : -1.0;
            float swSpan = _geometry.position.x, swChord = _geometry.position.y;
            float swWide = 0.40 * (1.0 - 0.55 * swSpan / 1.12);
            float3 swSh = float3(0.12 * swSide, 0.22, 0.10);
            float swPhi = swFlap + 0.35 * sin(swWing - 0.9) * smoothstep(0.4, 1.1, swSpan) * step(0.2, abs(swFlap));
            float3 swOpen = swSh + float3(swSide * cos(swPhi), sin(swPhi), -0.18) * swSpan + float3(0.0, 0.0, -swWide * swChord);
            float3 swShut = swSh + float3(swSide * 0.08, 0.05, -0.60) * swSpan + float3(swSide * 0.05, -0.08, 0.0) * swChord;
            swL = mix(swShut, swOpen, swSpread);
            swNL = normalize(mix(float3(swSide * 0.6, 0.8, 0.0), float3(-swSide * sin(swPhi), cos(swPhi), 0.0), swSpread));
        }
        // Its pitch, then its heading, then its place.
        float swCp = cos(swPitch), swSp = sin(swPitch);
        swL = float3(swL.x, swL.y * swCp + swL.z * swSp, swL.z * swCp - swL.y * swSp);
        swNL = float3(swNL.x, swNL.y * swCp + swNL.z * swSp, swNL.z * swCp - swNL.y * swSp);
        float3 swFwd = float3(sin(swH), 0.0, -cos(swH));
        float3 swRight = float3(cos(swH), 0.0, sin(swH));
        float3 swW = swP + swRight * swL.x + float3(0.0, swL.y, 0.0) + swFwd * swL.z;
        float3 swNW = swRight * swNL.x + float3(0.0, swNL.y, 0.0) + swFwd * swNL.z;
        // (Afloat, nothing of it is below the water: its underside lies on it, which is its waterline.)
        if (swOnWater > 0.5) { swW.y = max(swW.y, swanWater); }
        if (swanFlip > 0.5) {
            float swDeep = swW.y - swanWater;
            swW.x += 0.05 * sin(swT * 1.9 + swDeep * 24.0) * swDeep;
            swW.y = 2.0 * swanWater - swW.y;
            swNW.y = -swNW.y;
        }
        \(swanProxy)
        swW = swCam + (swW - swCam) * swK;
        if (swShow < 0.5) { swW = float3(0.0, -200.0, 0.0); }
        _geometry.position = scn_node.inverseModelTransform * float4(swW, 1.0);
        _geometry.normal = normalize((scn_node.inverseModelTransform * float4(swNW, 0.0)).xyz);
        """

    /// How a swan looks: white plumage, the bill and face black, lit by the hour's sun and sky (its light comes from the
    /// lake's own look, `View.refresh`), into the air with distance, into the mist at dawn. Its reflection darker.
    static let swanLook = """
        #pragma arguments
        float3 swanSun;
        float3 swanSky;
        float3 swanToSun;
        float3 swanAir;
        float swanHaze;
        float swanMist;
        float3 swanMistLit;
        float swanShade;
        #pragma body
        // (Seen from either side: the face turned to the lens is the one lit.)
        float3 slNv = dot(_surface.normal, _surface.view) < 0.0 ? -_surface.normal : _surface.normal;
        float3 slN = normalize((scn_frame.inverseViewTransform * float4(slNv, 0.0)).xyz);
        float slPart = _surface.diffuseTexcoord.x;
        float3 slAlb = mix(float3(0.80, 0.79, 0.76), float3(0.022, 0.020, 0.018), smoothstep(1.5, 1.9, slPart));
        float3 slC = slAlb * (swanSun * max(dot(slN, swanToSun), 0.0) + swanSky * (0.50 + 0.50 * slN.y));
        float slDp = length(_surface.position);
        float slD = 40.0 + 300.0 * -log(max(1.0 - (slDp - 9.0) / 14.0, 0.02));
        slC = mix(slC, swanAir, saturate((0.04 + 0.6 * swanHaze) * slD / 500.0));
        slC = mix(slC, swanMistLit, swanMist * 0.55);
        _surface.diffuse = float4(slC * swanShade, 1.0);
        """
}
