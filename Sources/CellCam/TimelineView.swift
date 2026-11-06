import SwiftUI
import UIKit

/// Bottom timeline: every photo taken so far, oldest -> newest.
/// Tap a thumbnail to see it full-screen.
struct TimelineView: View {
    let photoURLs: [URL]
    @State private var selected: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Timeline — \(photoURLs.count) Foto\(photoURLs.count == 1 ? "" : "s")")
                .font(.subheadline.bold())

            if photoURLs.isEmpty {
                Text("Noch keine Fotos. Nimm ein Testfoto auf!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(photoURLs, id: \.self) { url in
                            Button {
                                selected = url
                            } label: {
                                VStack(spacing: 2) {
                                    Thumbnail(url: url)
                                        .frame(width: 62, height: 62)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topLeading) {
                                            Text(Self.badge(for: url))
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(.black.opacity(0.65), in: Capsule())
                                                .foregroundStyle(.white)
                                                .padding(3)
                                        }
                                    Text(Self.timeLabel(for: url))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 86)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $selected) { url in
            PhotoDetailView(url: url)
        }
    }

    /// N = normal, Z = zoom, F = zoom+filter, T = single test photo.
    static func badge(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.contains("3-zoom-filter") { return "F" }
        if name.contains("2-zoom") { return "Z" }
        if name.contains("1-normal") { return "N" }
        return "T"
    }

    static func typeName(for url: URL) -> String {
        switch badge(for: url) {
        case "N": return "Normal (ohne Zoom/Filter)"
        case "Z": return "Zoom"
        case "F": return "Zoom + Farbfilter"
        default: return "Testfoto"
        }
    }

    static func timeLabel(for url: URL) -> String {
        guard let date = CameraService.date(fromFileName: url.lastPathComponent) else {
            return url.lastPathComponent
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct Thumbnail: View {
    let url: URL

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.gray.opacity(0.3)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}

private struct PhotoDetailView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("Foto konnte nicht geladen werden.")
                }
                Text(TimelineView.typeName(for: url))
                    .font(.subheadline.bold())
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let date = CameraService.date(fromFileName: url.lastPathComponent) {
                    Text(date.formatted(date: .abbreviated, time: .standard))
                        .font(.footnote)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}
