import AppKit
import SceneKit
import simd

extension LoftScene {
    // MARK: The cars in the street

    /// What drives and parks in the street: real models (see CREDITS: a 2001 Crown Victoria, New York's cab for twenty
    /// years, and a 2011 Mazda 6, both CC BY 4.0, rebuilt by `scripts/make-loft-cars.swift`), painted here. A cab is the
    /// Crown Victoria as it came, yellow with its lettering and its grime; the same car in black is a livery car; the
    /// Mazda is everybody else, in the dark, silver and white most cars are. Every car points along +x, wheels on y = 0.
    final class StreetCars {
        /// (`taxi`: today's cab, the midsize hybrid sedan in taxi yellow with its roof light; `cab`: the old Crown
        /// Victoria, still about; `sedan`: everybody else.)
        enum Kind {
            case cab, livery, sedan, taxi
            /// (Built on the Mazda's body.)
            var mazda: Bool { self == .sedan || self == .taxi }
        }
        /// How a sedan's body is drawn: its cabin raised (a crossover, an SUV) or lowered (a sports saloon) over the
        /// same chassis, wheels and lamps, so that the street is not one car in different paints.
        enum Body: Float { case saloon = 1.0, crossover = 1.32, suv = 1.55, low = 0.86 }

        /// One model's pieces: one set of points and an element for each of its materials, shared by every car of it.
        private struct Model {
            let sources: [SCNGeometrySource]
            let parts: [(name: String, element: SCNGeometryElement)]
        }
        private var models: [String: Model] = [:]
        /// One look a paint, shared by every car in it; and one geometry a look (each geometry is its own buffers on the
        /// graphics chip: one a car was 33 MB for the street).
        private var looks: [String: [String: SCNMaterial]] = [:]
        private var bodies: [String: SCNGeometry] = [:]
        /// Every car material, for the hour's light in their lacquer and glass (`StreetCars.follow`).
        private(set) var materials: [SCNMaterial] = []
        /// The lamps of the cars that are driven: lit after dark, in rain and in fog.
        private var lampLooks: LampLooks?

        /// Where each model's lamps are (from the models' own lamp glass), and how long the car is.
        static func headlamp(_ kind: Kind) -> SIMD3<Float> { kind.mazda ? SIMD3(1.95, 0.745, 0.70) : SIMD3(2.43, 0.72, 0.66) }
        static func taillamp(_ kind: Kind) -> SIMD3<Float> { kind.mazda ? SIMD3(-2.17, 0.91, 0.64) : SIMD3(-2.49, 0.89, 0.65) }
        static func length(_ kind: Kind) -> Float { kind.mazda ? 4.76 : 5.39 }

        private func model(_ name: String) -> Model? {
            if let made = models[name] { return made }
            let folder = Resources.url("models/\(name)")
            guard let json = try? Data(contentsOf: folder.appendingPathComponent("\(name).gltf")),
                let gltf = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                let bin = try? Data(contentsOf: folder.appendingPathComponent("\(name).bin")),
                let accessors = gltf["accessors"] as? [[String: Any]],
                let views = gltf["bufferViews"] as? [[String: Any]],
                let materials = gltf["materials"] as? [[String: Any]],
                let meshes = gltf["meshes"] as? [[String: Any]],
                let primitives = meshes.first?["primitives"] as? [[String: Any]]
            else { return nil }
            func floats(_ index: Int) -> [Float] {
                let a = accessors[index]
                let v = views[a["bufferView"] as? Int ?? 0]
                let start = v["byteOffset"] as? Int ?? 0
                let length = v["byteLength"] as? Int ?? 0
                return bin.subdata(in: start..<(start + length)).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            }
            func ints(_ index: Int) -> [UInt32] {
                let a = accessors[index]
                let v = views[a["bufferView"] as? Int ?? 0]
                let start = v["byteOffset"] as? Int ?? 0
                let length = v["byteLength"] as? Int ?? 0
                return bin.subdata(in: start..<(start + length)).withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
            }
            var positions: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var coords: [CGPoint] = []
            var parts: [(String, SCNGeometryElement)] = []
            for primitive in primitives {
                guard let attributes = primitive["attributes"] as? [String: Int], let p = attributes["POSITION"],
                    let n = attributes["NORMAL"], let t = attributes["TEXCOORD_0"], let i = primitive["indices"] as? Int
                else { continue }
                let base = UInt32(positions.count)
                let pf = floats(p), nf = floats(n), tf = floats(t)
                for k in 0..<(pf.count / 3) {
                    positions.append(SCNVector3(pf[k * 3], pf[k * 3 + 1], pf[k * 3 + 2]))
                    normals.append(SCNVector3(nf[k * 3], nf[k * 3 + 1], nf[k * 3 + 2]))
                    coords.append(CGPoint(x: CGFloat(tf[k * 2]), y: CGFloat(tf[k * 2 + 1])))
                }
                let name = materials[primitive["material"] as? Int ?? 0]["name"] as? String ?? ""
                parts.append((name, SCNGeometryElement(indices: ints(i).map { $0 + base }, primitiveType: .triangles)))
            }
            let made = Model(
                sources: [
                    SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals),
                    SCNGeometrySource(textureCoordinates: coords),
                ], parts: parts.map { (name: $0.0, element: $0.1) })
            models[name] = made
            return made
        }

