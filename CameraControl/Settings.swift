import CoreGraphics
import Foundation

/// Output canvas size. Everything is composed at this resolution.
let canvasSize = CGSize(width: 1280, height: 720)
let canvasRect = CGRect(origin: .zero, size: canvasSize)

struct RGB: Codable, Equatable {
    var r: Double, g: Double, b: Double
}

enum BackgroundMode: String, Codable, CaseIterable, Identifiable {
    case none, blur, preset, color, custom, screen
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Off"
        case .blur: "Blur"
        case .preset: "Scene"
        case .color: "Color"
        case .custom: "Image"
        case .screen: "Screen"
        }
    }
}

enum BackgroundPreset: String, Codable, CaseIterable, Identifiable {
    case newsStudio, weather, snow, matrix, clouds, aquarium, city, sunset, space, beach, synthwave, greenScreen
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newsStudio: "News Studio"
        case .weather: "Weather Map"
        case .snow: "Snowfall"
        case .matrix: "Code Rain"
        case .clouds: "Sky"
        case .aquarium: "Aquarium"
        case .city: "Night City"
        case .sunset: "Sunset"
        case .space: "Outer Space"
        case .beach: "Beach"
        case .synthwave: "Synthwave"
        case .greenScreen: "Green Screen"
        }
    }
    /// Animated scenes are redrawn every frame by `AnimatedScenes`.
    var isAnimated: Bool { [.weather, .snow, .matrix, .clouds, .aquarium].contains(self) }
}

/// Effects that treat you and your background differently (need person segmentation).
enum PersonEffect: String, Codable, CaseIterable, Identifiable {
    case none, colorPop, neonOutline, clones, ghostTrail
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "None"
        case .colorPop: "Color Pop"
        case .neonOutline: "Neon Outline"
        case .clones: "Clones"
        case .ghostTrail: "Ghost Trail"
        }
    }
}

enum WitnessMode: String, Codable, CaseIterable, Identifiable {
    case off, pixelate, eyeBar
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .pixelate: "Pixelate"
        case .eyeBar: "Eye Bar"
        }
    }
}

/// How the video animates when it's switched off or swapped for a card, and back.
enum OffStyle: String, Codable, CaseIterable, Identifiable {
    case tvOff, glitch, pixels, iris, spin, fade
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tvOff: "Old TV"
        case .glitch: "Glitch"
        case .pixels: "Pixels"
        case .iris: "Iris"
        case .spin: "Spin"
        case .fade: "Fade"
        }
    }
}

enum FilterKind: String, Codable, CaseIterable, Identifiable {
    case none, mono, noir, sepia, comic, thermal, xray, invert, pixelate, posterize,
         crystallize, kaleidoscope, bloom, vhs, edges, twirl, bulge, pinch,
         oldFilm, glitch, ascii, halftone
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "None"
        case .mono: "Mono"
        case .noir: "Noir"
        case .sepia: "Sepia"
        case .comic: "Comic"
        case .thermal: "Thermal"
        case .xray: "X-Ray"
        case .invert: "Invert"
        case .pixelate: "Pixelate"
        case .posterize: "Pop Art"
        case .crystallize: "Crystal"
        case .kaleidoscope: "Kaleido"
        case .bloom: "Dreamy"
        case .vhs: "VHS"
        case .edges: "Neon Edges"
        case .twirl: "Twirl"
        case .bulge: "Big Head"
        case .pinch: "Pinch"
        case .oldFilm: "Old Film"
        case .glitch: "Glitch"
        case .ascii: "ASCII"
        case .halftone: "Halftone"
        }
    }
    /// Distortions are centered on the first detected face.
    var isDistortion: Bool { self == .twirl || self == .bulge || self == .pinch }
}

enum Sticker: String, Codable, CaseIterable, Identifiable {
    case none, sunglasses, topHat, crown, clownNose, frog, robot, alien, skull, cat
    var id: String { rawValue }

