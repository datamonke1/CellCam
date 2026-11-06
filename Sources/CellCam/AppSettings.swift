import Foundation

/// Everything the user can set under "Settings", persisted as one saved set.
struct AppSettings: Codable, Equatable {
    var flashEnabled: Bool = true
    /// Stored zoom used for photo 2 (and as fallback for auto-zoom).
    var zoomFactor: Double = 2.0
    var autoZoomEnabled: Bool = false
    /// Auto-zoom target: blob should fill this share of the image width (percent).
    var autoZoomFillPercent: Double = 80
    var filter: CellPhotoFilter = .contrast
    /// Time T between series, in minutes.
    var intervalMinutes: Int = 60
    var saveToPhotos: Bool = true
}

/// Saves/loads one `AppSettings` set in UserDefaults.
final class SettingsStore {
    private let key = "cellcam.settings.v1"
    private let defaults = UserDefaults.standard

    var hasSavedSettings: Bool { defaults.data(forKey: key) != nil }

    func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    func load() -> AppSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}
