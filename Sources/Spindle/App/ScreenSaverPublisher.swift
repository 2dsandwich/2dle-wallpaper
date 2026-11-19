import Foundation

/// Keeps playback and scene preferences available while the desktop is covered.
final class ScreenSaverPublisher {
    private var timer: Timer?
    private var artworkID: String?
    private var madeDirectory = false

    func start(model: NowPlaying, settings: Settings) {
        publish(model: model, settings: settings)
        // (The saver takes the music to have stopped when what it reads is five seconds old: every other second is often enough.)
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.publish(model: model, settings: settings)
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func publish(model: NowPlaying, settings: Settings) {
        do {
            if !madeDirectory {
                try FileManager.default.createDirectory(
                    at: ScreenSaverState.directory, withIntermediateDirectories: true)
                madeDirectory = true
            }
            if artworkID != model.art.id {
                if writeJPEG(model.art.image, to: ScreenSaverState.artworkURL) { artworkID = model.art.id }
            }
            let playback = model.playback
            let state = ScreenSaverState(
                timestamp: Date().timeIntervalSince1970, scene: settings.scene.rawValue,
                turntable: settings.turntable.rawValue,
                clock: settings.clockEnabled ? settings.clockStyle.rawValue : nil,
                artworkID: artworkID ?? "builtin", isPlaying: playback.isPlaying,
                position: playback.currentPosition, duration: playback.duration,
                lowerBand: playback.band.lowerBound, upperBand: playback.band.upperBound,
                bpm: playback.bpm, album: playback.album, disc: playback.disc,
                recordStyle: Collection.shared.style(for: model.art.id).rawValue,
                unlocked: Collection.shared.unlocked.map(\.rawValue),
                unlockLabels: Dictionary(
                    uniqueKeysWithValues: RecordStyle.allCases.map {
                        ($0.rawValue, Collection.shared.deadwaxUnlockLabel(for: $0))
                    }),
                wearLevel: settings.sleeveWearShown
                    ?? SleeveWear.level(seconds: Collection.shared.wearSeconds(for: model.art.id)))
            try JSONEncoder().encode(state).write(to: ScreenSaverState.url, options: .atomic)
        } catch {
            NSLog("2dle: screen saver state unavailable: \(error.localizedDescription)")
        }
    }

    deinit { timer?.invalidate() }
}
