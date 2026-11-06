import AVFoundation
import Foundation
import Photos
import UIKit

/// Owns the AVCaptureSession. All session work happens on `sessionQueue`;
/// published state is updated on the main queue.
///
/// Important iOS limitation (by design): the camera only works while the app
/// is in the foreground. Locking the phone interrupts the session with
/// `videoDeviceNotAvailableInBackground`, so the phone must stay unlocked
/// with this app open for the whole experiment.
final class CameraService: NSObject, ObservableObject {
    @Published var isConfigured = false
    @Published var isRunning = false
    @Published var photoCount = 0
    @Published var photoURLs: [URL] = []
    @Published var lastPhotoAt: Date?
    @Published var lastError: String?
    @Published var maxZoom: CGFloat = 1
    @Published var hasFlash = false
    @Published var totalPhotoBytes: Int64 = 0
    @Published var deviceFreeBytes: Int64 = 0
    @Published var seriesInProgress = false
    @Published var seriesStatus: String?
    /// Latest filtered frame for the live Settings preview.
    @Published var livePreviewImage: UIImage?

    /// When true, video frames are rendered (filtered) for the Settings tab.
    var livePreviewActive = false
    /// Settings snapshot used to filter the live preview; kept in sync by the UI.
    var previewSettings = AppSettings()

