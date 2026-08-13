// AIAgentShortcutInstaller.swift
// OSGKeyboard · Main App
//
// Opening the HTTPS iCloud share page from the app is claimed as a
// Universal Link and often lands on Gallery. `shortcuts://shortcuts/TOKEN`
// opens the Add sheet in Shortcuts directly.

import Foundation
import UIKit
import OSGKeyboardShared

enum AIAgentShortcutInstaller {
    static let bundledResourceName = "OSGExtractTodos"

    @MainActor
    static func openInstallPage(for skill: AIClipboardSkill) {
        if let shareURL = skill.shortcutICloudURL,
           let installURL = AIAgentShortcutRun.shortcutsInstallURL(from: shareURL) {
            UIApplication.shared.open(installURL)
            return
        }
        openBundledShortcut()
    }

    @MainActor
    private static func openBundledShortcut() {
        guard let bundled = Bundle.main.url(
            forResource: bundledResourceName,
            withExtension: "shortcut"
        ) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AIClipboardSkillCatalog.extractTodosShortcutName).shortcut")
        try? FileManager.default.removeItem(at: tmp)
        do {
            try FileManager.default.copyItem(at: bundled, to: tmp)
            UIApplication.shared.open(tmp)
        } catch {
            UIApplication.shared.open(bundled)
        }
    }
}
