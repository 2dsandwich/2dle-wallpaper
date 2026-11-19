import AppKit
import simd

/// The hour of the day, for the scenes that are lit by daylight. Each of those was lit by hand
/// for one moment (the Alps at sunset, the tatami room in the morning); with an hour given, the
/// sun leaves that moment and stands where the hour puts it: low and orange at either end of the
/// day, high and nearly white in the middle, round to one side in the morning and the other in
/// the evening. After dark the same light is the moon's: a tenth as strong, and blue.
///
/// Everything is worked out relative to the moment the scene was lit for, so that at that hour
/// the scene is exactly as it was made.
enum Daylight {
    /// The hour (0 to 24) to light the daylight scenes by. `nil` leaves every scene as it was lit by hand.
    static var hour: Double?
    /// Roughly where the Mac is, in degrees, for whoever has asked for the scenes to keep their own days (see
    /// `LocalWeather`). Nil for everybody else. (`SPINDLE_PLACE=59.9,10.7` sets it, for test renders.)
    static var place: (latitude: Double, longitude: Double)? = ProcessInfo.processInfo.environment["SPINDLE_PLACE"]
        .flatMap { said in
            let parts = said.split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }

    /// How a scene's daylight is to be changed for an hour.
    struct State {
        /// How far along its arc the light has moved from where the scene has it (in days: sunrise to sunset is 1).
        var along: Float
        /// How much higher (+) or lower it stands, as a difference of sines of the height of the sun.
        var higher: Float
        /// Its strength, as a multiple of what the scene has.
        var strength: Float
        /// Its colour at this hour, and how far to go over to it from the scene's own (0 at the scene's hour).
        var colour: SIMD3<Float>
        var turn: Float
        /// The light of the sky itself, as a multiple of what the scene has.
        var sky: Float
        /// What is seen out of doors in a photograph is multiplied by this.
        var outdoors: SIMD3<Float>
        var night: Bool
        /// How far the stars are out (0 by day and through the dusk).
        var stars: Float = 0
        /// How much of full daylight there is, whatever the scene was lit for (0 at night, 1 in the middle of the day).
        var day: Float = 0
        /// How far it is dark enough to want the lamps on (0 in daylight, 1 from dusk to dawn).
        var gloom: Float = 1
    }

    /// Sunrise and sunset by the clock, for the time of year: about nine and a half hours of day at midwinter and
    /// fourteen and a half at midsummer, as at the latitude of Tokyo or San Francisco. (Without knowing where
    /// the Mac is, this is as near as it can be said. Knowing it, they are the place's own: see `place`.)
    static func day(on date: Date = Date()) -> (rise: Double, set: Double) {
        let ordinal = Double(Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 172)
        if let place {
            // How far the sun stands from the equator today, and so how long it is up at this latitude. (Never quite all
            // day or none of it: the far north keeps an hour of night in summer and an hour of day in winter, to light by.)
            let lean = -23.44 * cos(2 * .pi * (ordinal + 10) / 365) * .pi / 180
            let half = acos(min(max(-tan(place.latitude * .pi / 180) * tan(lean), -1), 1)) * 12 / .pi
            let length = min(max(2 * half, 1), 23)
            // When it is highest by the clock: twelve, put right for how far this is from the middle of its time zone
            // and for the sun running a little fast or slow with the time of year.
            let turn = 2 * .pi * (ordinal - 81) / 364
            let early = 9.87 * sin(2 * turn) - 7.53 * cos(turn) - 1.5 * sin(turn)
            let noon =
                12 + (Double(TimeZone.current.secondsFromGMT(for: date)) / 3600 * 15 - place.longitude) / 15 - early
                / 60
            return (noon - length / 2, noon + length / 2)
        }
        let length = 12 + 2.5 * sin(2 * .pi * (ordinal - 80) / 365)
        return (12 - length / 2, 12 + length / 2)
    }

    /// The hour a scene was lit for, given the moment as a fraction of the day.
    static func hour(of design: Float, on date: Date = Date()) -> Double {
        let (rise, set) = day(on: date)
        if design <= 1 { return rise + Double(design) * (set - rise) }
        return set + Double(design - 1) * (24 - (set - rise))
    }