    enum Placement { case eyes, hat, nose, face }

    var emoji: String {
        switch self {
        case .none: ""
        case .sunglasses: "🕶️"
        case .topHat: "🎩"
        case .crown: "👑"
        case .clownNose: "🔴"
        case .frog: "🐸"
        case .robot: "🤖"
        case .alien: "👽"
        case .skull: "💀"
        case .cat: "🐱"
        }
    }

    var placement: Placement {
        switch self {
        case .sunglasses: .eyes
        case .topHat, .crown: .hat
        case .clownNose: .nose
        default: .face
        }
    }
}

enum CaptionPosition: String, Codable, CaseIterable, Identifiable {
    case top, bottom
    var id: String { rawValue }
}

enum Reaction: String, CaseIterable, Identifiable {
    case confetti, hearts, laugh, fire, thumbsUp, clap, balloons
    var id: String { rawValue }

    var emojis: [String] {
        switch self {
        case .confetti: ["🎉", "🎊", "✨", "🥳", "⭐️"]
        case .hearts: ["❤️", "💖", "💕", "😍"]
        case .laugh: ["😂", "🤣", "😆"]
        case .fire: ["🔥", "💥", "🔥"]
        case .thumbsUp: ["👍", "👍🏻", "👌"]
        case .clap: ["👏", "🙌"]
        case .balloons: ["🎈", "🎈", "🎈", "🎁"]
        }
    }

    /// Confetti rains from the top; everything else floats up from the bottom.
    var fallsDown: Bool { self == .confetti }
}

struct EffectSettings: Codable, Equatable {
    // Camera
    var mirror = true
    var zoom = 1.0
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0

    // Look
    var filter = FilterKind.none
    var filterIntensity = 0.6

    // Background
    var backgroundMode = BackgroundMode.none
    var backgroundPreset = BackgroundPreset.newsStudio
    var blurRadius = 18.0
    var backgroundColor = RGB(r: 0.15, g: 0.55, b: 0.35)

    var presenterSmall = true

    // You
    var personEffect = PersonEffect.none
    var laserEyes = false
    var witness = WitnessMode.off
    var autoFrame = false

    // Fun
    var sticker = Sticker.none

    // News anchor
    var newsEnabled = false
    var newsTag = "BREAKING NEWS"
    var newsName = "Bennett Atwood"
    var newsTitle = "Live from the home office"
    var tickerEnabled = true
    var tickerText = "Local man turns webcam into a TV studio • Coffee levels reported at record highs • Meeting could have been an email, sources say"
    var channelName = "CAM NEWS 24"
    var showLiveBug = true

    // Caption
    var captionEnabled = false
    var captionText = "Hello! 👋"
    var captionPosition = CaptionPosition.bottom

    // Stop / hold
    var freeze = false
    var blank = false
    var blankTitle = "Be right back"
    var blankSubtitle = "Grabbing a coffee ☕️"
    var cameraOff = false
    var offStyle = OffStyle.tvOff

    // Starting soon
    var startingSoon = false
    var countdownMinutes = 5
    var startingSoonTitle = "Starting soon"
    var startingSoonSubtitle = "Grab a snack, we'll be live shortly 🍿"

    /// True when a card (camera off, be right back, starting soon) replaces the video.
    var showsCard: Bool { cameraOff || blank || startingSoon }

    static let defaultsKey = "effectSettings.v1"

    static func load() -> EffectSettings {
        // Merge saved values over the defaults so settings added in later versions
        // don't make older saved data fail to decode.
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(EffectSettings()),
              var merged = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any] else {
            return EffectSettings()
        }
        merged.merge(saved) { _, new in new }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              var s = try? JSONDecoder().decode(EffectSettings.self, from: mergedData) else {
            return EffectSettings()
        }
        // Never start the app with the video stopped.
        s.freeze = false
        s.blank = false
        s.cameraOff = false
        s.startingSoon = false
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
