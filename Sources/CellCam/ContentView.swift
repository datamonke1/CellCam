import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraService()

    @State private var zoom: CGFloat = 1
    @State private var flashEnabled = true
    @State private var saveToPhotos = true

    /// Minutes between photos. 60 = hourly (project default); 1 is for testing the setup.
    @State private var intervalMinutes = 60
    @State private var timelapseRunning = false
    @State private var secondsToNext: Int?
    @State private var nextPhotoAt: Date?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            CameraPreview(session: camera.session)
                .frame(maxWidth: .infinity, maxHeight: 320)
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

            controls

            timelapseControls

            footer
        }
        .padding()
        .onAppear { camera.configureIfNeeded() }
        .onReceive(tick) { _ in tickTimelapse() }
        .onChange(of: zoom) { camera.setZoom($0) }
        .onChange(of: flashEnabled) { camera.flashEnabled = $0 }
        .onChange(of: saveToPhotos) { camera.saveToPhotos = $0 }
    }

    // MARK: - Sections

    private var statusBadge: some View {
        Text(timelapseRunning ? "● TIMELAPSE RUNNING" : (camera.isRunning ? "● CAMERA READY" : "○ CAMERA OFF"))
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
            .foregroundStyle(timelapseRunning ? .green : .white)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Zoom \(String(format: "%.1f", zoom))×")
                    .font(.subheadline).monospacedDigit()
                Slider(value: $zoom, in: 1...max(camera.maxZoom, 1), step: 0.1)
            }
            HStack(spacing: 20) {
                Toggle("Flash (Blitz)", isOn: $flashEnabled)
                    .disabled(!camera.hasFlash)
                Toggle("Save to Photos", isOn: $saveToPhotos)
            }
            .font(.subheadline)
        }
    }

    private var timelapseControls: some View {
        VStack(spacing: 10) {
            Picker("Interval", selection: $intervalMinutes) {
                Text("1 min (test)").tag(1)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("60 min (hourly)").tag(60)
            }
            .pickerStyle(.segmented)
            .disabled(timelapseRunning)

            Button(timelapseRunning ? "Stop timelapse" : "Start timelapse") {
                timelapseRunning ? stopTimelapse() : startTimelapse()
            }
            .buttonStyle(.borderedProminent)
            .tint(timelapseRunning ? .red : .green)
            .disabled(!camera.isConfigured)

            Button("Take test photo now") { camera.capturePhoto() }
                .buttonStyle(.bordered)
                .disabled(!camera.isConfigured)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Photos taken: \(camera.photoCount)")
            if let last = camera.lastPhotoAt {
                Text("Last: \(last.formatted(date: .omitted, time: .standard))")
            }
            if timelapseRunning, let secondsToNext {
                Text("Next photo in \(secondsToNext / 60):\(String(format: "%02d", secondsToNext % 60))")
            }
            Text("Keep the phone unlocked, plugged in, and this app open.\nLocking the phone stops the camera (iOS rule).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .font(.footnote)
    }

    // MARK: - Timelapse logic

    private func startTimelapse() {
        camera.capturePhoto() // first photo immediately, so framing/flash can be checked
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
            camera.capturePhoto()
            scheduleNext()
        }
    }
}