    /// How much of a low sun's shaft there is at an hour (the one shown, or else the hour a scene was lit for): rising
    /// through the last three hours before sunset to all of it in the last hour, gone within twenty minutes of sunset;
    /// and the same, shorter, after sunrise. For a scene's own raking light at the end of the day, which its daylight
    /// sun, weakening as it sets, does not give.
    static func lowSun(at hour: Double? = Daylight.hour, design: Float) -> Float {
        let h = Float(hour ?? Daylight.hour(of: design))
        let (rise, set) = day()
        let evening = smoothstep(Float(set) - 3.2, Float(set) - 1.0, h) * (1 - smoothstep(Float(set) - 0.1, Float(set) + 0.35, h))
        let morning = smoothstep(Float(rise) - 0.2, Float(rise) + 0.3, h) * (1 - smoothstep(Float(rise) + 1.0, Float(rise) + 2.6, h))
        return max(evening, morning)
    }

    /// How much of each of four looks a view out of doors takes at a moment (counted from sunrise: 0 to 1 the day, 1 to
    /// 2 the night). By day the evening's colours only while the sun is low (its height from `low.from` up to `low.to`,
    /// at either end of the day); by night the afterglow for a while after sunset (and before sunrise), the dusk, then
    /// the night.
    static func looks(at moment: Float, low: (from: Float, to: Float)) -> (
        day: Float, gold: Float, dusk: Float, night: Float
    ) {
        var w = (day: Float(0), gold: Float(0), dusk: Float(0), night: Float(0))
        if moment < 1 {
            let height = sin(.pi * moment)
            let low = 1 - smoothstep(low.from, low.to, height)
            w.gold = low
            w.day = 1 - low
        } else {
            let n = moment - 1
            let edge = min(n, 1 - n)
            let afterglow = 1 - smoothstep(0.0, 0.03, edge)
            let deep = smoothstep(0.03, 0.10, edge)
            w.gold = afterglow
            w.night = deep
            w.dusk = max(1 - afterglow - deep, 0)
        }
        return w
    }

    /// The strength of the sun at a height (the sine of it), and of the sky.
    private static func sunStrength(_ height: Float) -> Float {
        smoothstep(0, 0.13, height) * (0.5 + 0.5 * pow(max(height, 0), 0.6))
    }
    private static func skyStrength(_ height: Float) -> Float { 0.34 + 0.66 * smoothstep(0, 0.42, height) }

    /// The sun, the moon and the sky at one moment. Moments are counted from sunrise: 0 to 1 is the day, 1 to 2 the night.
    private static func sample(_ moment: Float) -> (
        along: Float, height: Float, sun: Float, colour: SIMD3<Float>, sky: Float, outdoors: SIMD3<Float>, night: Bool
    ) {
        let dusk = SIMD3<Float>(0.46, 0.50, 0.66)
        if moment < 1 {
            let height = sin(.pi * moment)
            let low = SIMD3<Float>(1.0, 0.50, 0.24)
            let high = SIMD3<Float>(1.0, 0.95, 0.86)
            let sky = skyStrength(height)
            // (Out of doors at dusk and dawn what there is to see dims with the sky, and goes a little blue.)
            return (
                moment, height, sunStrength(height), low + (high - low) * smoothstep(0.04, 0.62, height), sky,
                dusk + (SIMD3<Float>(1, 1, 1) - dusk) * smoothstep(0.34, 0.80, sky), false
            )
        }
        // Night: the moon keeps the sun's road, lower, from the one side to the other.
        let n = moment - 1
        let height = 0.7 * sin(.pi * n)
        // (The last of the dusk goes in the first twentieth of the night, and the dawn comes in the last.)
        let twilight = 1 - smoothstep(0, 0.06, min(n, 1 - n))
        let dark = SIMD3<Float>(0.10, 0.14, 0.27)
        return (
            n, height, 0.10 * smoothstep(0, 0.16, height), SIMD3<Float>(0.52, 0.64, 1.0), 0.15 + 0.19 * twilight,
            dark + (dusk - dark) * twilight, true
        )
    }

    /// The moment an hour of the clock is, counted as `sample` counts.
    static func moment(at hour: Double, on date: Date = Date()) -> Float {
        let (rise, set) = day(on: date)
        let clock = hour - 24 * (hour / 24).rounded(.down)
        if clock >= rise, clock <= set { return Float((clock - rise) / (set - rise)) }
        let gone = clock > set ? clock - set : clock + 24 - set
        return 1 + Float(gone / (24 - (set - rise)))
    }

