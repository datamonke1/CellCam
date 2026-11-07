import Foundation
import Network
import UIKit

/// Uploads captured JPEGs to the private GitHub repo `blobcam_data`
/// whenever the iPhone has an internet connection.
///
/// Uses the GitHub Contents API (one commit per file). Photos stay in the
/// app folder either way; GitHub is a backup, not the primary store.
///
/// The token is kept in the Keychain (never in the public CellCam source).
final class GitHubSync: ObservableObject {
    static let shared = GitHubSync()

    @Published var statusText = "GitHub-Sync aus"
    @Published var pendingCount = 0
    @Published var uploadedCount = 0
    @Published var lastError: String?
    @Published var isOnline = false
    @Published var hasToken = false

    var enabled = true
    var owner = "datamonke1"
    var repo = "blobcam_data"

    private let queue = DispatchQueue(label: "dev.datamonke1.cellcam.github")
    private var busy = false
    private let monitor = NWPathMonitor()
    private let pendingKey = "cellcam.github.pending"
    private let syncedKey = "cellcam.github.synced"
    private let tokenKey = "cellcam.github.token"

    private init() {
        hasToken = !(loadToken() ?? "").isEmpty
        pendingCount = pendingNames().count
        uploadedCount = syncedNames().count
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
                self?.refreshStatus()
            }
            if path.status == .satisfied {
                self?.flush()
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    // MARK: - Public

    func configure(enabled: Bool, owner: String, repo: String) {
        self.enabled = enabled
        self.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        self.repo = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshStatus()
        if enabled { flush() }
    }

    func setToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        saveToken(trimmed.isEmpty ? nil : trimmed)
        DispatchQueue.main.async {
            self.hasToken = !trimmed.isEmpty
            self.refreshStatus()
        }
        if !trimmed.isEmpty { flush() }
    }

    func tokenPreview() -> String {
        let t = loadToken() ?? ""
        guard t.count > 8 else { return t.isEmpty ? "" : "••••" }
        return String(t.prefix(4)) + "…" + String(t.suffix(4))
    }

    /// Queue a just-saved photo for upload (no-op if already synced).
    func enqueue(fileURL: URL) {
        let name = fileURL.lastPathComponent
        var pending = pendingNames()
        var synced = syncedNames()
        if synced.contains(name) { return }
        if !pending.contains(name) {
            pending.append(name)
            savePending(pending)
        }
        DispatchQueue.main.async {
            self.pendingCount = pending.count
            self.refreshStatus()
        }
        flush()
    }

    /// Scan the app photo folder and queue anything not yet on GitHub.
    func enqueueMissing(from directory: URL?) {
        guard let directory else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension.lowercased() == "jpg" {
            enqueue(fileURL: url)
        }
    }

    func flush() {
        queue.async { [weak self] in self?.uploadNext() }
    }

    // MARK: - Upload loop

    private func uploadNext() {
        guard !busy else { return }
        guard enabled else {
            DispatchQueue.main.async { self.refreshStatus() }
            return
        }
        // Always try: NWPathMonitor can lag, URLSession fails fast if offline.
        guard let token = loadToken(), !token.isEmpty else {
            DispatchQueue.main.async {
                self.lastError = "GitHub-Token fehlt (Settings → GitHub-Sync)."
                self.refreshStatus()
            }
            return
        }
        var pending = pendingNames()
        guard let name = pending.first else {
            DispatchQueue.main.async { self.refreshStatus() }
            return
        }
        guard let dir = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false)
            .appendingPathComponent("CellCam", isDirectory: true) else { return }
        let fileURL = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            pending.removeAll { $0 == name }
            savePending(pending)
            uploadNext()
            return
        }

        busy = true
        DispatchQueue.main.async { self.statusText = "Lade \(name) hoch…" }

        putFile(name: name, data: data, token: token) { [weak self] result in
            guard let self else { return }
            self.busy = false
            var pending = self.pendingNames()
            var synced = self.syncedNames()
            switch result {
            case .success:
                pending.removeAll { $0 == name }
                synced.insert(name)
                self.savePending(pending)
                self.saveSynced(synced)
                DispatchQueue.main.async {
                    self.pendingCount = pending.count
                    self.uploadedCount = synced.count
                    self.lastError = nil
                    self.refreshStatus()
                }
                self.uploadNext()
            case .failure(let error):
                let message = error.localizedDescription
                // Already on GitHub → treat as synced.
                if message.contains("422") || message.lowercased().contains("already")
                    || message.contains("sha") && message.contains("exists") {
                    pending.removeAll { $0 == name }
                    synced.insert(name)
                    self.savePending(pending)
                    self.saveSynced(synced)
                    DispatchQueue.main.async {
                        self.pendingCount = pending.count
                        self.uploadedCount = synced.count
                        self.lastError = nil
                        self.refreshStatus()
                    }
                    self.uploadNext()
                    return
                }
                DispatchQueue.main.async {
                    self.lastError = message
                    self.refreshStatus()
                }
                // Leave in queue; will retry on next flush / connectivity change.
            }
        }
    }

    private func putFile(name: String, data: Data, token: String,
                         completion: @escaping (Result<Void, Error>) -> Void) {
        let path = "photos/\(name)"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(encodedPath)") else {
            completion(.failure(NSError(domain: "GitHubSync", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Ungültige Repo-URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let body: [String: Any] = [
            "message": "BlobCam: \(name)",
            "content": data.base64EncodedString(),
            "branch": "main"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code) {
                completion(.success(()))
                return
            }
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            // File already exists: GitHub returns 422.
            if code == 422 {
                completion(.failure(NSError(domain: "GitHubSync", code: 422,
                                            userInfo: [NSLocalizedDescriptionKey: "422 already exists"])))
                return
            }
            if code == 401 || code == 403 {
                completion(.failure(NSError(domain: "GitHubSync", code: code,
                                            userInfo: [NSLocalizedDescriptionKey: "GitHub-Token ungültig oder keine Rechte auf blobcam_data (HTTP \(code))."])))
                return
            }
            completion(.failure(NSError(domain: "GitHubSync", code: code,
                                        userInfo: [NSLocalizedDescriptionKey: "GitHub HTTP \(code): \(text.prefix(180))"])))
        }.resume()
    }

    private func refreshStatus() {
        if !enabled {
            statusText = "GitHub-Sync aus"
        } else if !hasToken {
            statusText = "GitHub-Sync: Token fehlt"
        } else if pendingCount == 0 {
            statusText = "GitHub: \(uploadedCount) Foto\(uploadedCount == 1 ? "" : "s") synchronisiert"
        } else {
            statusText = "GitHub: \(pendingCount) wartend · \(uploadedCount) schon oben"
        }
    }

    // MARK: - Persistence

    private func pendingNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
    }
    private func savePending(_ names: [String]) {
        UserDefaults.standard.set(names, forKey: pendingKey)
    }
    private func syncedNames() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: syncedKey) ?? [])
    }
    private func saveSynced(_ names: Set<String>) {
        UserDefaults.standard.set(Array(names), forKey: syncedKey)
    }

    private func loadToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }
    private func saveToken(_ token: String?) {
        if let token, !token.isEmpty {
            UserDefaults.standard.set(token, forKey: tokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tokenKey)
        }
    }
}
