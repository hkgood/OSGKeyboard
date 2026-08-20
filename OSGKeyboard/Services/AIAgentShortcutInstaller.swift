// AIAgentShortcutInstaller.swift
// OSGKeyboard · Main App
//
// Opening the HTTPS iCloud share page from the app is claimed as a
// Universal Link and often lands on Gallery. `shortcuts://shortcuts/TOKEN`
// opens the Add sheet in Shortcuts directly.

import Foundation
import OSGKeyboardShared
import UIKit

enum AIAgentShortcutInstaller {
    @MainActor
    static func openInstallPage(for skill: AIClipboardSkill) {
        if let shareURL = skill.shortcutICloudURL,
           let installURL = AIAgentShortcutRun.shortcutsInstallURL(from: shareURL) {
            UIApplication.shared.open(installURL)
            return
        }
        openBundledShortcut(for: skill)
    }

    @MainActor
    private static func openBundledShortcut(for skill: AIClipboardSkill) {
        guard let resource = skill.shortcutResourceName,
              let bundled = Bundle.main.url(
                forResource: resource,
                withExtension: "shortcut"
              ) else { return }
        let fileName = skill.shortcutName ?? resource
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).shortcut")
        try? FileManager.default.removeItem(at: tmp)
        do {
            try FileManager.default.copyItem(at: bundled, to: tmp)
            UIApplication.shared.open(tmp)
        } catch {
            UIApplication.shared.open(bundled)
        }
    }
}