    /// `design` is the moment the scene was lit for: 0 at sunrise, 1 at sunset, on towards 2 through the night.
    static func state(at hour: Double, design: Float, on date: Date = Date()) -> State {
        let now = sample(min(moment(at: hour, on: date), 1.9999))
        let made = sample(design)
        let same = now.night == made.night
        // (Close to its own hour a scene keeps its own colours, and what is out of doors is as it was photographed.)
        let near = same ? 1 - smoothstep(0.03, 0.22, abs(now.along - made.along)) : 0
        let seen = SIMD3<Float>(
            min(now.outdoors.x / made.outdoors.x, 1), min(now.outdoors.y / made.outdoors.y, 1),
            min(now.outdoors.z / made.outdoors.z, 1))
        let n = now.along
        return State(
            along: now.along - made.along, higher: now.height - made.height, strength: now.sun / max(made.sun, 0.03),
            colour: now.colour, turn: 1 - near, sky: now.sky / made.sky,
            outdoors: seen + (SIMD3<Float>(1, 1, 1) - seen) * near * (now.night ? 1 : smoothstep(0, 0.2, now.height)),
            night: now.night,
            stars: now.night ? smoothstep(0.015, 0.09, min(n, 1 - n)) : 0,
            day: smoothstep(0.34, 0.95, now.sky), gloom: now.night ? 1 : 1 - smoothstep(0.30, 0.40, now.height))
    }
}

/// The weather out of doors, for the scenes that look out on it: where the Mac is, for whoever has asked for the
/// scenes to copy it (see `LocalWeather`), or one set by hand from the developer tools.
enum Outdoors {
    enum Sky: String, CaseIterable { case clear, cloudy, fog, drizzle, rain, snow, storm }

    /// The weather to show: nil when nobody has asked, and every scene keeps the weather it was made with.
    /// (`SPINDLE_SKY=rain` (or any other of them) sets it, for test renders; `SPINDLE_RAIN=1` or `0` is rain or clear.)
    static var sky: Sky? = {
        let env = ProcessInfo.processInfo.environment
        return env["SPINDLE_SKY"].flatMap(Sky.init(rawValue:)) ?? env["SPINDLE_RAIN"].map { $0 != "0" ? .rain : .clear }
    }()
    /// Whether rain is falling in it (nil when nobody has asked).
    static var raining: Bool? { sky.map { $0 == .drizzle || $0 == .rain || $0 == .storm } }

    /// How bright a flash of lightning is `t` seconds after it began: two strokes close together, the second the
    /// brighter, and a flicker dying away after it.
    static func flash(after t: Float) -> Float {
        if t < 0.07 { return 0.7 }
        if t < 0.13 { return 0.08 }
        if t < 0.22 { return 1 }
        if t < 0.9 { return exp(-(t - 0.22) / 0.14) * (0.75 + 0.25 * sin(t * 70)) }
        return 0
    }

    /// What a weather is made of, each as much of it as there is: rain and snow falling, cloud over the sun, fog,
    /// the ground wet, snow lying, and a storm in it. A scene is handed these as the weather comes and goes, and
    /// shows what it can of each.
    struct Weather: Equatable {
        var rain: Float = 0, snow: Float = 0, cloud: Float = 0, fog: Float = 0, wet: Float = 0, cover: Float = 0,
            storm: Float = 0

        init() {}
        init(_ sky: Sky) {
            switch sky {
            case .clear: break
            case .cloudy: cloud = 0.6
            case .fog:
                cloud = 0.5
                fog = 1
            case .drizzle:
                rain = 0.28
                cloud = 0.75
                wet = 0.5
            case .rain:
                rain = 1
                cloud = 1
                wet = 1
            case .storm:
                rain = 1.8
                cloud = 1.25
                wet = 1
                storm = 1
            case .snow:
                snow = 1
                cloud = 0.8
                cover = 1
            }
        }
        /// Part of the way from this weather to another.
        func towards(_ other: Weather, _ t: Float) -> Weather {
            var mixed = Weather()
            mixed.rain = rain + (other.rain - rain) * t
            mixed.snow = snow + (other.snow - snow) * t
            mixed.cloud = cloud + (other.cloud - cloud) * t
            mixed.fog = fog + (other.fog - fog) * t
            mixed.wet = wet + (other.wet - wet) * t
            mixed.cover = cover + (other.cover - cover) * t
            mixed.storm = storm + (other.storm - storm) * t
            return mixed
        }
        /// Something is falling, or flashing: the scene has to be redrawn to show it.
        var moving: Bool { rain > 0.004 || snow > 0.004 || storm > 0.004 }
    }
}
