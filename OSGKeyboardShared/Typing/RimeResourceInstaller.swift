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
    public static let resourceVersion = "2.3.0"

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
        AppGroupConfigDarwin.postConfigChanged()
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
