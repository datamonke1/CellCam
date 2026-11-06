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

    var flashEnabled = true
    var saveToPhotos = true

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
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
        sessionQueue.async { [weak self] in
            guard let self, let camera = self.device else { return }
            let clamped = min(max(factor, 1), self.maxZoom)
            do {
                try camera.lockForConfiguration()
                camera.videoZoomFactor = clamped
                camera.unlockForConfiguration()
            } catch {
                self.reportError("Could not set zoom: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, self.session.isRunning else {
                self?.reportError("Camera is not running (app must stay in the foreground, phone unlocked).")
                return
            }
            let settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
            )
            let useFlash = self.flashEnabled && (self.device?.hasFlash ?? false)
            settings.flashMode = useFlash ? .on : .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
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

    /// Reloads the list of all photos taken so far (oldest first).
    func loadSavedPhotos() {
        guard let dir = photosDirectory() else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        let sorted = urls
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        DispatchQueue.main.async { [weak self] in
            self?.photoURLs = sorted
            self?.photoCount = sorted.count
            if let last = sorted.last {
                self?.lastPhotoAt = Self.date(fromFileName: last.lastPathComponent)
            }
        }
    }

    static func date(fromFileName name: String) -> Date? {
        // cell-yyyyMMdd-HHmmss.jpg
        let core = name.dropFirst(5).dropLast(4)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.date(from: String(core))
    }

    // MARK: - Saving

    private func save(_ data: Data) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "cell-\(formatter.string(from: Date())).jpg"

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

// MARK: - Photo delegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            reportError("Capture failed: \(error.localizedDescription)")
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            reportError("Capture failed: no image data.")
            return
        }
        save(data)
    }
}
