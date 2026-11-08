import ImageIO
import SwiftUI
import UIKit

/// Timeline grouped by series: the 3 photos of one series are always
/// shown stacked under each other. Tapping any photo opens a full-screen
/// pager — swipe left/right through all photos. The photos come from the
/// app folder, so this also works when "save to Photos" is switched off.
struct TimelineView: View {
    let photoURLs: [URL]
    let onDelete: (URL) -> Void
    let onDeleteAll: () -> Void
    @State private var confirmDeleteAll = false
    @State private var pagerIndex: Int?
    @State private var showPager = false

    private struct Group: Identifiable {
        let id: String
        let date: Date?
        let urls: [URL]
        var isSeries: Bool { id.hasPrefix("serie-") }
    }

    private var groups: [Group] {
        let grouped = Dictionary(grouping: photoURLs) {
            CameraService.seriesID(fromFileName: $0.lastPathComponent)
        }
        return grouped.map { id, urls in
            Group(id: id,
                  date: urls.first.flatMap { CameraService.date(fromFileName: $0.lastPathComponent) },
                  urls: urls.sorted {
                      (CameraService.photoNumber(fromFileName: $0.lastPathComponent) ?? 99) <
                      (CameraService.photoNumber(fromFileName: $1.lastPathComponent) ?? 99)
                  })
        }
        .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Timeline — \(photoURLs.count) Foto\(photoURLs.count == 1 ? "" : "s")")
                        .font(.subheadline.bold())
                    Spacer()
                    if !photoURLs.isEmpty {
                        Button("Alle löschen", role: .destructive) { confirmDeleteAll = true }
                            .font(.caption)
                    }
                }
                Text("Es wird nur geladen, was gerade auf dem Bildschirm ist.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if photoURLs.isEmpty {
                    Text("Noch keine Fotos. Nimm ein Testfoto auf!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ForEach(groups) { group in
                        groupView(group)
                    }
                }
            }
            .padding()
        }
        .alert("Alle Fotos löschen?", isPresented: $confirmDeleteAll) {
            Button("Abbrechen", role: .cancel) {}
            Button("Alle löschen", role: .destructive) { onDeleteAll() }
        } message: {
            Text("Alle \(photoURLs.count) Fotos im App-Ordner werden gelöscht. Kopien in der Fotos-App bleiben erhalten.")
        }
        .sheet(isPresented: $showPager) {
            PhotoPagerView(urls: photoURLs,
                           startIndex: pagerIndex ?? 0,
                           onDelete: onDelete)
        }
    }

    // MARK: - One series (3 photos stacked vertically)

    private func groupView(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(groupTitle(group))
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(group.urls, id: \.self) { url in
                    Button {
                        pagerIndex = photoURLs.firstIndex(of: url) ?? 0
                        showPager = true
                    } label: {
                        HStack(spacing: 10) {
                            Thumbnail(url: url)
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.rowTitle(for: url))
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                Text(url.lastPathComponent)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func groupTitle(_ group: Group) -> String {
        let when = group.date.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        } ?? ""
        return group.isSeries ? "Serie · \(when)" : "Einzel/Test · \(when)"
    }

    // MARK: - Labels

    static func rowTitle(for url: URL) -> String {
        let name = url.lastPathComponent
        switch CameraService.photoNumber(fromFileName: name) {
        case 1: return "Foto 1 · Normal (ohne Zoom/Filter)"
        case 2: return "Foto 2 · Zoom"
        case 3: return "Foto 3 · Zoom + Filter"
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

// MARK: - Full-screen swipe pager

private struct PhotoPagerView: View {
    let onDelete: (URL) -> Void
    @State private var urls: [URL]
    @State private var index: Int
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    init(urls: [URL], startIndex: Int, onDelete: @escaping (URL) -> Void) {
        self.onDelete = onDelete
        _urls = State(initialValue: urls)
        _index = State(initialValue: min(max(startIndex, 0), max(urls.count - 1, 0)))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                if urls.isEmpty {
                    Text("Keine Fotos mehr.")
                        .foregroundStyle(.secondary)
                } else {
                    let url = urls[min(index, urls.count - 1)]
                    PagerImage(url: url)
                        .id(url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 30).onEnded { value in
                                if value.translation.width < -40 {
                                    index = min(index + 1, urls.count - 1)
                                } else if value.translation.width > 40 {
                                    index = max(index - 1, 0)
                                }
                            }
                        )
                    Text(TimelineView.rowTitle(for: url))
                        .font(.subheadline.bold())
                    Text("Foto \(min(index, urls.count - 1) + 1) von \(urls.count) · wischen zum Blättern")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let date = CameraService.date(fromFileName: url.lastPathComponent) {
                        Text(date.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(url.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.bottom, 8)
            .navigationTitle("Fotos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !urls.isEmpty {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Dieses Foto löschen?", isPresented: $confirmDelete) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) { deleteCurrent() }
            } message: {
                Text("Das Foto wird aus dem App-Ordner gelöscht. Eine Kopie in der Fotos-App (falls gespeichert) bleibt erhalten.")
            }
        }
    }

    private func deleteCurrent() {
        guard !urls.isEmpty else { return }
        let removed = urls[min(index, urls.count - 1)]
        onDelete(removed)
        urls.removeAll { $0 == removed }
        if urls.isEmpty {
            dismiss()
        } else {
            index = min(index, urls.count - 1)
        }
    }
}

// MARK: - Thumbnail

private struct Thumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.3)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .onAppear { image = ImageThumb.image(at: url, maxPixel: 160) }
        .onDisappear { image = nil }
    }
}

/// One large photo at a time. Swiping changes the index in the pager,
/// so the other files stay on disk.
private struct PagerImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .onAppear { image = ImageThumb.image(at: url, maxPixel: 1200) }
        .onDisappear { image = nil }
    }
}

/// Small decoded previews. A full iPhone-7 JPEG is about 50 MB once
/// unpacked; loading every photo that way gets the app killed on launch.
enum ImageThumb {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        return cache
    }()

    static func image(at url: URL, maxPixel: CGFloat) -> UIImage? {
        let key = "\(url.path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}
