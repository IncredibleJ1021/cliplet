import ClipletCore
import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let historyLimit = "settings.historyLimit"
        static let hotKey = "settings.hotKey"
        static let pasteAfterSelection = "settings.pasteAfterSelection"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var historyLimit: Int {
        get {
            let stored = defaults.integer(forKey: Keys.historyLimit)
            return stored == 0 ? 50 : min(max(stored, 1), 200)
        }
        set {
            defaults.set(min(max(newValue, 1), 200), forKey: Keys.historyLimit)
        }
    }

    var hotKey: HotKey {
        get {
            guard let data = defaults.data(forKey: Keys.hotKey),
                  let decoded = try? decoder.decode(HotKey.self, from: data) else {
                return HotKey(keyCode: 9, modifiers: [.control, .option])
            }

            return decoded
        }
        set {
            guard let data = try? encoder.encode(newValue) else {
                return
            }

            defaults.set(data, forKey: Keys.hotKey)
        }
    }

    var pasteAfterSelection: Bool {
        get {
            guard defaults.object(forKey: Keys.pasteAfterSelection) != nil else {
                return true
            }

            return defaults.bool(forKey: Keys.pasteAfterSelection)
        }
        set {
            defaults.set(newValue, forKey: Keys.pasteAfterSelection)
        }
    }
}
