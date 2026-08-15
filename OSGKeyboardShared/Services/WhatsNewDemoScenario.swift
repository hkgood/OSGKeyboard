// WhatsNewDemoScenario.swift
// OSGKeyboard · Shared
//
// DEBUG-only bridge: the main app arms a scenario in the App Group, then the
// real keyboard extension plays a scripted UI timeline over a Notes-like host.
// Never read in Release.

import Foundation

public enum WhatsNewDemoScenario: String, Sendable {
    case edit
    case ai
    case clipboard
    case clipboardSkills

    public enum Keys {
        public static let scenario = "debug.whatsNew.demoScenario"
        public static let seedText = "debug.whatsNew.seedText"
        public static let armedAt = "debug.whatsNew.armedAt"
        /// `zh` / `en` — drives demo copy; UI strings follow AppGroup `uiLanguage`.
        public static let language = "debug.whatsNew.language"
        /// Set while the extension timeline is running (survives consume).
        public static let playing = "debug.whatsNew.playing"
    }

    public enum Language: String, Sendable {
        case zh
        case en
    }

    /// How long an armed scenario stays valid (avoids sticky demos).
    public static let armTTL: TimeInterval = 120

    public static func arm(
        _ scenario: WhatsNewDemoScenario,
        seedText: String,
        language: Language = .zh,
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) {
        guard let defaults else { return }
        // Don't stomp an in-flight timeline.
        guard !isPlaying(defaults: defaults) else { return }
        defaults.set(scenario.rawValue, forKey: Keys.scenario)
        defaults.set(seedText, forKey: Keys.seedText)
        defaults.set(language.rawValue, forKey: Keys.language)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.armedAt)
        defaults.synchronize()
    }

    /// Peek without clearing — clear only after the demo timeline finishes.
    public static func peek(
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> (scenario: WhatsNewDemoScenario, seedText: String, language: Language)? {
        guard let defaults else { return nil }
        guard let raw = defaults.string(forKey: Keys.scenario),
              let scenario = WhatsNewDemoScenario(rawValue: raw)
        else { return nil }
        let armedAt = defaults.double(forKey: Keys.armedAt)
        guard armedAt > 0,
              Date().timeIntervalSince1970 - armedAt < armTTL
        else {
            clear(defaults: defaults)
            return nil
        }
        let language = Language(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .zh
        let seed = defaults.string(forKey: Keys.seedText)
            ?? (language == .en
                ? "Meeting at 3pm tomorrow to discuss the plan"
                : "明天下午三点开会讨论方案")
        return (scenario, seed, language)
    }

    public static func consume(
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> (scenario: WhatsNewDemoScenario, seedText: String, language: Language)? {
        guard let defaults else { return nil }
        guard let armed = peek(defaults: defaults) else { return nil }
        // Keep `playing` so host re-arm / pasteboard capture stay suppressed.
        defaults.set(true, forKey: Keys.playing)
        defaults.removeObject(forKey: Keys.scenario)
        defaults.removeObject(forKey: Keys.seedText)
        defaults.removeObject(forKey: Keys.armedAt)
        // Keep language for the in-flight timeline; cleared in finishPlaying.
        defaults.synchronize()
        return armed
    }

    public static func isPlaying(
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) -> Bool {
        defaults?.bool(forKey: Keys.playing) == true
    }

    public static func finishPlaying(
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable
    ) {
        guard let defaults else { return }
        defaults.removeObject(forKey: Keys.playing)
        defaults.removeObject(forKey: Keys.language)
        defaults.synchronize()
    }

    public static func clear(defaults: UserDefaults? = AppGroup.defaultsIfAvailable) {
        guard let defaults else { return }
        defaults.removeObject(forKey: Keys.scenario)
        defaults.removeObject(forKey: Keys.seedText)
        defaults.removeObject(forKey: Keys.armedAt)
        defaults.removeObject(forKey: Keys.language)
        defaults.removeObject(forKey: Keys.playing)
        defaults.synchronize()
    }
}
