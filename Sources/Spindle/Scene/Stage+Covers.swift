import AppKit
import SceneKit

extension Stage {
    func sleeveWearLevel(for id: String) -> Double {
        let earned: Double
        if let snapshot = constructionPresentation {
            earned = snapshot.wearLevels[id] ?? 0
        } else {
            earned =
                passivePresentation
                ? (suppliedWearLevels[id] ?? 0) : SleeveWear.level(seconds: Collection.shared.wearSeconds(for: id))
        }
        return max(earned, Stage.handled(id))
    }

    /// Every record on the desk has been taken out and put back before: never factory fresh, whatever has been heard of
    /// it here (2026-10-17: the pile read as pristine flat card in every scene). A little edge wear, the record's ring
    /// coming through and the first grey of handling, different for each album and the same for it every time. The
    /// "Sleeve wear" switch off still shows them as new (`previewWearLevel` is then 0, and this is not asked).
    static func handled(_ id: String) -> Double { 1.3 + 0.7 * Double(stableHash(id + "handled") % 1000) / 1000 }

    /// Each album gets its own pressing: mostly black, sometimes coloured, splattered or marbled.
    func makeRecord(for art: AlbumArt) -> SCNNode {
        let vinyl = pressing(for: art)
        let record = Props.record(label: art.image, vinyl: vinyl, style: Collection.shared.style(for: art.id))
        protectArtwork(record.childNode(withName: "label", recursively: false)?.geometry?.firstMaterial)
        glows(record.childNode(withName: "label", recursively: false)?.geometry?.firstMaterial)
        Stage.fitShadow(of: record, to: vinyl)
        remadeEnvironment?.handling.record?(record)
        return record
    }

    func makeSleeve(for art: AlbumArt) -> SCNNode {
        let sleeve = Props.sleeve(art: sleeveImage(for: art), showsRecord: false)
        for part in sleeve.childNodes { exposePrint(part.geometry?.firstMaterial) }
        configureSleeveMaterial(
            sleeve.childNode(withName: "front", recursively: false)?.geometry?.firstMaterial, art: art)
        return sleeve
    }

    func sleeveImage(for art: AlbumArt) -> CGImage {
        if let previewWearLevel { return SleeveWearRenderer.image(art, level: previewWearLevel) }
        let level = sleeveWearLevel(for: art.id)
        return SleeveWearRenderer.image(art, level: level)
    }

    var artworkLightFactor: CGFloat {
        if let remadeEnvironment { return remadeEnvironment.artworkGain }
        switch preset {
        case .listeningRoom: return 0.82
        case .tatami: return 0.85
        default: return 1
        }
    }

    /// Bright-scene correction is confined to printed art, leaving the room and deck lighting intact.
    func protectArtwork(_ material: SCNMaterial?) {
        // (Asked for again every second with the rest of a sleeve's dressing: anything written to a material has the
        // view draw again, changed or not, so nothing is written that is already there.)
        exposePrint(material)
        guard artworkLightFactor < 1, let material,
            (material.value(forKey: "artGain") as? Double) != Double(artworkLightFactor)
        else { return }
        material.setValue(Double(artworkLightFactor), forKey: "artGain")
        material.multiply.contents = NSColor(white: artworkLightFactor, alpha: 1)
    }

    /// A print's ceiling under white is kept in what this camera shows (`Mat.holdsHighlights`), so it is told the
    /// camera's exposure. (Only written when it differs, like everything asked for again every second.)
    func exposePrint(_ material: SCNMaterial?) {
        let seen = Float(pow(2, cameraNode.camera?.exposureOffset ?? 0))
        guard let material, let was = material.value(forKey: "printExposure") as? NSNumber,
            abs(was.floatValue - seen) > 0.0001
        else { return }
        material.setValue(NSNumber(value: seen), forKey: "printExposure")
    }

