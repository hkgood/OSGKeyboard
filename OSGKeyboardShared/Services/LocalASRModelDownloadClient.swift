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
    private var delegateSession: URLSession!

    // Every field below is reachable from BOTH the caller's thread
    // (`download` / `pause` / `resumeFromPause` / `cancel`) and URLSession's
    // delegate queue (`delegateQueue: nil` = a private serial background
    // queue), so all of them are guarded by `lock`. That is what makes the
    // `@unchecked Sendable` above true rather than aspirational: an unguarded
    // check-then-act on `finished` let two threads each resume
    // `completionContinuation`, and a checked continuation resumed twice is a
    // hard crash, not a recoverable error.
    private let lock = NSLock()
    private var remoteURL: URL?
    private var task: URLSessionDownloadTask?
    private var completionContinuation: CheckedContinuation<Void, Error>?
    private var isPausing = false
    private var finished = false
    private var retryCount = 0
    /// Set by `cancel()` before it invalidates the session. `startTask` refuses
    /// to build a task once this is set: `URLSession.downloadTask` on an
    /// invalidated session raises an ObjC exception, which Swift cannot catch.
    private var sessionInvalidated = false

    init(
        destinationURL: URL,
        maxRetries: Int = 4,
        onProgress: @escaping @Sendable (LocalASRDownloadProgressUpdate) -> Void
    ) {
        self.destinationURL = destinationURL
        self.maxRetries = maxRetries
        self.onProgress = onProgress
        super.init()
        let config = URLSessionConfiguration.default
        // Big weight files over flaky links: allow long total transfers but
        // fail (and retry) a stalled connection that goes quiet for a while.
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 24 * 60 * 60
        config.waitsForConnectivity = true
        // Built here rather than in a `lazy var`: lazy initialization is not
        // atomic, and this session is first touched from whichever thread wins
        // the `startTask` / `cancel` race.
        delegateSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Atomically takes ownership of the pending completion continuation and
    /// marks the download finished. Returns `nil` when another thread already
    /// claimed it — the single guarantee that `download(from:)` is resumed
    /// exactly once, no matter how cancel / completion / failure interleave.
    private func claimCompletion() -> CheckedContinuation<Void, Error>? {
        lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard !finished else { return nil }
            finished = true
            let pending = completionContinuation
            completionContinuation = nil
            return pending
        }
    }

    /// Runs until the archive is fully written to `destinationURL` (survives pause/resume).
    public func download(from remoteURL: URL) async throws {
        // A controller is single-use — `LocalASRModelDownloadClient.makeController`
        // builds a fresh one per download. `finished` is deliberately NOT reset
        // here: doing so would resurrect a controller already settled by
        // `cancel()`, and `startTask` would then hand work to a session that
        // `cancel()` had invalidated (an uncatchable ObjC exception).
        lock.withLock {
            self.remoteURL = remoteURL
            retryCount = 0
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // `cancel()` can land between the setup above and here; parking a
            // continuation nobody will ever resume would hang the caller.
            let alreadyCancelled = lock.withLock { () -> Bool in
                guard !finished else { return true }
                completionContinuation = continuation
                return false
            }
            guard !alreadyCancelled else {
                continuation.resume(throwing: CancellationError())
                return
            }
            startTask(resumeData: nil)
        }
    }

    public func pause() async throws -> Data {
        let pending = lock.withLock { () -> URLSessionDownloadTask? in
            guard let running = task, !finished, !isPausing else { return nil }
            isPausing = true
            return running
        }
        guard let pending else {
            throw LocalASRModelManagerError.downloadFailed("No active download to pause.")
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pending.cancel(byProducingResumeData: { [weak self] data in
                guard let self else {
                    continuation.resume(
                        throwing: LocalASRModelManagerError.downloadFailed("Pause failed.")
                    )
                    return
                }
                if let data {
                    // `isPausing` deliberately stays set until `resumeFromPause`
                    // / `cancel` clears it. Cancelling for resume data also
                    // fires `didCompleteWithError`, and that callback can land
                    // either side of this one — clearing the flag here (as this
                    // used to) let the cancellation be misread as a permanent
                    // failure, tearing down a download the user only paused.
                    continuation.resume(returning: data)
                    return
                }
                // No resume data: the task is dead and cannot be continued, and
                // the `didCompleteWithError` that would normally report it was
                // suppressed by `isPausing`. Settle `download(from:)` here so
                // it cannot hang waiting for a callback that already passed.
                self.lock.withLock { self.isPausing = false }
                let failure = LocalASRModelManagerError.downloadFailed("Pause failed.")
                self.claimCompletion()?.resume(throwing: failure)
                continuation.resume(throwing: failure)
            })
        }
    }

    /// Continues a paused download; `download(from:)` must still be awaiting.
    public func resumeFromPause(_ resumeData: Data) {
        // Only a genuinely paused download may continue. `finished` is NOT
        // reset: a completed or cancelled download must never be revived, and
        // pausing no longer sets it in the first place.
        let canResume = lock.withLock { () -> Bool in
            guard isPausing, !finished else { return false }
            isPausing = false
            return true
        }
        guard canResume else { return }
        startTask(resumeData: resumeData)
    }

    public func cancel() {
        let pending = lock.withLock { () -> URLSessionDownloadTask? in
            isPausing = false
            // Flagged under the same lock `startTask` takes, so the two are
            // totally ordered: either the task is built first (and cancelled
            // just below), or `startTask` sees this and builds nothing.
            sessionInvalidated = true
            return task
        }
        // Claim before cancelling the task: the cancellation then arrives at
        // `didCompleteWithError` already settled, so it cannot re-report the
        // download as a generic network failure.
        claimCompletion()?.resume(throwing: CancellationError())
        pending?.cancel()
        delegateSession.invalidateAndCancel()
    }

    private func startTask(resumeData: Data?) {
        let started = lock.withLock { () -> URLSessionDownloadTask? in
            guard !sessionInvalidated else { return nil }
            let created: URLSessionDownloadTask?
            if let resumeData {
                created = delegateSession.downloadTask(withResumeData: resumeData)
            } else if let remoteURL {
                created = delegateSession.downloadTask(with: remoteURL)
            } else {
                created = nil
            }
            task = created
            return created
        }
        started?.resume()
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
        // Claim first: a cancelled download must not have its archive moved
        // into place, and claiming is what stops the `didCompleteWithError`
        // that follows every finished download from resuming us a second time.
        guard let pending = claimCompletion() else { return }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: location, to: destinationURL)
            pending.resume()
        } catch {
            pending.resume(
                throwing: LocalASRModelManagerError.downloadFailed(error.localizedDescription)
            )
        }
        session.finishTasksAndInvalidate()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // `isPausing` means the cancellation below is the one *we* asked for in
        // `pause()`; the download is not over and must keep its continuation.
        let (suppressed, shouldRetry, delay) = lock.withLock { () -> (Bool, Bool, Double) in
            let suppressed = finished || isPausing
            guard let error, !suppressed, Self.isRetryable(error), retryCount < maxRetries else {
                return (suppressed, false, 0)
            }
            retryCount += 1
            return (suppressed, true, Self.backoffSeconds(attempt: retryCount))
        }

        if suppressed { return }
        guard let error else { return }

        // Transient network drop: resume from where we stopped (if the server
        // handed back resume data) after a short exponential backoff, up to a cap.
        if shouldRetry {
            let resumeData = (error as NSError)
                .userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                let stillActive = self.lock.withLock { !self.finished && !self.isPausing }
                guard stillActive else { return }
                self.startTask(resumeData: resumeData)
            }
            return
        }

        guard let pending = claimCompletion() else { return }
        pending.resume(throwing: LocalASRModelManagerError.downloadFailed(error.localizedDescription))
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
