// CrashDiagnosticsService.swift
// OSGKeyboard · Main App
//
// The app previously had NO crash visibility of any kind: no third-party SDK,
// no MetricKit subscriber, no uncaught-exception handler. Two consequences
// mattered in practice:
//
//   1. Keyboard-extension jetsams (the ~60 MiB memory ceiling) are the single
//      most likely way a user loses the keyboard mid-sentence, and they are
//      NOT reported as crashes in App Store Connect — they never reached us
//      at all.
//   2. Every crash report had to come from a user manually describing it.
//
// MetricKit closes both gaps without a third-party SDK and without shipping
// user content anywhere: iOS hands the containing app diagnostics for itself
// AND its extensions, on next launch, already anonymised. Memory kills arrive
// here as crash diagnostics with an `EXC_RESOURCE` exception type.
//
// Reports are written into the SAME App Group diagnostics directory that Flow
// startup failures use, so Settings ▸ Diagnostics lists, exports and clears
// them with the existing UI, and the existing retention/size budget applies.
//
// On App Store builds they stay on device, full stop. On INTERNAL builds (local
// Debug and TestFlight) `InternalDiagnosticsUploader` also sends them to the
// account service — see that file for why the split exists.

import Foundation
import MetricKit
import OSGKeyboardShared

/// Subscribes to MetricKit and turns crash / hang diagnostics into local,
/// exportable reports. Install once, at app launch.
public final class CrashDiagnosticsService: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    public static let shared = CrashDiagnosticsService()

    /// Cap on the serialized call stack kept per diagnostic. Full trees run to
    /// hundreds of KB and the diagnostics directory has a 4 MiB total budget
    /// shared with Flow reports; the top frames are what identifies a crash.
    private static let maxCallStackDigestLength = 4_000
    private static let maxTopFrames = 12
    /// A crash loop can put a whole day of repeats in one payload. Keeping the
    /// newest few per kind stops it from evicting every other report.
    private static let maxDiagnosticsPerKind = 5
    /// Matches the account service's `terminationReason` column.
    static let maxTerminationReasonLength = 255

    private let makeStore: @Sendable (FlowDiagnosticsProcess) -> FlowFailureLogStore
    private let lock = NSLock()
    private var isSubscribed = false
    private var storesByProcess: [FlowDiagnosticsProcess: FlowFailureLogStore] = [:]

    public init(
        makeStore: @escaping @Sendable (FlowDiagnosticsProcess) -> FlowFailureLogStore = { process in
            // A fresh store per process kind: `FlowFailureLogStore.shared`
            // carries THIS session's live breadcrumbs, which have nothing to do
            // with a crash that happened before the last launch. An empty
            // window is the honest one.
            FlowFailureLogStore(process: process)
        }
    ) {
        self.makeStore = makeStore
        super.init()
    }

    /// Idempotent — safe to call from every launch path.
    public func start() {
        let shouldSubscribe = lock.withLock {
            guard !isSubscribed else { return false }
            isSubscribed = true
            return true
        }
        guard shouldSubscribe else { return }
        MXMetricManager.shared.add(self)
        OSGDiag.log("crashDiagnostics subscribed", category: "diagnostics")
    }

    public func stop() {
        let shouldRemove = lock.withLock {
            guard isSubscribed else { return false }
            isSubscribed = false
            return true
        }
        guard shouldRemove else { return }
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    /// Daily aggregate metrics (launch time, hang rate, memory). Not used yet —
    /// diagnostics are what turn "the keyboard disappeared" into evidence.
    public func didReceive(_ payloads: [MXMetricPayload]) {}

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var storedAny = false
        for payload in payloads {
            storedAny = persist(payload) || storedAny
        }
        guard storedAny else { return }
        // Internal builds only; a no-op elsewhere. Detached because MetricKit
        // calls back on its own queue and must not be made to wait on network.
        Task.detached(priority: .utility) {
            await InternalDiagnosticsUploader.shared.uploadPendingReports()
        }
    }

    // MARK: - Persistence

    @discardableResult
    private func persist(_ payload: MXDiagnosticPayload) -> Bool {
        // `ISO8601FormatStyle` is a Sendable value type; a shared
        // `ISO8601DateFormatter` static would not be, and MetricKit calls back
        // on an unspecified queue.
        let window = [
            "windowBegin": payload.timeStampBegin.formatted(.iso8601),
            "windowEnd": payload.timeStampEnd.formatted(.iso8601)
        ]

        var storedAny = false

        for diagnostic in (payload.crashDiagnostics ?? []).prefix(Self.maxDiagnosticsPerKind) {
            var context = window
            context["exceptionType"] = Self.identifier(diagnostic.exceptionType?.stringValue)
            context["exceptionCode"] = Self.identifier(diagnostic.exceptionCode?.stringValue)
            context["signal"] = Self.identifier(diagnostic.signal?.stringValue)
            context["terminationReason"] = diagnostic.terminationReason.map {
                String($0.prefix(Self.maxTerminationReasonLength))
            }
            context["virtualMemoryRegionInfo"] = diagnostic.virtualMemoryRegionInfo.map {
                String($0.prefix(Self.maxTerminationReasonLength))
            }
            storedAny = write(
                kind: "crash",
                reason: Self.crashReason(diagnostic),
                context: context,
                metaData: diagnostic.metaData,
                callStackTree: diagnostic.callStackTree
            ) || storedAny
        }

        for diagnostic in (payload.hangDiagnostics ?? []).prefix(Self.maxDiagnosticsPerKind) {
            var context = window
            let seconds = diagnostic.hangDuration.converted(to: .seconds).value
            context["hangMillis"] = String(Int((seconds * 1_000).rounded()))
            storedAny = write(
                kind: "hang",
                reason: String(format: "hang %.1fs", seconds),
                context: context,
                metaData: diagnostic.metaData,
                callStackTree: diagnostic.callStackTree
            ) || storedAny
        }

        for diagnostic in (payload.cpuExceptionDiagnostics ?? []).prefix(Self.maxDiagnosticsPerKind) {
            var context = window
            context["cpuSeconds"] = String(
                format: "%.1f",
                diagnostic.totalCPUTime.converted(to: .seconds).value
            )
            context["sampledSeconds"] = String(
                format: "%.1f",
                diagnostic.totalSampledTime.converted(to: .seconds).value
            )
            storedAny = write(
                kind: "cpuException",
                reason: "cpu exception",
                context: context,
                metaData: diagnostic.metaData,
                callStackTree: diagnostic.callStackTree
            ) || storedAny
        }

        for diagnostic in (payload.diskWriteExceptionDiagnostics ?? []).prefix(Self.maxDiagnosticsPerKind) {
            var context = window
            context["writesCausedMB"] = String(
                format: "%.1f",
                diagnostic.totalWritesCaused.converted(to: .megabytes).value
            )
            storedAny = write(
                kind: "diskWriteException",
                reason: "disk write exception",
                context: context,
                metaData: diagnostic.metaData,
                callStackTree: diagnostic.callStackTree
            ) || storedAny
        }

        return storedAny
    }

    @discardableResult
    private func write(
        kind: String,
        reason: String,
        context: [String: String],
        metaData: MXMetaData,
        callStackTree: MXCallStackTree
    ) -> Bool {
        var merged = context
        merged["kind"] = kind
        merged["source"] = "metricKit"
        // The upload contract constrains these to `[A-Za-z0-9._+-]{1,32}`, and
        // MetricKit does not respect that: `osVersion` reads like
        // "iPhone OS 26.0 (23A123)" and `deviceType` like "iPhone17,1". Sanitise
        // at the point of capture so the stored report and the uploaded one
        // never disagree.
        merged["osVersion"] = Self.identifier(metaData.osVersion)
        merged["deviceType"] = Self.identifier(metaData.deviceType)
        merged["appBuild"] = Self.identifier(metaData.applicationBuildVersion)
        merged["platformArchitecture"] = Self.identifier(metaData.platformArchitecture)

        let frames = Self.topBinaryNames(callStackTree)
        if !frames.isEmpty {
            merged["topBinaries"] = frames.joined(separator: ",")
        }
        if let digest = Self.callStackDigest(callStackTree) {
            merged["callStackDigest"] = digest
        }

        // Which process died. MetricKit delivers extension diagnostics to the
        // containing app, so without this every keyboard crash would be filed
        // under "host" and the Settings breakdown would lie.
        let process = Self.originProcess(metaData: metaData, binaries: frames)
        merged["processBundleID"] = metaData.bundleIdentifier

        let store = lock.withLock { () -> FlowFailureLogStore in
            if let existing = storesByProcess[process] { return existing }
            let created = makeStore(process)
            storesByProcess[process] = created
            return created
        }
        let storedURL = store.persistStartupFailure(
            reason: "metrickit.\(kind): \(reason)",
            context: merged
        )
        OSGDiag.log(
            "crashDiagnostics stored=\(storedURL != nil ? 1 : 0) kind=\(kind) "
                + "process=\(process.rawValue) reason=\(reason)",
            category: "diagnostics"
        )
        return storedURL != nil
    }

    // MARK: - Extraction

    /// Reduces a free-form MetricKit string to the `[A-Za-z0-9._+-]{1,32}`
    /// shape the account service accepts for release identifiers. Returns `nil`
    /// when nothing usable survives, so the field is simply omitted.
    static func identifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            .union(CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"))
            .union(CharacterSet(charactersIn: "0123456789._+-"))
        let mapped = String(
            String.UnicodeScalarView(
                value.unicodeScalars.map { allowed.contains($0) ? $0 : "-" }
            )
        )
        // Collapse runs introduced by the substitution so "iPhone OS 26.0 (23A)"
        // does not become a wall of dashes.
        var collapsed = ""
        var lastWasDash = false
        for character in mapped {
            let isDash = character == "-"
            if isDash && lastWasDash { continue }
            collapsed.append(character)
            lastWasDash = isDash
        }
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(32))
    }

    private static func crashReason(_ diagnostic: MXCrashDiagnostic) -> String {
        var parts: [String] = []
        if let type = diagnostic.exceptionType {
            parts.append("exc=\(type)")
        }
        if let signal = diagnostic.signal {
            parts.append("signal=\(signal)")
        }
        if let termination = diagnostic.terminationReason, !termination.isEmpty {
            parts.append(termination)
        }
        return parts.isEmpty ? "crash" : parts.joined(separator: " ")
    }

    /// The keyboard extension's own binary appears in its call stacks. Prefer
    /// the bundle identifier when MetricKit supplies one, and fall back to the
    /// binary names so older payloads are still attributed correctly.
    private static func originProcess(
        metaData: MXMetaData,
        binaries: [String]
    ) -> FlowDiagnosticsProcess {
        let bundleID = metaData.bundleIdentifier
        if !bundleID.isEmpty {
            return bundleID.contains("keyboard") || bundleID.hasSuffix(".OSGKeyboardExt")
                ? .keyboard
                : .host
        }
        return binaries.contains(where: { $0.localizedCaseInsensitiveContains("OSGKeyboardExt") })
            ? .keyboard
            : .host
    }

    /// Depth-first walk of the call stack tree collecting distinct binary
    /// names, attributed threads first. This is what makes a report readable at
    /// a glance: `OSGKeyboardExt,librime,...` says more than a 300 KB tree.
    private static func topBinaryNames(_ tree: MXCallStackTree) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: tree.jsonRepresentation()),
              let dictionary = root as? [String: Any],
              let stacks = dictionary["callStacks"] as? [[String: Any]] else {
            return []
        }
        let ordered = stacks.sorted { lhs, rhs in
            (lhs["threadAttributed"] as? Bool ?? false)
                && !(rhs["threadAttributed"] as? Bool ?? false)
        }
        var names: [String] = []
        var seen = Set<String>()

        func visit(_ frames: [[String: Any]]) {
            for frame in frames {
                guard names.count < maxTopFrames else { return }
                if let name = frame["binaryName"] as? String, seen.insert(name).inserted {
                    names.append(name)
                }
                if let children = frame["subFrames"] as? [[String: Any]] {
                    visit(children)
                }
            }
        }

        for stack in ordered {
            guard names.count < maxTopFrames else { break }
            visit(stack["callStackRootFrames"] as? [[String: Any]] ?? [])
        }
        return names
    }

    private static func callStackDigest(_ tree: MXCallStackTree) -> String? {
        guard let text = String(data: tree.jsonRepresentation(), encoding: .utf8) else {
            return nil
        }
        guard text.count > maxCallStackDigestLength else { return text }
        return String(text.prefix(maxCallStackDigestLength)) + "…[truncated]"
    }
}