        /// A car of the kind, in the paint (ignored for a cab), lamps lit or not (one that is driven has them).
        func car(_ kind: Kind, paint: SIMD3<Float>, driven: Bool, east: Bool = true, body shape: Body = .saloon) -> SCNNode {
            let node = SCNNode()
            let name = kind.mazda ? "loft_sedan" : "loft_cab"
            guard let model = model(name) else { return node }
            let shape: Body = kind.mazda ? shape : .saloon
            let key = "\(kind).\(paint.x).\(paint.y).\(paint.z).\(shape.rawValue)"
            let geometry: SCNGeometry
            if let made = bodies[key] {
                geometry = made
            } else {
                let look = self.look(kind, paint: paint, lift: shape.rawValue)
                // (A livery car has no sign on its roof.)
                let parts = model.parts.filter { kind != .livery || $0.name != "taxi_sign" }
                geometry = SCNGeometry(sources: model.sources, elements: parts.map(\.element))
                geometry.materials = parts.map { look[$0.name] ?? look["*"] ?? SCNMaterial() }
                bodies[key] = geometry
            }
            let body = SCNNode(geometry: geometry)
            body.categoryBitMask = 4
            body.castsShadow = true
            node.addChildNode(body)
            // The dark under it: soft, a little wider than the car.
            let under = Props.contactShadow(width: Self.length(kind) + 0.5, depth: 2.4, opacity: 1.5)
            under.enumerateHierarchy { piece, _ in
                piece.renderingOrder = 3
                piece.categoryBitMask = 4
            }
            under.simdPosition = SIMD3(0, 0.015, 0)
            node.addChildNode(under)
            if kind == .taxi { addRoofLight(to: node, lift: shape.rawValue) }
            if driven { addLamps(to: node, kind, east: east) }
            return node
        }

        /// Today's cab's roof light: a box across the roof, its sides lit with TAXI and the medallion's number (`follow`),
        /// its top and base dark plastic.
        private func addRoofLight(to node: SCNNode, lift: Float) {
            if roofSign == nil {
                let face = SCNMaterial()
                face.lightingModel = .physicallyBased
                face.diffuse.contents = Mat.cached("loft.taxi.roof.1") { Self.roofLightPicture() }
                face.emission.contents = face.diffuse.contents
                face.emission.intensity = 0
                face.roughness.contents = 0.35
                face.name = "cab sign"
                Self.reflecting(face)
                let shell = Mat.pbr(rgb(0.03, 0.03, 0.032), roughness: 0.4)
                Self.reflecting(shell)
                roofSign = (face, shell)
                materials += [face, shell]
            }
            guard let (face, shell) = roofSign else { return }
            let box = SCNBox(width: 0.30, height: 0.17, length: 0.82, chamferRadius: 0.03)
            // (All four sides lit with the sign, its top and base the shell: from up here it is its side that is seen, and
            // with the sign on its front and back only it read as a dark box.)
            box.materials = [face, face, face, face, shell, shell]
            let sign = SCNNode(geometry: box)
            sign.simdPosition = SIMD3(-0.22, 0.85 + (1.447 - 0.85) * lift + 0.085, 0)
            sign.categoryBitMask = 4
            sign.castsShadow = true
            node.addChildNode(sign)
            let base = SCNNode(geometry: SCNBox(width: 0.36, height: 0.03, length: 0.90, chamferRadius: 0.01))
            base.geometry?.firstMaterial = shell
            base.simdPosition = SIMD3(-0.22, 0.85 + (1.447 - 0.85) * lift + 0.005, 0)
            base.categoryBitMask = 4
            node.addChildNode(base)
        }
        private var roofSign: (SCNMaterial, SCNMaterial)?

