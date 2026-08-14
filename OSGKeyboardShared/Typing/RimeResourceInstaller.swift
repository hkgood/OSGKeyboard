// RimeResourceInstaller.swift
// OSGKeyboard · Shared
//
// The host app owns Rime deployment. The keyboard extension only opens
// an already-built session, keeping expensive maintenance work out of
// the extension's constrained lifecycle.

import Foundation
import Darwin

public enum RimeResourceError: LocalizedError {
    case appGroupUnavailable
    case bundledResourceMissing(String)
    case lockUnavailable
    case deploymentFailed
    case resourcesNotInstalled
    case hostAppRequired

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "App Group 不可用"
        case .bundledResourceMissing(let name):
            return "缺少输入法资源：\(name)"
        case .lockUnavailable:
            return "输入法资源正在被其他进程更新"
        case .deploymentFailed:
            return "输入法资源部署失败"
        case .resourcesNotInstalled:
            return "请先打开 OSGKeyboard 完成输入法初始化"
        case .hostAppRequired:
            return "输入法资源只能由 OSGKeyboard 主应用部署"
        }
    }

    /// Whether opening the host app can actually resolve this failure. Only
    /// host-side deployment fixes missing or broken resources; App Group and
    /// lock failures resolve on their own.
    public var isResolvedByHostDeployment: Bool {
        switch self {
        case .resourcesNotInstalled, .deploymentFailed, .bundledResourceMissing,
             .hostAppRequired:
            return true
        case .appGroupUnavailable, .lockUnavailable:
            return false
        }
    }
}

public struct RimeResourcePaths: Sendable {
    public let root: URL
    public let sharedData: URL
    public let userData: URL
    public let lockFile: URL

    public static func resolve() throws -> RimeResourcePaths {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) else {
            throw RimeResourceError.appGroupUnavailable
        }
        let root = container.appendingPathComponent("Rime", isDirectory: true)
        return RimeResourcePaths(
            root: root,
            sharedData: root.appendingPathComponent("SharedSupport", isDirectory: true),
            userData: root.appendingPathComponent("UserData", isDirectory: true),
            lockFile: root.appendingPathComponent(".deployment.lock")
        )
    }
}

