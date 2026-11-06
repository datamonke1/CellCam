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
