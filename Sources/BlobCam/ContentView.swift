import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraService()
    @ObservedObject private var github = GitHubSync.shared
    private let settingsStore = SettingsStore()

    // Draft settings (edited in the UI, saved/loaded via SettingsStore)
    @State private var flashEnabled = true
    @State private var zoom: Double = 2.0
    @State private var autoZoomEnabled = false
    @State private var autoZoomFillPercent: Double = 80
    @State private var filter: CellPhotoFilter = .contrast
    @State private var contrast: Double = 1.0
    @State private var channelRed: Double = 1.0
    @State private var channelGreen: Double = 1.0
    @State private var channelBlue: Double = 1.0
    @State private var channelAlpha: Double = 1.0
    @State private var intervalMinutes = 60
    @State private var saveToPhotos = true
    @State private var githubSyncEnabled = true
    @State private var githubToken = ""
    @State private var settingsMessage: String?

    @State private var selectedTab = 0
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
                    contrast: contrast,
                    channelRed: channelRed, channelGreen: channelGreen,
                    channelBlue: channelBlue, channelAlpha: channelAlpha,
                    intervalMinutes: intervalMinutes,
                    saveToPhotos: saveToPhotos,
                    githubSyncEnabled: githubSyncEnabled)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            betriebTab
                .tabItem { Label("Betrieb", systemImage: "camera") }
                .tag(0)
            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(1)
        }
        .onAppear {
            camera.configureIfNeeded()
            if let saved = settingsStore.load() {
                apply(saved)
                settingsMessage = "Gespeicherte Settings geladen"
            }
            applyGitHubConfig()
            github.enqueueMissing(from: camera.photosDirectory())
            syncPreview()
        }
        .onReceive(tick) { _ in tickTimelapse() }
        .onChange(of: zoom) { camera.setZoom(CGFloat($0)) }
        .onChange(of: flashEnabled) { camera.flashEnabled = $0 }
        .onChange(of: saveToPhotos) { camera.saveToPhotos = $0 }
        .onChange(of: camera.isConfigured) { configured in
            if configured { camera.setZoom(CGFloat(zoom)) }
        }
        .onChange(of: filter) { _ in syncPreview() }
        .onChange(of: contrast) { _ in syncPreview() }
        .onChange(of: channelRed) { _ in syncPreview() }
        .onChange(of: channelGreen) { _ in syncPreview() }
        .onChange(of: channelBlue) { _ in syncPreview() }
        .onChange(of: channelAlpha) { _ in syncPreview() }
    }

    // MARK: - Tab 1: Betrieb (operation)

    private var betriebTab: some View {
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

                timelapseControls
                storageSection
                githubStatusSection

                Divider()

                TimelineView(photoURLs: camera.photoURLs,
                             onDelete: { camera.deletePhoto($0) },
                             onDeleteAll: { camera.deleteAllPhotos() })
            }
            .padding()
        }
    }

    private var statusBadge: some View {
        Text(timelapseRunning ? "● TIMELAPSE RUNNING" : (camera.isRunning ? "● CAMERA READY" : "○ CAMERA OFF"))
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
            .foregroundStyle(timelapseRunning ? .green : .white)
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

    /// Estimated days until the storage is full, with the currently
    /// selected settings. Every series is stored in the app folder, and
    /// (optionally) again in the Photos library on the same device.
    private var storageDaysRemaining: Double? {
        guard camera.deviceFreeBytes > 0, camera.averageSeriesBytes > 0,
              intervalMinutes > 0 else { return nil }
        let bytesPerSeries = Double(camera.averageSeriesBytes) * (saveToPhotos ? 2 : 1)
        let seriesPerDay = 1440.0 / Double(intervalMinutes)
        let bytesPerDay = bytesPerSeries * seriesPerDay
        guard bytesPerDay > 0 else { return nil }
        return Double(camera.deviceFreeBytes) / bytesPerDay
    }

    private func formatStorageDuration(days: Double) -> String {
        if days < 1 {
            return "ca. \(max(Int((days * 24).rounded()), 1)) Stunden"
        } else if days < 60 {
            return "ca. \(Int(days.rounded())) Tage"
        } else if days < 365 {
            return "ca. \(Int((days / 30.44).rounded())) Monate"
        } else {
            return "ca. \(String(format: "%.1f", days / 365.25)) Jahre"
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Speicherplatz")
                .font(.subheadline.bold())
            Text("BlobCam: \(camera.photoCount) Fotos · \(Self.formatBytes(camera.totalPhotoBytes)) belegt")
                .font(.footnote)
            Text("Frei auf dem iPhone: \(Self.formatBytes(camera.deviceFreeBytes))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if camera.deviceFreeBytes > 0 {
                ProgressView(value: Double(camera.totalPhotoBytes),
                             total: Double(camera.totalPhotoBytes + camera.deviceFreeBytes))
            }
            if let days = storageDaysRemaining {
                let until = Date().addingTimeInterval(days * 86_400)
                Text("Reicht noch \(formatStorageDuration(days: days)) (bis ca. \(until.formatted(date: .abbreviated, time: .omitted)))")
                    .font(.footnote.bold())
                Text("bei \(intervalMinutes) min Intervall · 3 Fotos/Serie · Ø \(Self.formatBytes(camera.averageSeriesBytes))/Serie\(saveToPhotos ? " · inkl. Fotos-App-Kopie (zählt doppelt)" : "")\(camera.seriesCount == 0 ? " · noch keine Serie gemessen, Schätzwert" : " · aus \(camera.seriesCount) Serie\(camera.seriesCount == 1 ? "" : "n") gemessen")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tab 2: Settings (with live picture)

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                liveSettingsPreview

                // 1) Flash
                Toggle("1) Blitz", isOn: $flashEnabled)
                    .disabled(!camera.hasFlash)

                // 2) Zoom
                HStack {
                    Text("2) Zoom \(String(format: "%.1f", zoom))×")
                        .font(.subheadline).monospacedDigit()
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

                // 3) Colour filter + channels
                Picker("3) Farbfilter", selection: $filter) {
                    ForEach(CellPhotoFilter.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Kontrast \(String(format: "%.2f", contrast))")
                        .font(.subheadline).monospacedDigit()
                    Slider(value: $contrast, in: 0.4...2.0, step: 0.05)
                }

                Text("Farbkanäle einzeln")
                    .font(.subheadline.bold())
                channelSlider("Rot", value: $channelRed, color: .red)
                channelSlider("Grün", value: $channelGreen, color: .green)
                channelSlider("Blau", value: $channelBlue, color: .blue)
                channelSlider("Alpha", value: $channelAlpha, color: .gray, range: 0...1)
                Button("Kanäle + Kontrast zurücksetzen") {
                    channelRed = 1; channelGreen = 1; channelBlue = 1; channelAlpha = 1; contrast = 1
                }
                .font(.caption)
                Text("Alpha sieht man im Live-Bild auf dem Schachbrett; im gespeicherten JPEG wird Transparenz auf Schwarz abgeflacht.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Toggle("In Fotos-App speichern", isOn: $saveToPhotos)
                    .font(.subheadline)

                githubSettingsSection

                // Save / load
                HStack {
                    Button("Settings speichern") {
                        settingsStore.save(currentSettings)
                        applyGitHubConfig()
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
                if let status = camera.seriesStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .onAppear {
            syncPreview()
            camera.livePreviewActive = true
        }
        .onDisappear { camera.livePreviewActive = false }
    }

    /// Live picture with the current filter + channel settings applied.
    private var liveSettingsPreview: some View {
        ZStack {
            Checkerboard()
            if let image = camera.livePreviewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(channelAlpha)
            } else {
                CameraPreview(session: camera.session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) {
            Text("● LIVE (mit Filter)")
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .padding(8)
        }
    }

    private var githubStatusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GitHub-Sync")
                .font(.subheadline.bold())
            Text(github.statusText)
                .font(.footnote)
            if let error = github.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Ziel: github.com/\(currentSettings.githubOwner)/\(currentSettings.githubRepo) (privat)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var githubSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitHub-Sync")
                .font(.subheadline.bold())
            Toggle("Fotos nach GitHub hochladen, sobald Internet da ist", isOn: $githubSyncEnabled)
                .onChange(of: githubSyncEnabled) { _ in applyGitHubConfig() }
            Text("Repo: \(currentSettings.githubOwner)/\(currentSettings.githubRepo) · \(github.hasToken ? "Token gespeichert (\(github.tokenPreview()))" : "kein Token")")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("GitHub-Token hier einfügen", text: $githubToken)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.footnote)
            HStack {
                Button("Token speichern") {
                    applyGitHubConfig()
                    settingsStore.save(currentSettings)
                    settingsMessage = github.hasToken ? "Token gespeichert" : "Token-Feld war leer"
                }
                .buttonStyle(.bordered)
                Button("Jetzt synchronisieren") {
                    applyGitHubConfig()
                    github.enqueueMissing(from: camera.photosDirectory())
                    github.flush()
                }
                .buttonStyle(.bordered)
                .disabled(!githubSyncEnabled)
            }
            Text("Token: github.com → Settings → Developer settings → Fine-grained tokens → Generate, nur Repo blobcam_data, Berechtigung Contents: Read and write. Einmalig einfügen.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(github.statusText)
                .font(.caption)
            if let error = github.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func channelSlider(_ name: String, value: Binding<Double>,
                               color: Color, range: ClosedRange<Double> = 0...2) -> some View {
        HStack {
            Text("\(name) \(String(format: "%.2f", value.wrappedValue))")
                .font(.caption).monospacedDigit()
                .frame(width: 86, alignment: .leading)
            Slider(value: value, in: range, step: 0.05)
                .tint(color)
        }
    }

    // MARK: - Settings apply / sync

    private func apply(_ settings: AppSettings) {
        flashEnabled = settings.flashEnabled
        zoom = settings.zoomFactor
        autoZoomEnabled = settings.autoZoomEnabled
        autoZoomFillPercent = settings.autoZoomFillPercent
        filter = settings.filter
        contrast = settings.contrast
        channelRed = settings.channelRed
        channelGreen = settings.channelGreen
        channelBlue = settings.channelBlue
        channelAlpha = settings.channelAlpha
        intervalMinutes = settings.intervalMinutes
        saveToPhotos = settings.saveToPhotos
        githubSyncEnabled = settings.githubSyncEnabled
        camera.flashEnabled = settings.flashEnabled
        camera.saveToPhotos = settings.saveToPhotos
        camera.setZoom(CGFloat(settings.zoomFactor))
        applyGitHubConfig()
        syncPreview()
    }

    private func applyGitHubConfig() {
        github.configure(enabled: githubSyncEnabled,
                         owner: currentSettings.githubOwner,
                         repo: currentSettings.githubRepo)
        if !githubToken.isEmpty {
            github.setToken(githubToken)
            githubToken = "" // don't keep the secret in the text field
        }
    }

    private func syncPreview() {
        camera.previewSettings = currentSettings
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Timelapse logic

    private func startTimelapse() {
        camera.captureSeries(settings: currentSettings)
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

/// Grey/white checkerboard so the alpha channel becomes visible.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 18
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = row
                while x < size.width {
                    if col % 2 == 0 {
                        context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)),
                                     with: .color(.gray.opacity(0.45)))
                    }
                    x += cell
                    col += 1
                }
                y += cell
                row += 1
            }
        }
        .background(Color.white)
    }
}