public actor RimeResourceInstaller {
    public static let shared = RimeResourceInstaller()
    /// Bump when SharedSupport layout / schema / import_tables contract changes.
    public static let resourceVersion = "2.4.0"

    public init() {}

    public static var isReady: Bool {
        guard TypingInputConfiguration.installedResourceVersion() == resourceVersion,
              let paths = try? RimeResourcePaths.resolve() else {
            return false
        }
        return FileManager.default.fileExists(
            atPath: paths.userData.appendingPathComponent("build").path
        )
    }

    /// Full deployment is forbidden inside an app-extension process. Keeping
    /// this check beside the heavy operation makes the host-only contract
    /// enforceable even though the readiness API lives in the shared framework.
    public static var canDeployInCurrentProcess: Bool {
        canDeploy(bundleURL: Bundle.main.bundleURL)
    }

    static func canDeploy(bundleURL: URL) -> Bool {
        bundleURL.pathExtension.lowercased() != "appex"
    }

    /// Installs source data and asks librime to prebuild schemas. Call only
    /// from the host app, never from the keyboard extension.
    ///
    /// Redeploys when `force` is set, the resource version is stale, or the
    /// PersonalDictionary sidecar fingerprint changed.
    public func installIfNeeded(
        configuration: TypingInputConfigurationSnapshot,
        personalDictionary: PersonalDictionary? = nil,
        force: Bool = false
    ) throws {
        guard Self.canDeployInCurrentProcess else {
            throw RimeResourceError.hostAppRequired
        }

        let dictionary = personalDictionary ?? AppGroupStore().personalDictionary
        let personalYAML = try Self.makePersonalDictionaryYAML(from: dictionary)
        let personalFingerprint = RimePersonalDictionaryExporter.fingerprint(of: personalYAML)
        let personalChanged =
            TypingInputConfiguration.installedPersonalDictionaryFingerprint() != personalFingerprint

        if !force, Self.isReady, !personalChanged { return }

        let paths = try RimeResourcePaths.resolve()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.userData, withIntermediateDirectories: true)

        let descriptor = open(paths.lockFile.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw RimeResourceError.lockUnavailable }
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw RimeResourceError.lockUnavailable
        }

        let staging = paths.root.appendingPathComponent(
            "SharedSupport.staging-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        guard let pinyinSource = Self.bundledURL(forResource: "osg_pinyin.dict", withExtension: "yaml") else {
            throw RimeResourceError.bundledResourceMissing("osg_pinyin.dict.yaml")
        }
        let baseline = try String(contentsOf: pinyinSource, encoding: .utf8)
        let patched = RimePersonalDictionaryExporter.injectingImportTables(into: baseline)
        try patched.write(
            to: staging.appendingPathComponent("osg_pinyin.dict.yaml"),
            atomically: true,
            encoding: .utf8
        )

        guard let manifestSource = Self.bundledURL(forResource: "manifest", withExtension: "json") else {
            throw RimeResourceError.bundledResourceMissing("manifest.json")
        }
        try fileManager.copyItem(
            at: manifestSource,
            to: staging.appendingPathComponent("manifest.json")
        )

        try personalYAML.write(
            to: staging.appendingPathComponent(
                "\(RimePersonalDictionaryExporter.dictionaryName).dict.yaml"
            ),
            atomically: true,
            encoding: .utf8
        )

        try RimeSchemaGenerator.defaultConfiguration().write(
            to: staging.appendingPathComponent("default.yaml"),
            atomically: true,
            encoding: .utf8
        )
        for schema in TypingInputSchema.allCases {
            try RimeSchemaGenerator.schema(
                for: schema,
                fuzzyPairs: configuration.fuzzyPairs
            ).write(
                to: staging.appendingPathComponent("\(schema.rawValue).schema.yaml"),
                atomically: true,
                encoding: .utf8
            )
        }

        if fileManager.fileExists(atPath: paths.sharedData.path) {
            try fileManager.removeItem(at: paths.sharedData)
        }
        try fileManager.moveItem(at: staging, to: paths.sharedData)

        let bridge = OSGRimeBridge(
            sharedDataDirectory: paths.sharedData.path,
            userDataDirectory: paths.userData.path,
            distributionVersion: Self.resourceVersion
        )
        do {
            // Version bumps already rebuild SharedSupport from scratch; skip the
            // heavier full integrity pass unless the caller forced a redeploy.
            try bridge.deploy(withFullCheck: force)
        } catch {
            bridge.finalizeRuntime()
            throw error
        }
        bridge.finalizeRuntime()

        TypingInputConfiguration.setInstalledResourceVersion(Self.resourceVersion)
        TypingInputConfiguration.setInstalledPersonalDictionaryFingerprint(personalFingerprint)
    }

    private static func makePersonalDictionaryYAML(
        from dictionary: PersonalDictionary
    ) throws -> String {
        guard let pinyinSource = bundledURL(forResource: "osg_pinyin.dict", withExtension: "yaml") else {
            throw RimeResourceError.bundledResourceMissing("osg_pinyin.dict.yaml")
        }
        let annotator = try RimePinyinAnnotator.load(from: pinyinSource)
        return RimePersonalDictionaryExporter.yaml(from: dictionary, annotator: annotator)
    }

    public func syncUserData() throws {
        let paths = try RimeResourcePaths.resolve()
        let bridge = OSGRimeBridge(
            sharedDataDirectory: paths.sharedData.path,
            userDataDirectory: paths.userData.path,
            distributionVersion: Self.resourceVersion
        )
        try bridge.start()
        // Destroying the session and finalizing librime flushes LevelDB
        // user dictionaries. `sync_user_data` is for external Rime sync
        // deployments and is intentionally not needed here.
        bridge.finalizeRuntime()
    }

    /// Deletes librime user dictionaries under `UserData`, keeping `build/`
    /// so `isReady` stays true. Host-only: the keyboard must not race LevelDB.
    public func clearUserDictionary() throws {
        guard Self.canDeployInCurrentProcess else {
            throw RimeResourceError.hostAppRequired
        }
        let paths = try RimeResourcePaths.resolve()
        try Self.removeUserDictionaries(in: paths.userData)
    }

    /// Testable file-level wipe. Matches LevelDB folders like `osg_pinyin.userdb`.
    nonisolated public static func removeUserDictionaries(
        in userData: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: userData.path) else { return }
        let names = try fileManager.contentsOfDirectory(atPath: userData.path)
        for name in names where name.lowercased().contains("userdb") {
            try fileManager.removeItem(at: userData.appendingPathComponent(name))
        }
    }
}

extension RimeResourceInstaller {
    /// Host app owns the dictionary YAML; prefer `Bundle.main`, fall back to
    /// the Shared token bundle for unit tests that inject fixtures.
    fileprivate static func bundledURL(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return Bundle(for: RimeResourceBundleToken.self).url(
            forResource: name,
            withExtension: ext
        )
    }
}

private final class RimeResourceBundleToken: NSObject {}