    func glows(_ material: SCNMaterial?) {
        guard let material else { return }
        if albumGlow > 0.005 {
            if (material.emission.contents as AnyObject?) !== (material.diffuse.contents as AnyObject?) {
                material.emission.contents = material.diffuse.contents
            }
            if abs(material.emission.intensity - albumGlow) > 0.0005 { material.emission.intensity = albumGlow }
        } else if material.emission.intensity > 0 {
            material.emission.intensity = 0
            material.emission.contents = NSColor.black
        }
    }

    func setAlbumGlow(_ glow: CGFloat) {
        guard abs(glow - albumGlow) > 0.004 || (glow == 0) != (albumGlow == 0) else { return }
        albumGlow = glow
        for entry in entries {
            glows(entry.node.childNode(withName: "front", recursively: false)?.geometry?.firstMaterial)
        }
        glows(recordNode?.childNode(withName: "label", recursively: false)?.geometry?.firstMaterial)
    }

    func configureSleeveMaterial(_ material: SCNMaterial?, art: AlbumArt) {
        protectArtwork(material)
        glows(material)
        let level = previewWearLevel ?? sleeveWearLevel(for: art.id)
        let amount = min(max(level / 4, 0), 1)
        guard let material, (material.value(forKey: "wearLaid") as? Double) != amount else { return }
        material.setValue(amount, forKey: "wearLaid")
        material.normal.contents = Resources.url("textures/paper_001_normalgl.jpg")
        material.normal.intensity = CGFloat(0.30 + amount * 0.45) * (remadeEnvironment?.sleeveGrain ?? 1)
        // (Printed card is matte: at 0.62 a sleeve lying flat took the lamp as a waxy wash over its whole face, and its
        // dark ink went to a brown glare. Matte with its fibre and a little smoother where it is handled: `Props.cardSheen`,
        // with most of the lamps' sheen taken off it, `printMatte`.)
        material.roughness.contents = Props.cardSheen()
    }

    /// Hosts supply preferences. Saver hosts supply their snapshot and never consult listening stats.
    func setPersonalPresentation(wearLevel: Double? = nil, albumID: String? = nil, wearPreviewLevel: Double? = nil) {
        let preferenceChanged = previewWearLevel != wearPreviewLevel
        previewWearLevel = wearPreviewLevel
        if let wearLevel, let id = albumID ?? currentAlbumID { suppliedWearLevels[id] = wearLevel }
        refreshPersonalPresentation(forceWear: preferenceChanged)
    }

    func refreshPersonalPresentation(forceWear: Bool = false) {
        let settled = phase == .idle && requests.isEmpty
        if settled || forceWear {
            var sleeves = entries
            if let incoming, !sleeves.contains(where: { $0 === incoming }) { sleeves.append(incoming) }
            var changedWear = false
            for entry in sleeves {
                curl(entry)
                let image = sleeveImage(for: entry.art)
                let material = entry.node.childNode(withName: "front", recursively: false)?.geometry?.firstMaterial
                configureSleeveMaterial(material, art: entry.art)
                if (material?.diffuse.contents as AnyObject?) !== (image as AnyObject) {
                    material?.diffuse.contents = image
                    changedWear = true
                }
            }
            if changedWear || forceWear { markAnimating(for: 0.3) }
        }
    }

    /// A record you can nearly see straight through throws next to no shadow.
    static func fitShadow(of record: SCNNode, to vinyl: SCNMaterial) {
        let solid = ((vinyl.value(forKey: "fade") as? NSNumber)?.floatValue ?? 1) >= 0.4
        record.childNodes.first(where: { $0.name == "disc" })?.castsShadow = solid
    }

    /// Vinyl in whichever style the collection says this album's record should be.
    func pressing(for art: AlbumArt) -> SCNMaterial {
        let look = VinylLook.make(Collection.shared.style(for: art.id), art: art)
        let material = Mat.vinyl(look: look)
        Mat.copySheen(from: vinyl, to: material)
        if look.cycles {
            shifting.append(material)
            if shifting.count > 3 { shifting.removeFirst() }
        }
        return material
    }

