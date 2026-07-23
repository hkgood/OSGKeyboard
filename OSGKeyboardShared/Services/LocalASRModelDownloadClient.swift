// LocalASRModelDownloadClient.swift
// OSGKeyboard · Shared
//
// URLSession download with byte-level progress and pause/resume (macOS local model installs).

import Foundation

#if os(macOS)

public struct LocalASRDownloadProgressUpdate: Sendable {
    public let bytesReceived: Int64
    public let bytesTotal: Int64

    public var fraction: Double {
        guard bytesTotal > 0 else { return 0 }
        return min(1, max(0, Double(bytesReceived) / Double(bytesTotal)))
    }
}

/// Controls an in-flight URLSession download; supports pause via resume data,
/// plus automatic retry-with-resume on transient network failures.
public final class LocalASRModelDownloadController: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let onProgress: @Sendable (LocalASRDownloadProgressUpdate) -> Void
    private let maxRetries: Int
    private lazy var delegateSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Big weight files over flaky links: allow long total transfers but
        // fail (and retry) a stalled connection that goes quiet for a while.
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 24 * 60 * 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var remoteURL: URL?
    private var task: URLSessionDownloadTask?
    private var completionContinuation: CheckedContinuation<Void, Error>?
    private var isPausing = false
    private var finished = false
    private var retryCount = 0

    init(
        destinationURL: URL,
        maxRetries: Int = 4,
        onProgress: @escaping @Sendable (LocalASRDownloadProgressUpdate) -> Void
    ) {
        self.destinationURL = destinationURL
        self.maxRetries = maxRetries
        self.onProgress = onProgress
        super.init()
    }

    /// Runs until the archive is fully written to `destinationURL` (survives pause/resume).
    public func download(from remoteURL: URL) async throws {
        self.remoteURL = remoteURL
        retryCount = 0
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            completionContinuation = continuation
            startTask(resumeData: nil)
        }
    }

    public func pause() async throws -> Data {
        guard task != nil, !finished else {
            throw LocalASRModelManagerError.downloadFailed("No active download to pause.")
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            isPausing = true
            task?.cancel(byProducingResumeData: { [weak self] data in
                guard let self else { return }
                self.isPausing = false
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: LocalASRModelManagerError.downloadFailed("Pause failed."))
                }
            })
        }
    }

    /// Continues a paused download; `download(from:)` must still be awaiting.
    public func resumeFromPause(_ resumeData: Data) {
        finished = false
        startTask(resumeData: resumeData)
    }

    public func cancel() {
        finished = true
        task?.cancel()
        completionContinuation?.resume(throwing: CancellationError())
        completionContinuation = nil
        delegateSession.invalidateAndCancel()
    }

    private func startTask(resumeData: Data?) {
        if let resumeData {
            task = delegateSession.downloadTask(withResumeData: resumeData)
        } else if let remoteURL {
            task = delegateSession.downloadTask(with: remoteURL)
        }
        task?.resume()
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(
            LocalASRDownloadProgressUpdate(
                bytesReceived: totalBytesWritten,
                bytesTotal: max(totalBytesExpectedToWrite, 1)
            )
        )
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard !finished else { return }
        finished = true
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: location, to: destinationURL)
            completionContinuation?.resume()
        } catch {
            completionContinuation?.resume(
                throwing: LocalASRModelManagerError.downloadFailed(error.localizedDescription)
            )
        }
        completionContinuation = nil
        session.finishTasksAndInvalidate()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        if isPausing { return }
        guard let error else { return }

        // Transient network drop: resume from where we stopped (if the server
        // handed back resume data) after a short exponential backoff, up to a cap.
        if Self.isRetryable(error), retryCount < maxRetries {
            retryCount += 1
            let resumeData = (error as NSError)
                .userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            let delay = Self.backoffSeconds(attempt: retryCount)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.finished, !self.isPausing else { return }
                self.startTask(resumeData: resumeData)
            }
            return
        }

        finished = true
        completionContinuation?.resume(
            throwing: LocalASRModelManagerError.downloadFailed(error.localizedDescription)
        )
        completionContinuation = nil
        session.finishTasksAndInvalidate()
    }

    /// Network hiccups worth retrying; permanent failures (404, cancelled) are not.
    private static func isRetryable(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorNetworkConnectionLost,
             NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorSecureConnectionFailed,
             NSURLErrorResourceUnavailable,
             NSURLErrorHTTPTooManyRedirects,
             NSURLErrorDataLengthExceedsMaximum,
             NSURLErrorZeroByteResource:
            return true
        default:
            return false
        }
    }

    /// 1s, 2s, 4s, 8s … capped at 30s.
    private static func backoffSeconds(attempt: Int) -> Double {
        min(30, pow(2, Double(attempt - 1)))
    }
}

public enum LocalASRModelDownloadClient {

    public static func makeController(
        destinationURL: URL,
        maxRetries: Int = 4,
        onProgress: @escaping @Sendable (LocalASRDownloadProgressUpdate) -> Void
    ) -> LocalASRModelDownloadController {
        LocalASRModelDownloadController(
            destinationURL: destinationURL,
            maxRetries: maxRetries,
            onProgress: onProgress
        )
    }
}

#endif