        /// The roof light's face: TAXI in black on a lit cream panel, the medallion's number small beside it, a little
        /// grime at its foot.
        private static func roofLightPicture() -> CGImage {
            Tex.draw(width: 384, height: 96) { ctx, rect in
                ctx.setFillColor(Tex.rgb(0.93, 0.88, 0.70))
                ctx.fill(rect)
                ctx.setFillColor(Tex.gray(0, 0.18))
                ctx.fill(CGRect(x: 0, y: 0, width: 384, height: 12))
                for (text, size, x) in [("TAXI", CGFloat(54), CGFloat(150)), ("7J42", 22, 312)] {
                    let font = NSFont(name: "HelveticaNeue-CondensedBold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
                    let line = CTLineCreateWithAttributedString(
                        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(white: 0.06, alpha: 1)]))
                    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                    ctx.textPosition = CGPoint(x: x - b.width / 2 - b.minX, y: 48 - b.height / 2 - b.minY)
                    CTLineDraw(line, ctx)
                }
            }
        }

        /// The materials of one paint on one model, keyed by the model's material names ("*" for the sedan's one).
        private func look(_ kind: Kind, paint: SIMD3<Float>, lift: Float = 1) -> [String: SCNMaterial] {
            let key = "\(kind).\(paint.x).\(paint.y).\(paint.z).\(lift)"
            if let made = looks[key] { return made }
            var made: [String: SCNMaterial] = [:]
            switch kind {
            case .sedan, .taxi:
                let body = lacquer(
                    "loft_sedan", paint: paint, repaint: 1, reference: 0.80, gloss: kind == .taxi ? 0.55 : 0.75,
                    grime: kind == .taxi ? 1 : 0)
                if lift != 1 {
                    // The cabin raised or lowered over the same chassis: whatever is over the waist moves up or down
                    // with the roof, the wheels, the lamps and the sills stay.
                    body.setValue(NSNumber(value: lift), forKey: "carLift")
                    body.shaderModifiers?[.geometry] = """
                        #pragma arguments
                        float carLift;
                        #pragma body
                        float carY = _geometry.position.y;
                        if (carY > 0.85) { _geometry.position.y = 0.85 + (carY - 0.85) * carLift; }
                        """
                }
                made["*"] = body
            case .cab, .livery:
                // (Yellow as it came, or the same body in black: its lettering is lost in the black.)
                made["main_frame"] = lacquer(
                    "loft_cab", paint: kind == .cab ? SIMD3(1, 1, 1) : paint, repaint: kind == .cab ? 0 : 1,
                    reference: 0.62, gloss: kind == .cab ? 0.55 : 0.85)
                let glass = carGlass()
                made["glass"] = glass
                made["glass_window"] = glass
                let parts = Mat.pbr(.white, roughness: 0.55, metalness: 0.2)
                parts.diffuse.contents = Mat.texture("loft_cab_parts.jpg")
                parts.diffuse.mipFilter = .linear
                made["wheels_and_parts"] = parts
                made["interior_bottom"] = Mat.pbr(rgb(0.035, 0.034, 0.033), roughness: 0.8)
                let plate = Mat.pbr(.white, roughness: 0.5)
                plate.diffuse.contents = Mat.texture("loft_cab_plate.jpg")
                made["plate"] = plate
                let sign = Mat.pbr(.white, roughness: 0.4)
                sign.diffuse.contents = Mat.texture("loft_cab_sign.jpg")
                // (The roof light, lit with the lamps: see `follow`.)
                sign.emission.contents = Mat.texture("loft_cab_sign.jpg")
                sign.emission.intensity = 0
                sign.name = "cab sign"
                made["taxi_sign"] = sign
                materials += [glass, parts, made["interior_bottom"]!, plate, sign]
            }
            for (_, m) in made where m.name != "cab sign" { m.locksAmbientWithDiffuse = true }
            looks[key] = made
            return made
        }

        /// Paint with a clear coat over the model's own picture, its mask saying what is paint (red), glass (green) and
        /// bright metal (blue); with the street and the sky in the lacquer and the glass (`carLight`), and the air
        /// between it and the lens (`carAir`).
        private func lacquer(
            _ model: String, paint: SIMD3<Float>, repaint: Float, reference: Float, gloss: Float, grime: Float = 0
        ) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = Mat.texture("\(model)_body.jpg")
            m.diffuse.mipFilter = .linear
            m.diffuse.maxAnisotropy = 4
            m.roughness.contents = 0.5
            m.metalness.contents = 0.0
            let mask = SCNMaterialProperty(contents: Mat.texture("\(model)_mask.png") as Any)
            mask.mipFilter = .linear
            m.setValue(mask, forKey: "carMask")
            m.setValue(NSValue(scnVector3: SCNVector3(paint)), forKey: "carPaint")
            m.setValue(NSNumber(value: repaint), forKey: "carRepaint")
            m.setValue(NSNumber(value: reference), forKey: "carReference")
            m.setValue(NSNumber(value: gloss), forKey: "carGloss")
            m.setValue(NSNumber(value: Float(0)), forKey: "snowCover")
            m.setValue(NSNumber(value: Float(0)), forKey: "wetCover")
            m.setValue(NSNumber(value: grime), forKey: "carGrime")
            Self.reflecting(m)
            m.shaderModifiers?[.surface] = """
                #pragma arguments
                texture2d<float> carMask;
                float3 carPaint;
                float carRepaint;
                float carReference;
                float carGloss;
                float snowCover;
                float wetCover;
                float carGrime;
                #pragma body
                constexpr sampler carSampler(filter::linear, mip_filter::linear, address::repeat);
                float4 carM = carMask.sample(carSampler, _surface.diffuseTexcoord);
                float3 carBase = _surface.diffuse.rgb;
                float carLum = dot(carBase, float3(0.2126, 0.7152, 0.0722));
                // Repainted: the paint, as light or dark as the picture's own paint is there (its grime, its shut lines
                // and its shading kept).
                float3 carPainted = carPaint * clamp(carLum / carReference, 0.0, 1.25);
                carBase = mix(carBase, carPainted, carM.r * carRepaint);
                // A working car's grime: the sills and the lower doors road-dirty, the paint dulled a little all over.
                float carLow = 1.0 - smoothstep(0.25, 0.62, (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).y - (\(LoftScene.street)));
                carBase = mix(carBase, carBase * float3(0.55, 0.52, 0.48), carM.r * carGrime * (0.18 + 0.55 * carLow));
                // Glass: near black, the cabin dim through it.
                carBase = mix(carBase, carBase * 0.35, carM.g);
                _surface.diffuse.rgb = carBase;
                _surface.roughness = mix(mix(mix(0.62, 0.30, carM.r), 0.06, carM.g), 0.30, carM.b);
                _surface.metalness = 0.85 * carM.b;
                _surface.clearCoat = carGloss * carM.r + carM.g;
                _surface.clearCoatRoughness = 0.06 + 0.10 * wetCover;
                // Snow lying on the roof, the bonnet and the boot, the grey of snow under street lamps; rain beading.
                float3 snowUp = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
                float carSnow = snowCover * smoothstep(0.55, 0.85, snowUp.y);
                _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(0.20, 0.21, 0.23), carSnow);
                _surface.roughness = mix(_surface.roughness, 0.9, carSnow);
                _surface.clearCoat *= 1.0 - carSnow;
                """
            materials.append(m)
            return m
        }

        /// Separate glass (the cab's): dark, glossy, the street in it.
        private func carGlass() -> SCNMaterial {
            let m = Mat.pbr(rgb(0.02, 0.022, 0.026), roughness: 0.05)
            m.clearCoat.contents = 1.0
            m.clearCoatRoughness.contents = 0.04
            Self.reflecting(m)
            return m
        }

        /// The fragment stage every car material shares: what the lacquer and the glass mirror, worked out from where the
        /// reflected ray goes (the sky above the roofs, the buildings across the street with their windows, the road),
        /// with the hour's colours (`carSky`, `carFacade`, `carGround`, `carWindows`); and the air between the car and
        /// the lens, more of it the further off (`carAir`: its colour, and in w how much it closes in, for fog).
        static func reflecting(_ m: SCNMaterial) {
            m.setValue(NSValue(scnVector3: SCNVector3(0.62, 0.68, 0.76)), forKey: "carSky")
            m.setValue(NSValue(scnVector3: SCNVector3(0.20, 0.18, 0.17)), forKey: "carFacade")
            m.setValue(NSValue(scnVector3: SCNVector3(0.07, 0.07, 0.075)), forKey: "carGround")
            m.setValue(NSNumber(value: Float(0)), forKey: "carWindows")
            m.setValue(NSValue(scnVector4: SCNVector4(0.5, 0.55, 0.6, 0)), forKey: "carAir")
            var modifiers = m.shaderModifiers ?? [:]
            modifiers[.fragment] = """
                #pragma arguments
                float3 carSky;
                float3 carFacade;
                float3 carGround;
                float carWindows;
                float4 carAir;
                \(LoftScene.lampArguments)
                #pragma body
                \(LoftScene.lampBody)
                float3 carN = normalize(_surface.normal);
                float3 carV = normalize(_surface.view);
                float3 carR = (scn_frame.inverseViewTransform * float4(reflect(-carV, carN), 0.0)).xyz;
                float carF = 0.04 + 0.96 * pow(1.0 - saturate(dot(carN, carV)), 5.0);
                float carCoat = saturate(_surface.clearCoat);
                // Up past the roofs, the sky; level, the buildings across the street (the far side's, or ours behind the
                // lens), their windows lit after dark; below, the road.
                float carUp = carR.y;
                float carRoofs = smoothstep(0.18, 0.42, carUp);
                float carStreet = 1.0 - smoothstep(-0.08, 0.02, carUp);
                float carAround = atan2(carR.x, carR.z);
                float2 carCell = float2(carAround * 26.0, carUp * 30.0);
                float2 carIn = fract(carCell);
                float carPane = step(0.25, carIn.x) * step(carIn.x, 0.75) * step(0.3, carIn.y) * step(carIn.y, 0.8);
                float carLit = step(0.72, fract(sin(dot(floor(carCell), float2(12.9898, 78.233))) * 43758.5453));
                float3 carSeen = mix(carFacade + float3(1.0, 0.72, 0.42) * carPane * carLit * carWindows, carSky, carRoofs);
                carSeen = mix(carSeen, carGround, carStreet);
                _output.color.rgb += carSeen * carF * carCoat;
                // The air.
                float carFar = length(_surface.position);
                float carHaze = saturate((carFar - 38.0) / 70.0) * 0.35 + carAir.w * saturate(carFar / 60.0);
                _output.color.rgb = mix(_output.color.rgb, carAir.rgb, saturate(carHaze));
                """
            m.shaderModifiers = modifiers
        }

        /// The lamps of a car that is being driven, as real lamp units: in each head lamp's housing a dark chrome bowl
        /// under its glass with the bright core of the bulb inside it; a tight bloom that stays at the lamp; the tail lamps
        /// red lenses let into the body; on the road ahead the dipped beams' soft pool; and on a wet road each lamp's
        /// reflection drawn out towards us as a long broken streak (`streakPicture`). All lit by `follow`.
        /// (It had a glow card as big as the car's nose, a blurred square, and a beam picture of two bright wedges: the
        /// head lamps read as white smears past the car's outline and bands of light across the road.)
        private func addLamps(to node: SCNNode, _ kind: Kind, east: Bool) {
            if lampLooks == nil {
                let core = SCNMaterial()
                core.lightingModel = .constant
                core.diffuse.contents = NSColor.black
                core.emission.contents = rgb(1.0, 0.94, 0.84)
                core.emission.intensity = 0
                // The glass: clear over a chrome bowl, lit a little by the core, the street in it.
                let lens = Mat.pbr(rgb(0.10, 0.10, 0.11), roughness: 0.12, metalness: 0.9)
                lens.emission.contents = rgb(1.0, 0.92, 0.80)
                lens.emission.intensity = 0
                lens.clearCoat.contents = 1.0
                lens.clearCoatRoughness.contents = 0.03
                let tail = Mat.pbr(rgb(0.16, 0.012, 0.010), roughness: 0.2)
                tail.emission.contents = rgb(1.0, 0.045, 0.025)
                tail.emission.intensity = 0
                tail.clearCoat.contents = 1.0
                tail.clearCoatRoughness.contents = 0.04
                let bloom = Mat.cached("loft.car.bloom.4") { Self.bloomPicture() }
                let headGlow = Mat.decal(bloom, opacity: 0, additive: true)
                headGlow.multiply.contents = rgb(1.0, 0.92, 0.80)
                let tailGlow = Mat.decal(bloom, opacity: 0, additive: true)
                tailGlow.multiply.contents = rgb(1.0, 0.10, 0.05)
                headGlow.isDoubleSided = true
                tailGlow.isDoubleSided = true
                let beam = Mat.decal(Mat.cached("loft.beam.4") { Self.beamPicture() }, opacity: 0, additive: true)
                beam.multiply.contents = rgb(1.0, 0.88, 0.70)
                let streak = Mat.cached("loft.car.streak.1") { Self.streakPicture() }
                let headStreak = Mat.decal(streak, opacity: 0, additive: true)
                headStreak.multiply.contents = rgb(1.0, 0.90, 0.74)
                let tailStreak = Mat.decal(streak, opacity: 0, additive: true)
                tailStreak.multiply.contents = rgb(1.0, 0.08, 0.04)
                // (Brighter than a decal's colour can say: a lamp mirrored in water is nearly as bright as the lamp.)
                headStreak.diffuse.intensity = 2.4
                tailStreak.diffuse.intensity = 2.2
                // The dipped beams in the air ahead, as rain and mist show them: a soft wedge widening from the lamps.
                let haze = Mat.decal(Mat.cached("loft.beam.haze.2") { Self.hazePicture() }, opacity: 0, additive: true)
                haze.multiply.contents = rgb(1.0, 0.92, 0.80)
                haze.isDoubleSided = true
                // And the wet road's glare ahead of the car, where the beams lie on the water: a long bright sheen
                // running out in front, brightest a few metres out.
                let glare = Mat.decal(Mat.cached("loft.beam.glare.2") { Self.glarePicture() }, opacity: 0, additive: true)
                glare.multiply.contents = rgb(1.0, 0.90, 0.74)
                glare.diffuse.intensity = 1.0
                lampLooks = LampLooks(
                    core: core, lens: lens, tail: tail, headGlow: headGlow, tailGlow: tailGlow, beam: beam,
                    headStreak: headStreak, tailStreak: tailStreak, haze: haze, glare: glare)
                // (Named, so the weather leaves them alone: snow on a lit lamp's glass read as a grey blot.)
                lens.name = "car lamp"
                tail.name = "car lamp"
                materials += [lens, tail]
            }
            guard let looks = lampLooks else { return }
            let h = Self.headlamp(kind), t = Self.taillamp(kind)
            let cab = !kind.mazda
            // (Which way along the car is towards the lens: the cars face along x, and the lens is at +z.)
            let towardUs: Float = east ? 1 : -1
            // (Towards the lens from the street, in the car's own frame: up and back towards us, a little along the street.)
            let toLens = simd_normalize(SIMD3<Float>(0.15 * towardUs, 0.36, 0.92 * towardUs))
            func piece(_ geometry: SCNGeometry, _ material: SCNMaterial, _ at: SIMD3<Float>, order: Int = 0) -> SCNNode {
                geometry.firstMaterial = material
                let n = SCNNode(geometry: geometry)
                n.simdPosition = at
                n.categoryBitMask = 4
                n.castsShadow = false
                if order != 0 { n.renderingOrder = order }
                node.addChildNode(n)
                return n
            }
            func dome(_ segments: Int) -> SCNSphere {
                let s = SCNSphere(radius: 1)
                s.segmentCount = segments
                return s
            }
            for side in [Float(-1), 1] {
                // The head lamp: its glass a flattened dome let into the body's corner (only its face stands proud), and
                // the core a little in front of the bowl's middle, under the glass.
                let lens = piece(dome(18), looks.lens, SIMD3(h.x - 0.035, h.y, h.z * side))
                lens.simdScale = cab ? SIMD3(0.055, 0.060, 0.135) : SIMD3(0.060, 0.050, 0.150)
                let core = piece(
                    dome(12), looks.core, SIMD3(h.x + 0.004, h.y + 0.004, h.z * side - side * (cab ? 0.02 : 0.04)))
                core.simdScale = SIMD3(0.024, 0.024, 0.040)
                // The tail lamp: a red lens let into the body.
                let red = piece(dome(14), looks.tail, SIMD3(t.x + 0.03, t.y, t.z * side))
                red.simdScale = cab ? SIMD3(0.045, 0.085, 0.13) : SIMD3(0.045, 0.055, 0.17)
                // The lamp as it is seen from up here, on the lamps of the car's near side: its bright core and a tight
                // bloom that stays at the lamp (`lampPicture`), on a card brought a little towards the lens along the line
                // of sight, so the car's own wing and bumper never cut it. (Seen from seven floors up and across the
                // street, a lamp's glass is nearly edge on: drawn as glass alone the lamps hardly showed.)
                if side == towardUs {
                    let lift = toLens * 0.7
                    let flare = piece(SCNPlane(width: 0.42, height: 0.42), looks.headGlow, h + lift - SIMD3(0.02, 0, 0), order: 2)
                    flare.simdPosition.z = h.z * side + lift.z
                    flare.constraints = [SCNBillboardConstraint()]
                    let ember = piece(SCNPlane(width: 0.30, height: 0.30), looks.tailGlow, t + lift + SIMD3(0.02, 0, 0), order: 2)
                    ember.simdPosition.z = t.z * side + lift.z
                    ember.constraints = [SCNBillboardConstraint()]
                }
                // Each lamp in the wet road: a streak from the foot of the lamp towards us. (Laid by a holder turned so
                // the picture's bright end is at the lamp whichever way the car faces.)
                for (lampAt, look, wide) in [(h, looks.headStreak, Float(0.30)), (t, looks.tailStreak, Float(0.24))] {
                    let length: Float = 5.6
                    let holder = SCNNode()
                    holder.simdEulerAngles = SIMD3(0, east ? 0 : .pi, 0)
                    holder.simdPosition = SIMD3(lampAt.x, 0.035, lampAt.z * side + towardUs * length / 2)
                    let plane = SCNNode(geometry: SCNPlane(width: CGFloat(wide), height: CGFloat(length)))
                    plane.geometry?.firstMaterial = look
                    plane.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
                    plane.renderingOrder = 2
                    plane.categoryBitMask = 4
                    plane.castsShadow = false
                    holder.addChildNode(plane)
                    node.addChildNode(holder)
                }
            }
            // The road lit ahead of it: the dipped beams' soft pool.
            let pool = piece(SCNPlane(width: 8.0, height: 3.0), looks.beam, SIMD3(h.x + 4.6, 0.06, 0), order: 2)
            pool.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            // On a wet road the beams' glare running out ahead (`glarePicture`), and in the air over it the beams
            // themselves, soft, as the rain and the damp show them (`hazePicture`): a wedge from the lamps, laid at the
            // lamps' height and tipped down a little to the road as a dipped beam is.
            let glare = piece(SCNPlane(width: 11.0, height: 2.4), looks.glare, SIMD3(h.x + 6.0, 0.07, 0), order: 2)
            glare.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            let beams = SCNNode()
            beams.simdPosition = SIMD3(h.x + 0.1, h.y - 0.02, 0)
            beams.simdEulerAngles = SIMD3(0, 0, deg(-3.5))
            node.addChildNode(beams)
            let haze = SCNNode(geometry: SCNPlane(width: 9.0, height: 3.2))
            haze.geometry?.firstMaterial = looks.haze
            haze.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
            haze.simdPosition = SIMD3(4.5, 0, 0)
            haze.renderingOrder = 2
            haze.categoryBitMask = 4
            haze.castsShadow = false
            beams.addChildNode(haze)
        }

        private struct LampLooks {
            let core, lens, tail, headGlow, tailGlow, beam, headStreak, tailStreak, haze, glare: SCNMaterial
        }

        /// The two dipped beams in damp air seen from above, the lamps at the left: two soft cones from the lamps' places
        /// that open and merge as they go, brightest near the lamps and fading out; nothing in it has an edge.
        private static func hazePicture() -> CGImage {
            Tex.blur(
                Tex.draw(width: 512, height: 180) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    let lamps: [CGFloat] = [50, 130]
                    for lampY in lamps {
                        for k in 0..<60 {
                            let t = CGFloat(k) / 59
                            let x: CGFloat = 4 + t * 490
                            let half: CGFloat = 4 + 46 * t
                            let fade: CGFloat = pow(1 - t, 1.6)
                            let a: CGFloat = 0.30 * fade * min(t / 0.04, 1)
                            ctx.setFillColor(Tex.gray(1, a))
                            let y: CGFloat = lampY + (90 - lampY) * t * 0.35
                            ctx.fillEllipse(in: CGRect(x: x - 10, y: y - half, width: 20, height: half * 2))
                        }
                    }
                }, radius: 8)
        }

        /// A wet road's glare ahead of a car seen from above, the car at the left: a long soft sheen running out ahead in
        /// the beams' middle, brightest a few metres out, faint at its sides, broken softly by the water's ripples.
        private static func glarePicture() -> CGImage {
            Tex.blur(
                Tex.draw(width: 512, height: 112) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 7311)
                    var x: CGFloat = 0
                    while x < 512 {
                        let step = CGFloat(rng.range(3, 9))
                        let t = x / 512
                        let along = t < 0.18 ? t / 0.18 : pow(max(1 - (t - 0.18) / 0.82, 0), 1.4)
                        let half = 7 + 26 * t
                        ctx.setFillColor(Tex.gray(1, 0.85 * along * CGFloat(rng.range(0.55, 1.0))))
                        ctx.fillEllipse(in: CGRect(x: x, y: 56 - half, width: step * 1.6, height: half * 2))
                        x += step
                    }
                }, radius: 5)
        }

        /// A lamp seen from far off in damp air: a small bright core, a little wider than tall as the glass is, and a tight
        /// bloom round it falling away fast, gone well inside the card.
        private static func bloomPicture() -> CGImage {
            let glow = Tex.draw(width: 128, height: 128) { ctx, rect in
                ctx.setFillColor(Tex.gray(0))
                ctx.fill(rect)
                let g = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [Tex.gray(0.55), Tex.gray(0.26), Tex.gray(0.07), Tex.gray(0.012), Tex.gray(0)] as CFArray,
                    locations: [0, 0.20, 0.40, 0.65, 0.95])!
                ctx.drawRadialGradient(
                    g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64),
                    endRadius: 64, options: [])
            }
            let core = Tex.blur(
                Tex.draw(width: 128, height: 128) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    ctx.setFillColor(Tex.gray(1))
                    ctx.fillEllipse(in: CGRect(x: 64 - 24, y: 64 - 11, width: 48, height: 22))
                }, radius: 4)
            return Tex.draw(width: 128, height: 128) { ctx, rect in
                ctx.draw(glow, in: rect)
                ctx.setBlendMode(.plusLighter)
                ctx.setAlpha(0.6)
                ctx.draw(core, in: rect)
            }
        }

        /// The dipped beams' light on the road, seen from above, the car's nose at the left: two overlapping soft lobes
        /// from a couple of metres out, brightest at a third of their reach, fanning a little and fading. (Blurred:
        /// nothing in it has an edge.) (These pictures are read as sRGB and made linear: drawn at a tenth of white, as
        /// it was, the pool came out at a hundredth and was never seen. They are drawn near full and dimmed by the
        /// material's transparency.)
        private static func beamPicture() -> CGImage {
            Tex.blur(
                Tex.draw(width: 512, height: 168) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    for z in [CGFloat(62), 106] {
                        for k in 0..<36 {
                            let t = CGFloat(k) / 35
                            let x = 30 + t * 440
                            let rise = min(t / 0.30, 1), fall = pow(max(1 - (t - 0.30) / 0.70, 0), 1.4)
                            let a = 0.34 * (t < 0.30 ? rise * rise : fall)
                            let half = 10 + 34 * t
                            ctx.setFillColor(Tex.gray(1, a))
                            ctx.fillEllipse(in: CGRect(x: x - 18, y: z - half, width: 36, height: half * 2))
                        }
                    }
                }, radius: 14)
        }

        /// A lamp in a wet road from above: drawn out towards us (down the picture) from just past the lamp's foot,
        /// brightest a little way out, broken across by the ripples and the road's grain into many short dashes, narrow,
        /// fading as it comes.
        private static func streakPicture() -> CGImage {
            Tex.blur(
                Tex.draw(width: 64, height: 512) { ctx, rect in
                    ctx.setFillColor(Tex.gray(0))
                    ctx.fill(rect)
                    var rng = SeededRandom(seed: 4242)
                    var y: CGFloat = 0
                    while y < 512 {
                        let step = CGFloat(rng.range(2, 6))
                        let u = y / 512
                        let along = u < 0.12 ? u / 0.12 : pow(max(1 - (u - 0.12) / 0.88, 0), 1.3)
                        let width = 7 + 9 * u
                        for _ in 0..<Int(rng.range(1, 3)) {
                            let x = 32 + CGFloat(rng.range(-1, 1)) * width * 0.6
                            let w = CGFloat(rng.range(5, 13)) * (1.1 - 0.4 * u)
                            ctx.setFillColor(Tex.gray(1, along * CGFloat(rng.range(0.25, 0.85))))
                            // (Drawn from the top of the picture, which is the end at the lamp.)
                            ctx.fill(
                                CGRect(
                                    x: x - w / 2, y: 512 - y - step, width: w, height: step * CGFloat(rng.range(0.4, 0.9))))
                        }
                        y += step
                    }
                }, radius: 1.6)
        }

        /// Lights the lamps (0 out, 1 full) and gives the lacquer and glass the hour's street and sky. (`lampDark`: how
        /// dark the street is round the lamps, 0 by day, 1 at night: the beams' pool and the streaks only show on a dark
        /// road.)
        func follow(
            lamps lit: Float, lampDark: Float, sky: SIMD3<Float>, facade: SIMD3<Float>, ground: SIMD3<Float>,
            windows: Float, air: SIMD4<Float>, wet: Float
        ) {
            for m in materials where m.value(forKey: "carSky") != nil {
                m.setValue(NSValue(scnVector3: SCNVector3(sky)), forKey: "carSky")
                m.setValue(NSValue(scnVector3: SCNVector3(facade)), forKey: "carFacade")
                m.setValue(NSValue(scnVector3: SCNVector3(ground)), forKey: "carGround")
                m.setValue(NSNumber(value: windows), forKey: "carWindows")
                m.setValue(NSValue(scnVector4: SCNVector4(air.x, air.y, air.z, air.w)), forKey: "carAir")
            }
            // (A free cab's roof light is on day and night: by day it hardly shows.)
            for m in materials where m.name == "cab sign" { m.emission.intensity = CGFloat(0.25 + 0.65 * lit) }
            if let looks = lampLooks {
                looks.core.emission.intensity = CGFloat(lit > 0.01 ? (0.35 + 0.60 * lit) * Self.coreLevel : 0)
                looks.lens.emission.intensity = CGFloat(0.06 * lit)
                looks.tail.emission.intensity = CGFloat(0.15 + 0.85 * lit)
                looks.headGlow.transparency = CGFloat(Self.glowLevel * lit * (0.85 + 0.15 * min(air.w + wet, 1)))
                looks.tailGlow.transparency = CGFloat(Self.glowLevel * 0.75 * (0.25 + 0.75 * lit))
                // (On a wet road the beams' pool is mostly mirrored away from us: the streaks are what is seen.)
                looks.beam.transparency = CGFloat(lit * lampDark * (0.42 - 0.14 * wet))
                looks.headStreak.transparency = CGFloat(lit * wet * (0.40 + 0.35 * lampDark))
                // (The beams in the air only show against the dark, more in rain and mist; the glare only on a wet road.)
                looks.haze.transparency = CGFloat(lit * lampDark * min(0.08 + 1.6 * air.w + 0.14 * wet, 0.55))
                looks.glare.transparency = CGFloat(lit * wet * (0.22 + 0.40 * lampDark))
                looks.tailStreak.transparency = CGFloat(lit * wet * (0.45 + 0.30 * lampDark))
            }
        }

        /// (`SPINDLE_LAMPCORE=<x>` scales the head lamps' cores, for finding where they would clip.)
        static let coreLevel: Float = ProcessInfo.processInfo.environment["SPINDLE_LAMPCORE"].flatMap { Float($0) } ?? 1
        /// How bright the lamps' cards are (`SPINDLE_LAMPGLOW=<x>` for a test render).
        static let glowLevel: Float = ProcessInfo.processInfo.environment["SPINDLE_LAMPGLOW"].flatMap { Float($0) } ?? 0.9
    }
}