    /// The listener picked another style: the record that is out is re-pressed where it is.
    /// Only its vinyl is exchanged, inside the record itself, so this works just as well while
    /// the record is in flight between sleeve and platter as when it is sitting still: the new
    /// vinyl comes up slowly through the old, which stays as it is underneath until it is
    /// completely covered and only then is taken away. Nothing moves.
    func restyleRecord() {
        guard let record = recordNode, let art = (held ?? incoming ?? entries.last)?.art ?? sleevelessArt,
            let old = record.childNodes.first(where: { $0.name == "disc" })
        else { return }
        protectArtwork(record.childNode(withName: "label", recursively: false)?.geometry?.firstMaterial)
        let vinyl = pressing(for: art)
        lock.lock()
        let spinning = playing
        lock.unlock()
        let time: TimeInterval = spinning ? 2.4 : 1.5
        let lift: Float = 0.0003
        let top = Dim.recordThickness
        let fresh = Props.recordDisc(vinyl: vinyl)
        record.childNode(withName: "deadwax", recursively: false)?.removeFromParentNode()
        let deadwax = RecordDeadwax.node(style: Collection.shared.style(for: art.id))
        record.addChildNode(deadwax)
        // A hair proud of the old vinyl all round, so the two never fight for the same surface;
        // the label rides up with it for the duration, or it would be buried.
        fresh.simdPosition.y = lift
        fresh.simdScale = SIMD3(1.0008, 1, 1.0008)
        fresh.opacity = 0
        fresh.castsShadow = false
        record.insertChildNode(fresh, at: 0)
        let label = record.childNode(withName: "label", recursively: false)
        let hole = record.childNode(withName: "hole", recursively: false)
        label?.simdPosition.y = top + 0.00015 + lift
        deadwax.simdPosition.y = top + 0.00022 + lift
        hole?.simdPosition.y = top + 0.0003 + lift
        restyles += 1
        let token = restyles
        let appear = SCNAction.fadeIn(duration: time)
        appear.timingMode = .easeInEaseOut
        fresh.runAction(
            .sequence([
                appear, .wait(duration: 0.05),
                .run { [weak self] node in
                    // (If the listener has changed their mind again meanwhile, the later change does the tidying.)
                    guard let self, self.restyles == token else { return }
                    for other in record.childNodes where other.name == "disc" && other !== node {
                        other.removeFromParentNode()
                    }
                    node.simdPosition.y = 0
                    node.simdScale = SIMD3(1, 1, 1)
                    label?.simdPosition.y = top + 0.00015
                    deadwax.simdPosition.y = top + 0.00022
                    hole?.simdPosition.y = top + 0.0003
                    Stage.fitShadow(of: record, to: vinyl)
                },
            ]))
        let solid = ((vinyl.value(forKey: "fade") as? NSNumber)?.floatValue ?? 1) >= 0.999
        if !solid {
            // (A see-through pressing: the old vinyl has to thin out as the new one arrives.)
            let leave = SCNAction.fadeOut(duration: time)
            leave.timingMode = .easeInEaseOut
            for other in record.childNodes where other.name == "disc" && other !== fresh { other.runAction(leave) }
        }
        _ = old
        markAnimating(for: time + 1.0)
    }

    /// Same album, better image (the full-size cover arriving after the quick one).
    func refreshArtwork(_ art: AlbumArt) {
        // Swapping a large texture mid-animation costs a frame or two; wait until things settle.
        if phase != .idle {
            deferredArtwork = art
            return
        }
        guard let entry = held, entry.art.id == art.id, entry.art.image !== art.image else { return }
        entry.art = art
        refreshSleeveArtwork(entry, art: art)
        refreshRecordLabel(art.image)
        markAnimating(for: 0.3)
    }

    func refreshSleeveArtwork(_ entry: Entry, art: AlbumArt) {
        let material = entry.node.childNode(withName: "front", recursively: false)?.geometry?.firstMaterial
        material?.diffuse.contents = sleeveImage(for: art)
        configureSleeveMaterial(material, art: art)
    }

    func refreshRecordLabel(_ image: CGImage) {
        let material = recordNode?.childNode(withName: "label", recursively: false)?.geometry?.firstMaterial
        material?.diffuse.contents = image
        protectArtwork(material)
    }
}
