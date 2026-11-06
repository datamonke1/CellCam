import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraService()
    private let settingsStore = SettingsStore()

    // Draft settings (edited in the UI, saved/loaded via SettingsStore)
    @State private var flashEnabled = true
    @State private var zoom: Double = 2.0
    @State private var autoZoomEnabled = false
    @State private var autoZoomFillPercent: Double = 80
    @State private var filter: CellPhotoFilter = .contrast
    @State private var intervalMinutes = 60
    @State private var saveToPhotos = true
    @State private var settingsMessage: String?

    @State private var timelapseRunning = false
    @State private var secondsToNext: Int?
    @State private var nextPhotoAt: Date?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var currentSettings: AppSettings {
        AppSettings(flashEnabled: flashEnabled,
                    zoomFactor: zoom,
                    autoZoomEnabled: autoZoomEnabled,
                    autoZoomFillPercent: autoZoomFillPercent,
                    filter: filter,
                    intervalMinutes: intervalMinutes,
                    saveToPhotos: saveToPhotos)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CameraPreview(session: camera.session)
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topLeading) {
                        statusBadge.padding(8)
                    }

                if let error = camera.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                if let status = camera.seriesStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                settingsSection

                timelapseControls

                storageSection

                Divider()

                TimelineView(photoURLs: camera.photoURLs)
            }
            .padding()
        }
        .onAppear {
            camera.configureIfNeeded()
            // Auto-load saved settings at start, if any.
            if let saved = settingsStore.load() {
                apply(saved)
                settingsMessage = "Gespeicherte Settings geladen"
            }
        }
        .onReceive(tick) { _ in tickTimelapse() }
        .onChange(of: zoom) { camera.setZoom(CGFloat($0)) }
        .onChange(of: flashEnabled) { camera.flashEnabled = $0 }
        .onChange(of: saveToPhotos) { camera.saveToPhotos = $0 }
        .onChange(of: camera.isConfigured) { configured in
            if configured { camera.setZoom(CGFloat(zoom)) }
        }
    }

    // MARK: - Sections

    private var statusBadge: some View {
        Text(timelapseRunning ? "● TIMELAPSE RUNNING" : (camera.isRunning ? "● CAMERA READY" : "○ CAMERA OFF"))
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
            .foregroundStyle(timelapseRunning ? .green : .white)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.headline)

            // 1) Flash
            Toggle("1) Blitz", isOn: $flashEnabled)
                .disabled(!camera.hasFlash)

            // 2) Zoom
            HStack {
                Text("2) Zoom \(String(format: "%.1f", zoom))×")
                    .font(.subheadline).monospacedDigit()
                // Upper bound must always be > 1 (Slider traps on 1...1).
                Slider(value: $zoom, in: 1...max(camera.maxZoom, 2), step: 0.1)
                    .disabled(!camera.isConfigured)
            }
            Toggle("Auto-Zoom (Blob erkennen)", isOn: $autoZoomEnabled)
                .font(.subheadline)
            if autoZoomEnabled {
                HStack {
                    Text("Blob füllt \(Int(autoZoomFillPercent)) %")
                        .font(.subheadline).monospacedDigit()
                    Slider(value: $autoZoomFillPercent, in: 50...95, step: 5)
                }
            }

            // 3) Colour filter
            Picker("3) Farbfilter", selection: $filter) {
                ForEach(CellPhotoFilter.allCases) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .pickerStyle(.menu)

            Toggle("In Fotos-App speichern", isOn: $saveToPhotos)
                .font(.subheadline)

            // Save / load
            HStack {
                Button("Settings speichern") {
                    settingsStore.save(currentSettings)
                    settingsMessage = "Settings gespeichert"
                }
                .buttonStyle(.bordered)
                Button("Settings laden") {
                    if let saved = settingsStore.load() {
                        apply(saved)
                        settingsMessage = "Settings geladen"
                    } else {
                        settingsMessage = "Keine gespeicherten Settings gefunden"
                    }
                }
                .buttonStyle(.bordered)
            }
            if let settingsMessage {
                Text(settingsMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 4) Test photos
            Text("4) Testfotos")
                .font(.subheadline.bold())
            HStack {
                Button("Test-Serie jetzt (3 Fotos)") {
                    camera.captureSeries(settings: currentSettings)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!camera.isConfigured || camera.seriesInProgress)

                Button("Einzel-Testfoto") { camera.capturePhoto() }
                    .buttonStyle(.bordered)
                    .disabled(!camera.isConfigured || camera.seriesInProgress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelapseControls: some View {
        VStack(spacing: 10) {
            Picker("Intervall T", selection: $intervalMinutes) {
                Text("1 min (test)").tag(1)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("60 min (stündlich)").tag(60)
            }
            .pickerStyle(.segmented)
            .disabled(timelapseRunning)

            Button(timelapseRunning ? "Timelapse stoppen" : "Timelapse starten") {
                timelapseRunning ? stopTimelapse() : startTimelapse()
            }
            .buttonStyle(.borderedProminent)
            .tint(timelapseRunning ? .red : .green)
            .disabled(!camera.isConfigured)

            if timelapseRunning, let secondsToNext {
                Text("Nächstes Foto in \(secondsToNext / 60):\(String(format: "%02d", secondsToNext % 60))")
                    .font(.footnote).monospacedDigit()
            }
            Text("Ablauf pro Intervall: 1× normal, 1× Zoom, 1× Zoom+Filter.\nHandy entsperrt, angeschlossen und App offen lassen (iOS-Regel).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Speicherplatz")
                .font(.subheadline.bold())
            Text("CellCam: \(camera.photoCount) Fotos · \(Self.formatBytes(camera.totalPhotoBytes)) belegt")
                .font(.footnote)
            Text("Frei auf dem iPhone: \(Self.formatBytes(camera.deviceFreeBytes))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if camera.deviceFreeBytes > 0 {
                ProgressView(value: Double(camera.totalPhotoBytes),
                             total: Double(camera.totalPhotoBytes + camera.deviceFreeBytes))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Settings apply

    private func apply(_ settings: AppSettings) {
        flashEnabled = settings.flashEnabled
        zoom = settings.zoomFactor
        autoZoomEnabled = settings.autoZoomEnabled
        autoZoomFillPercent = settings.autoZoomFillPercent
        filter = settings.filter
        intervalMinutes = settings.intervalMinutes
        saveToPhotos = settings.saveToPhotos
        camera.flashEnabled = settings.flashEnabled
        camera.saveToPhotos = settings.saveToPhotos
        camera.setZoom(CGFloat(settings.zoomFactor))
    }

    // MARK: - Timelapse logic

    private func startTimelapse() {
        camera.captureSeries(settings: currentSettings) // first series immediately
        scheduleNext()
        timelapseRunning = true
    }

    private func stopTimelapse() {
        timelapseRunning = false
        nextPhotoAt = nil
        secondsToNext = nil
    }

    private func scheduleNext() {
        nextPhotoAt = Date().addingTimeInterval(Double(intervalMinutes * 60))
    }

    private func tickTimelapse() {
        guard timelapseRunning, let nextPhotoAt else { return }
        let remaining = Int(nextPhotoAt.timeIntervalSinceNow.rounded())
        secondsToNext = max(remaining, 0)
        if remaining <= 0 {
            if !camera.seriesInProgress {
                camera.captureSeries(settings: currentSettings)
            }
            scheduleNext()
        }
    }
}
