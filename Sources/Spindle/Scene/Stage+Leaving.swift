import AppKit
import SceneKit

/// What a stage leaves behind when it goes, and what is kept for the stages still here.
///
/// Every stage is given a number as it begins to be built (`Keeping.open`), counting up, and every picture or model
/// a cache hands out is stamped with the number of the newest stage begun by then. When a stage goes
/// (`Keeping.close`, from its `deinit`), whatever the caches hold that is stamped older than every stage still here
/// is let go of: no stage still here asked for it, so none is drawing it. (The caches had kept the pictures and models
/// of every scene visited, up to 640 MB of pictures and every model, and their textures with them.)
///
/// And the stage's own materials are emptied: SceneKit keeps every material that has a shader modifier for good once
/// it has drawn it (its Metal resource manager's `_availableShadables` holds the material strongly), and with it every
/// picture the material holds, as a texture. Emptied, what is kept is a husk of a few kilobytes. Only materials no
/// other stage can be drawing are emptied: those the stage made for itself, never a model's that is still kept
/// (`ModelLibrary`) or the contact shades' one material that every stage shares.
enum Keeping {
    /// (`SPINDLE_KEEP_EVERYTHING=1`: nothing is let go of and no picture is settled, as before 2026-10-19, for
    /// measuring what this saves.)
    static let everything = ProcessInfo.processInfo.environment["SPINDLE_KEEP_EVERYTHING"] != nil
    private static let lock = NSLock()
    private static var newest = 0
    /// The numbers of the stages still here, and the scene of each.
    private static var live: [Int: ScenePreset?] = [:]

    /// The number for a stage that is beginning to be built.
    static func open() -> Int {
        lock.lock()
        defer { lock.unlock() }
        newest += 1
        live[newest] = .some(nil)
        return newest
    }

    /// Which scene the stage of that number is (said once it is known).
    static func note(_ era: Int, is preset: ScenePreset) {
        lock.lock()
        if live[era] != nil { live[era] = preset }
        lock.unlock()
    }

    /// The number to stamp on whatever is handed out now.
    static var now: Int {
        lock.lock()
        defer { lock.unlock() }
        return newest
    }

    /// A stage has gone: what only it, or stages gone before it, asked for is let go of.
    static func close(_ era: Int, leaving root: SCNNode, lights: [SCNLight]) {
        lock.lock()
        let preset = live.removeValue(forKey: era) ?? nil
        let oldest = live.keys.min() ?? newest + 1
        let last = preset.map { gone in !live.values.contains { $0 == gone } } ?? false
        lock.unlock()
        guard !everything else { return }
        // (What a scene keeps for its own `tick` from the last one built, once there is none of it left.)
        if last, let preset { forgetLeftovers(of: preset) }
        Mat.forget(before: oldest)
        let models = ModelLibrary.forget(before: oldest)
        SleeveWearRenderer.forget(before: oldest)
        let kept = ModelLibrary.keptMaterials()
        empty(root, lights: lights, sparing: kept)
        // (And the materials of the models let go of: SceneKit keeps those too, if they have been drawn.)
        let shared = ObjectIdentifier(ContactShade.material)
        var seen = Set<ObjectIdentifier>()
        for material in models {
            let id = ObjectIdentifier(material)
            guard id != shared, !kept.contains(id), seen.insert(id).inserted else { continue }
            empty(material)
        }
        // (What Core Image kept of the pictures it was asked to make: made again if it is wanted again.)
        Tex.ciContext.clearCaches()
    }

    private static func forgetLeftovers(of preset: ScenePreset) {
        switch preset {
        case .rainyNewYork: CourtyardScene.forgetLeftovers()
        default: break
        }
    }

    /// Empties the materials under `root` (and the lights' gobos), all but those spared.
    private static func empty(_ root: SCNNode, lights: [SCNLight], sparing kept: Set<ObjectIdentifier>) {
        var seen = Set<ObjectIdentifier>()
        let shared = ObjectIdentifier(ContactShade.material)
        root.enumerateHierarchy { node, _ in
            for material in (node.geometry?.materials ?? []) + ScenePieces.materials(welded: node) {
                let id = ObjectIdentifier(material)
                guard id != shared, !kept.contains(id), seen.insert(id).inserted else { continue }
                empty(material)
            }
        }
        for light in lights { light.gobo?.contents = nil }
    }

    private static let named = try! NSRegularExpression(pattern: "texture2d<float>\\s+(\\w+)\\s*;")

    private static func empty(_ m: SCNMaterial) {
        for property in properties(of: m) where property.contents != nil { property.contents = nil }
    }

    /// Everything of a material's that can hold a picture: its own properties, and those handed to its shader
    /// modifiers by name.
    static func properties(of m: SCNMaterial) -> [SCNMaterialProperty] {
        var list = [
            m.diffuse, m.normal, m.roughness, m.metalness, m.ambientOcclusion, m.emission, m.multiply, m.transparent,
            m.specular, m.reflective, m.selfIllumination, m.displacement, m.clearCoat, m.clearCoatRoughness,
            m.clearCoatNormal, m.ambient,
        ]
        guard let modifiers = m.shaderModifiers else { return list }
        let text = modifiers.values.joined(separator: "\n")
        for match in named.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text),
                let property = m.value(forKey: String(text[range])) as? SCNMaterialProperty
            else { continue }
            list.append(property)
        }
        return list
    }
}

extension Stage {
    /// Moves the drawn pictures the stage's materials and lights hold out of the app's memory (`Tex.settled`), once it
    /// is built and before any of it is drawn: the same pictures, to the last bit. (Those the caches keep are settled
    /// as they are made.)
    func settlePictures(all: Bool = false) {
        guard Tex.settles else { return }
        let kept = all ? [] : Mat.keptPictures().union(SleeveWearRenderer.keptPictures())
        var twins: [ObjectIdentifier: CGImage] = [:]
        func settle(_ property: SCNMaterialProperty) {
            guard let contents = property.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return }
            let image = contents as! CGImage
            let id = ObjectIdentifier(image)
            if let twin = twins[id] {
                if twin !== image { property.contents = twin }
                return
            }
            let twin = kept.contains(id) ? image : Tex.settled(image)
            twins[id] = twin
            if twin !== image { property.contents = twin }
        }
        var seen = Set<ObjectIdentifier>()
        scene.rootNode.enumerateHierarchy { node, _ in
            for material in (node.geometry?.materials ?? []) + ScenePieces.materials(welded: node)
            where seen.insert(ObjectIdentifier(material)).inserted {
                Keeping.properties(of: material).forEach(settle)
            }
            if let gobo = node.light?.gobo { settle(gobo) }
        }
    }

    /// The lights of the stage (for their gobos, which are pictures too).
    var allLights: [SCNLight] {
        var lights: [SCNLight] = []
        scene.rootNode.enumerateHierarchy { node, _ in if let light = node.light { lights.append(light) } }
        return lights
    }
}
