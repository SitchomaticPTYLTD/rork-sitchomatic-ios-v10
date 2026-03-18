import Foundation

class BatchPresetService {
    static let shared = BatchPresetService()
    private let key = "batchPresets"
    private init() {}

    func loadPresets() -> [BatchPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([BatchPreset].self, from: data) else {
            return []
        }
        return presets
    }

    func savePresets(_ presets: [BatchPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
