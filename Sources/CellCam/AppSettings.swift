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
    /// Per-channel gains (colour matrix), 0...2, 1 = unchanged.
    var channelRed: Double = 1.0
    var channelGreen: Double = 1.0
    var channelBlue: Double = 1.0
    /// Alpha gain 0...1 — visible in the live settings preview (checkerboard);
    /// in saved JPEGs transparency is flattened onto black.
    var channelAlpha: Double = 1.0
    /// Time T between series, in minutes.
    var intervalMinutes: Int = 60
    var saveToPhotos: Bool = true

    // Backward-compatible decoding: older saved settings (without the
    // channel fields) must still load instead of being discarded.
    init(flashEnabled: Bool = true, zoomFactor: Double = 2.0,
         autoZoomEnabled: Bool = false, autoZoomFillPercent: Double = 80,
         filter: CellPhotoFilter = .contrast,
         channelRed: Double = 1.0, channelGreen: Double = 1.0,
         channelBlue: Double = 1.0, channelAlpha: Double = 1.0,
         intervalMinutes: Int = 60, saveToPhotos: Bool = true) {
        self.flashEnabled = flashEnabled
        self.zoomFactor = zoomFactor
        self.autoZoomEnabled = autoZoomEnabled
        self.autoZoomFillPercent = autoZoomFillPercent
        self.filter = filter
        self.channelRed = channelRed
        self.channelGreen = channelGreen
        self.channelBlue = channelBlue
        self.channelAlpha = channelAlpha
        self.intervalMinutes = intervalMinutes
        self.saveToPhotos = saveToPhotos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flashEnabled = try c.decodeIfPresent(Bool.self, forKey: .flashEnabled) ?? true
        zoomFactor = try c.decodeIfPresent(Double.self, forKey: .zoomFactor) ?? 2.0
        autoZoomEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoZoomEnabled) ?? false
        autoZoomFillPercent = try c.decodeIfPresent(Double.self, forKey: .autoZoomFillPercent) ?? 80
        filter = try c.decodeIfPresent(CellPhotoFilter.self, forKey: .filter) ?? .contrast
        channelRed = try c.decodeIfPresent(Double.self, forKey: .channelRed) ?? 1.0
        channelGreen = try c.decodeIfPresent(Double.self, forKey: .channelGreen) ?? 1.0
        channelBlue = try c.decodeIfPresent(Double.self, forKey: .channelBlue) ?? 1.0
        channelAlpha = try c.decodeIfPresent(Double.self, forKey: .channelAlpha) ?? 1.0
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 60
        saveToPhotos = try c.decodeIfPresent(Bool.self, forKey: .saveToPhotos) ?? true
    }
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
