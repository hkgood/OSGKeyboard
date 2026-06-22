import Foundation

/// Downloads model files from [ModelScope](https://www.modelscope.cn) using the
/// public repo API. Uses the same `owner/model` ids as Hugging Face for repos
/// mirrored on ModelScope (e.g. `aufklarer/Qwen3-ASR-0.6B-MLX-4bit`).
public enum ModelScopeDownloader {

    public static let defaultBaseURL = "https://modelscope.cn"

    private struct FilesPayload: Decodable {
        struct Entry: Decodable {
            let Path: String
            let Size: Int64?
            let entryType: String?

            enum CodingKeys: String, CodingKey {
                case Path
                case Size
                case entryType = "Type"
            }
        }
        let Files: [Entry]
    }

    private struct APIResponse: Decodable {
        let Data: FilesPayload
    }

    public struct RemoteFile: Sendable {
        public let path: String
        public let size: Int64
    }

    // MARK: - Public API

    /// Mirror of `HuggingFaceDownloader.downloadWeights` for ModelScope.
    public static func downloadWeights(
        modelId: String,
        to directory: URL,
        additionalFiles: [String] = [],
        baseURL: String = defaultBaseURL,
        revision: String = "master",
        retryDelaysSeconds: [Int]? = nil,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        HuggingFaceDownloader.prepareRepoDirectoryForDownload(at: directory)

        let listed = try await listAllFiles(modelId: modelId, baseURL: baseURL, revision: revision)
        var selected = Set<String>(["config.json"])
        for file in additionalFiles {
            selected.insert(file)
        }

        let hasExplicitWeights = additionalFiles.contains { $0.hasSuffix(".safetensors") }
        if !hasExplicitWeights {
            for file in listed where file.path.hasSuffix(".safetensors") {
                selected.insert(file.path)
            }
            if listed.contains(where: { $0.path == "model.safetensors.index.json" }) {
                selected.insert("model.safetensors.index.json")
            }
        }

        let files = listed.filter { selected.contains($0.path) }.map(\.path)
        guard !files.isEmpty else {
            throw DownloadError.failedToDownload("\(modelId): no matching files on ModelScope")
        }

        try await downloadFiles(
            modelId: modelId,
            to: directory,
            files: files,
            fileSizes: Dictionary(uniqueKeysWithValues: listed.map { ($0.path, $0.size) }),
            baseURL: baseURL,
            revision: revision,
            retryDelaysSeconds: retryDelaysSeconds,
            progressHandler: progressHandler
        )
    }

    /// Download an explicit list of repo-relative paths into `directory`.
    public static func downloadFiles(
        modelId: String,
        to directory: URL,
        files: [String],
        fileSizes: [String: Int64] = [:],
        baseURL: String = defaultBaseURL,
        revision: String = "master",
        retryDelaysSeconds: [Int]? = nil,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        if files.isEmpty {
            progressHandler?(1.0)
            return
        }

        HuggingFaceDownloader.prepareRepoDirectoryForDownload(at: directory)

        let ordered = files.sorted()
        var sizes = fileSizes
        for path in ordered where sizes[path] == nil {
            sizes[path] = 0
        }

        // Without byte sizes the old logic fell back to `(index + 1) / count`,
        // which jumps to 50% as soon as two small JSON files finish. Resolve
        // sizes from the repo listing whenever any entry is missing.
        if ordered.contains(where: { (sizes[$0] ?? 0) <= 0 }) {
            let listed = try await listAllFiles(
                modelId: modelId,
                baseURL: baseURL,
                revision: revision
            )
            let listedMap = Dictionary(uniqueKeysWithValues: listed.map { ($0.path, $0.size) })
            for path in ordered where (sizes[path] ?? 0) <= 0 {
                if let remote = listedMap[path], remote > 0 {
                    sizes[path] = remote
                }
            }
        }

        let totalBytes = max(ordered.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }, 1)
        var completedBytes: Int64 = 0

        let delays = retryDelaysSeconds ?? HuggingFaceDownloader.downloadRetryDelaysSeconds
        let maxAttempts = delays.count + 1