    var flashEnabled = true
    var saveToPhotos = true

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "dev.datamonke1.cellcam.video")
    private let ciContext = CIContext()
    private var lastPreviewAt = Date.distantPast
    private var device: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "dev.datamonke1.cellcam.session")

    // MARK: - Setup

    func configureIfNeeded() {
        loadSavedPhotos()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configure()
                } else {
                    self?.reportError("Camera permission denied. Enable it in Settings > Privacy > Camera.")
                }
            }
        default:
            reportError("Camera permission denied. Enable it in Settings > Privacy > Camera.")
        }
        if saveToPhotos {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
        }
    }

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input),
                  self.session.canAddOutput(self.photoOutput) else {
                self.session.commitConfiguration()
                self.reportError("Could not access the back camera.")
                return
            }

            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)

            // Video output feeds the filtered live preview (Settings tab).
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            self.session.commitConfiguration()

            self.device = camera
            let zoomCap = min(camera.activeFormat.videoMaxZoomFactor, 10)
            DispatchQueue.main.async {
                self.maxZoom = max(zoomCap, 1)
                self.hasFlash = camera.hasFlash
                self.isConfigured = true
            }

            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = self.session.isRunning }
        }
    }

    // MARK: - Zoom & flash

    /// Digital zoom on the wide camera. 1 = no zoom.
    func setZoom(_ factor: CGFloat) {
        setZoom(factor, completion: nil)
    }

    func setZoom(_ factor: CGFloat, completion: (() -> Void)?) {
        sessionQueue.async { [weak self] in
            guard let self, let camera = self.device else {
                completion?()
                return
            }
            let clamped = min(max(factor, 1), self.maxZoom)
            do {
                try camera.lockForConfiguration()
                camera.videoZoomFactor = clamped
                camera.unlockForConfiguration()
            } catch {
                self.reportError("Could not set zoom: \(error.localizedDescription)")
            }
            completion?()
        }
    }

    // MARK: - Capture

    private var pendingCapture: ((Result<Data, Error>) -> Void)?

    /// Single test photo at the current zoom.
    func capturePhoto() {
        capturePhotoData { [weak self] result in
            switch result {
            case .success(let data):
                self?.save(data, suffix: "Testfoto", at: Date())
            case .failure(let error):
                self?.reportError("Capture failed: \(error.localizedDescription)")
            }
        }
    }

    private func capturePhotoData(completion: @escaping (Result<Data, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, self.session.isRunning else {
                completion(.failure(NSError(
                    domain: "CellCam", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Camera is not running (app must stay in the foreground, phone unlocked)."])))
                return
            }
            self.pendingCapture = completion
            let settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
            )
            let useFlash = self.flashEnabled && (self.device?.hasFlash ?? false)
            settings.flashMode = useFlash ? .on : .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Photo series (normal / zoom / zoom+filter)

    /// One cycle: 1) normal photo (1x, no filter), 2) zoom photo,
    /// 3) filtered version of photo 2. All three share one timestamp.
    func captureSeries(settings: AppSettings) {
        guard !seriesInProgress else { return }
        flashEnabled = settings.flashEnabled
        saveToPhotos = settings.saveToPhotos
        seriesInProgress = true
        let seriesDate = Date()
        setSeriesStatus("Serie läuft: Foto 1 (normal)…")

        // 1) Normal photo at 1x
        setZoom(1) { [weak self] in
            self?.capturePhotoData { result in
                switch result {
                case .failure(let error):
                    self?.finishSeries(settings: settings,
                                       error: "Foto 1 fehlgeschlagen: \(error.localizedDescription)")
                case .success(let normalData):
                    self?.save(normalData, suffix: "Foto-1-normal", at: seriesDate)
                    self?.captureZoomPhoto(settings: settings, seriesDate: seriesDate, normalData: normalData)
                }
            }
        }
    }

    private func captureZoomPhoto(settings: AppSettings, seriesDate: Date, normalData: Data) {
        // Decide the zoom: stored preset, or auto-zoom from photo 1
        // (detection runs in the background so the UI never blocks).
        guard settings.autoZoomEnabled else {
            takeZoomPhoto(settings: settings, seriesDate: seriesDate,
                          zoomToUse: CGFloat(settings.zoomFactor),
                          note: "Zoom \(String(format: "%.1f", settings.zoomFactor))× (gespeichert)")
            return
        }
        setSeriesStatus("Serie läuft: Auto-Zoom sucht den Blob…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var zoomToUse = CGFloat(settings.zoomFactor)
            var note = "Auto-Zoom: kein Blob erkannt, gespeicherter Zoom \(String(format: "%.1f", zoomToUse))×"
            if let detection = BlobDetector.detect(
                jpegData: normalData, currentZoom: 1,
                targetFill: CGFloat(settings.autoZoomFillPercent) / 100,
                maxZoom: self.maxZoom) {
                zoomToUse = detection.suggestedZoom
                note = "Auto-Zoom \(String(format: "%.1f", zoomToUse))× (Blob erkannt)"
            }
            self.takeZoomPhoto(settings: settings, seriesDate: seriesDate,
                               zoomToUse: zoomToUse, note: note)
        }
    }

    private func takeZoomPhoto(settings: AppSettings, seriesDate: Date,
                               zoomToUse: CGFloat, note: String) {
        setSeriesStatus("Serie läuft: Foto 2 (\(note))…")

        // 2) Zoom photo, with a short settle time after changing the zoom
        setZoom(zoomToUse) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self?.capturePhotoData { result in
                    switch result {
                    case .failure(let error):
                        self?.finishSeries(settings: settings,
                                           error: "Foto 2 fehlgeschlagen: \(error.localizedDescription)")
                    case .success(let zoomData):
                        self?.save(zoomData, suffix: "Foto-2-zoom", at: seriesDate)
                        self?.saveFilteredPhoto(settings: settings, seriesDate: seriesDate, zoomData: zoomData)
                    }
                }
            }
        }
    }

    private func saveFilteredPhoto(settings: AppSettings, seriesDate: Date, zoomData: Data) {
        setSeriesStatus("Serie läuft: Foto 3 (Zoom + \(settings.filter.displayName))…")
        // 3) Filtered version of photo 2 (same moment, software filter)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let filtered = settings.filter.applied(
                to: zoomData,
                red: settings.channelRed, green: settings.channelGreen,
                blue: settings.channelBlue, alpha: settings.channelAlpha,
                contrast: settings.contrast) ?? zoomData
            self?.save(filtered, suffix: "Foto-3-zoom-filter", at: seriesDate)
            self?.finishSeries(settings: settings, error: nil)
        }
    }

    private func finishSeries(settings: AppSettings, error: String?) {
        // Restore the preview to the stored zoom so framing can be checked.
        setZoom(CGFloat(settings.zoomFactor)) { [weak self] in
            DispatchQueue.main.async {
                self?.seriesInProgress = false
                if let error {
                    self?.seriesStatus = nil
                    self?.lastError = error
                } else {
                    self?.seriesStatus = "Serie fertig: 3 Fotos gespeichert"
                    self?.lastError = nil
                }
            }
        }
    }

    private func setSeriesStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.seriesStatus = text }
    }

    // MARK: - Photo storage / timeline

    /// App-folder directory holding every photo (`cell-yyyyMMdd-HHmmss.jpg`).
    /// File names sort chronologically, which is what the timeline uses.
    func photosDirectory(create: Bool = false) -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("CellCam", isDirectory: true) else { return nil }
        if create {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Reloads the list of all photos taken so far (oldest first),
    /// plus storage figures for the storage indicator.
    func loadSavedPhotos() {
        guard let dir = photosDirectory() else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let sorted = urls
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let totalBytes = sorted.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let freeBytes = (try? FileManager.default.attributesOfFileSystem(
            forPath: dir.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        DispatchQueue.main.async { [weak self] in
            self?.photoURLs = sorted
            self?.photoCount = sorted.count
            self?.totalPhotoBytes = totalBytes
            self?.deviceFreeBytes = freeBytes
            if let last = sorted.last {
                self?.lastPhotoAt = Self.date(fromFileName: last.lastPathComponent)
            }
        }
    }

    // MARK: - Deleting photos (app folder only; Photos-library copies stay)

    func deletePhoto(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        loadSavedPhotos()
    }

    func deleteAllPhotos() {
        for url in photoURLs {
            try? FileManager.default.removeItem(at: url)
        }
        loadSavedPhotos()
    }

    static func date(fromFileName name: String) -> Date? {
        let formatter = DateFormatter()
        if name.hasPrefix("Serie_") || name.hasPrefix("Einzel_") {
            // Serie_yyyy-MM-dd_HH-mm-ss_...
            let stamp = name.drop(while: { $0 != "_" }).dropFirst().prefix(19)
            guard stamp.count == 19 else { return nil }
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            return formatter.date(from: String(stamp))
        }
        // Legacy: cell-yyyyMMdd-HHmmss[-suffix].jpg
        guard name.hasPrefix("cell-") else { return nil }
        let stamp = name.dropFirst(5).prefix(15)
        guard stamp.count == 15 else { return nil }
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.date(from: String(stamp))
    }

    /// 1, 2 or 3 for series photos, nil for single/test photos.
    /// Works for new (Foto-1-...) and legacy (-1-normal) names.
    static func photoNumber(fromFileName name: String) -> Int? {
        for n in 1...3 {
            if name.contains("Foto-\(n)-") || name.contains("-\(n)-") { return n }
        }
        return nil
    }

    /// Group id: photos of one series share it, every other photo is its own group.
    static func seriesID(fromFileName name: String) -> String {
        if photoNumber(fromFileName: name) != nil, let date = date(fromFileName: name) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            return "serie-" + formatter.string(from: date)
        }
        return "single-" + name
    }

    // MARK: - Saving

    private func save(_ data: Data, suffix: String, at date: Date) {
        // Clear naming: all photos of one series share the same timestamp,
        // and Foto-1/2/3 says which one it is.
        //   Serie_2026-11-06_18-45-00_Foto-1-normal.jpg
        //   Serie_2026-11-06_18-45-00_Foto-2-zoom.jpg
        //   Serie_2026-11-06_18-45-00_Foto-3-zoom-filter.jpg
        //   Einzel_2026-11-06_18-45-00_Testfoto.jpg
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let prefix = suffix.hasPrefix("Foto-") ? "Serie" : "Einzel"
        let name = "\(prefix)_\(formatter.string(from: date))_\(suffix).jpg"

        do {
            guard let dir = photosDirectory(create: true) else {
                reportError("Saving failed: no documents directory.")
                return
            }
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        } catch {
            reportError("Saving to app folder failed: \(error.localizedDescription)")
            return
        }

        if saveToPhotos {
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.lastError = nil
        }
        loadSavedPhotos()
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = message
        }
    }
}

// MARK: - Live preview frames (filtered, for the Settings tab)

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard livePreviewActive,
              Date().timeIntervalSince(lastPreviewAt) > 0.12, // ~8 fps is enough
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastPreviewAt = Date()

        let settings = previewSettings
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        image = settings.filter.applied(to: image)
        image = CellPhotoFilter.applyChannels(
            to: image,
            red: settings.channelRed, green: settings.channelGreen,
            blue: settings.channelBlue, alpha: 1) // alpha handled by the view (checkerboard)
        image = CellPhotoFilter.applyContrast(to: image, value: settings.contrast)

        // Downscale for speed on the iPhone 7, then render.
        let scale: CGFloat = 480 / max(image.extent.width, 1)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return }
        // Back camera in portrait: frames need a quarter turn.
        let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
        DispatchQueue.main.async { [weak self] in
            self?.livePreviewImage = uiImage
        }
    }
}

// MARK: - Photo delegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let completion = pendingCapture
        pendingCapture = nil
        if let error {
            completion?(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion?(.failure(NSError(
                domain: "CellCam", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Capture failed: no image data."])))
            return
        }
        completion?(.success(data))
    }
}