        for (index, path) in ordered.enumerated() {
            let destination = directory.appendingPathComponent(path, isDirectory: false)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var lastError: Error?
            for attempt in 1...maxAttempts {
                do {
                    try await HuggingFaceDownloader.withDownloadStallGuard(modelId: modelId) { reportProgress in
                        try await fetchFile(
                            modelId: modelId,
                            filePath: path,
                            to: destination,
                            baseURL: baseURL,
                            revision: revision
                        ) { fileBytes, fileExpectedBytes in
                            reportProgress(1.0)
                            let fileSize = sizes[path] ?? 0
                            let expected = fileSize > 0 ? fileSize : fileExpectedBytes
                            let overall: Double
                            if expected > 0, totalBytes > 1 {
                                overall = Double(completedBytes + min(fileBytes, expected)) / Double(totalBytes)
                            } else {
                                // Last resort when listing omits sizes: spread each
                                // file's slice by bytes received vs Content-Length.
                                let slice = 1.0 / Double(ordered.count)
                                let base = Double(index) * slice
                                let inFile = expected > 0
                                    ? min(Double(fileBytes) / Double(expected), 1.0) * slice
                                    : slice
                                overall = base + inFile
                            }
                            progressHandler?(min(max(overall, 0), 1))
                        }
                    }
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    try? FileManager.default.removeItem(at: destination)
                    if attempt < maxAttempts {
                        try await Task.sleep(for: .seconds(delays[attempt - 1]))
                    }
                }
            }

            if let lastError {
                throw DownloadError.failedToDownload(
                    "\(modelId)/\(path) on ModelScope: \(lastError.localizedDescription)"
                )
            }

            completedBytes += sizes[path] ?? 0
            progressHandler?(min(Double(completedBytes) / Double(totalBytes), 1))
        }

        progressHandler?(1.0)
    }

    // MARK: - Listing

    /// Recursively lists every file in a ModelScope repo (used for CoreML bundles).
    public static func listAllFiles(
        modelId: String,
        baseURL: String,
        revision: String
    ) async throws -> [RemoteFile] {
        var collected: [RemoteFile] = []
        try await listFiles(
            modelId: modelId,
            root: nil,
            into: &collected,
            baseURL: baseURL,
            revision: revision
        )
        return collected
    }

    private static func listFiles(
        modelId: String,
        root: String?,
        into collected: inout [RemoteFile],
        baseURL: String,
        revision: String
    ) async throws {
        guard let url = listingURL(modelId: modelId, baseURL: baseURL, revision: revision, root: root) else {
            throw DownloadError.failedToDownload("Invalid ModelScope listing URL for \(modelId)")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DownloadError.failedToDownload("ModelScope listing failed for \(modelId)")
        }

        let payload = try JSONDecoder().decode(APIResponse.self, from: data)
        for entry in payload.Data.Files {
            if isDirectoryEntry(entry) {
                try await listFiles(
                    modelId: modelId,
                    root: entry.Path,
                    into: &collected,
                    baseURL: baseURL,
                    revision: revision
                )
            } else {
                collected.append(RemoteFile(path: entry.Path, size: entry.Size ?? 0))
            }
        }
    }

    private static func isDirectoryEntry(_ entry: FilesPayload.Entry) -> Bool {
        if entry.entryType?.lowercased() == "tree" { return true }
        let size = entry.Size ?? 0
        return size == 0 && !entry.Path.contains(".")
    }

    // MARK: - Transfer

    /// Streams a single repo file. `onBytes` receives `(bytesWritten, expectedBytes)`.
    private static func fetchFile(
        modelId: String,
        filePath: String,
        to destination: URL,
        baseURL: String,
        revision: String,
        onBytes: @escaping (Int64, Int64) -> Void
    ) async throws {
        guard let url = fileURL(modelId: modelId, baseURL: baseURL, revision: revision, filePath: filePath) else {
            throw DownloadError.invalidRemoteFileName(filePath)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3600

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.failedToDownload(filePath)
        }
        guard (200...299).contains(http.statusCode) else {
            throw DownloadError.failedToDownload("\(filePath) HTTP \(http.statusCode)")
        }

        let expectedBytes = http.value(forHTTPHeaderField: "Content-Length")
            .flatMap(Int64.init) ?? 0

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1_048_576)
        var written: Int64 = 0

        for try await byte in asyncBytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 1_048_576 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                onBytes(written, expectedBytes)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        onBytes(written, expectedBytes)
    }

    // MARK: - URLs

    private static func listingURL(
        modelId: String,
        baseURL: String,
        revision: String,
        root: String?
    ) -> URL? {
        var components = URLComponents(string: "\(baseURL)/api/v1/models/\(modelId)/repo/files")
        var items = [
            URLQueryItem(name: "Revision", value: revision),
        ]
        if let root, !root.isEmpty {
            items.append(URLQueryItem(name: "Root", value: root))
        }
        components?.queryItems = items
        return components?.url
    }

    private static func fileURL(
        modelId: String,
        baseURL: String,
        revision: String,
        filePath: String
    ) -> URL? {
        var components = URLComponents(string: "\(baseURL)/api/v1/models/\(modelId)/repo")
        components?.queryItems = [
            URLQueryItem(name: "Revision", value: revision),
            URLQueryItem(name: "FilePath", value: filePath),
        ]
        return components?.url
    }
}
