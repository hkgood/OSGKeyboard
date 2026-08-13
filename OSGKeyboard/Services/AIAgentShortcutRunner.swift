// AIAgentShortcutRunner.swift
// OSGKeyboard · Main App
//
// Consumes the keyboard's pending extract-todos payload and opens the
// companion Shortcut. Release builds stay in Shortcuts. DEBUG builds add
// x-callback URLs so Console can record success / error / cancel.

import UIKit
import OSGKeyboardShared

enum AIAgentShortcutRunner {
    @MainActor
    static func runPendingIfNeeded() {
        AIAgentShortcutRun.trace("host.runPending begin")
        guard let payload = AppGroupStore().consumePendingShortcutRun() else { return }
        guard let skill = AIClipboardSkillCatalog.skill(id: payload.skillID),
              let name = skill.shortcutName else {
            AIAgentShortcutRun.trace(
                "host.runPending skip unknownSkill=\(payload.skillID)"
            )
            return
        }
        AIAgentShortcutRun.traceBody("host.titlesToShortcut", payload.joinedTitles)
        guard let url = shortcutsURL(name: name, text: payload.joinedTitles) else {
            AIAgentShortcutRun.trace("host.runPending skip URLBuildFailed name=\(name)")
            return
        }
        let textItem = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "text" }?
            .value
        AIAgentShortcutRun.trace(
            "host.openShortcuts scheme=\(url.scheme ?? "") host=\(url.host ?? "") "
                + "path=\(url.path) urlChars=\(url.absoluteString.count) "
                + "textQueryChars=\(textItem?.count ?? -1) name=\(name)"
        )
        AIAgentShortcutRun.traceBody("host.textQuery", textItem ?? "")
        UIApplication.shared.open(url) { success in
            AIAgentShortcutRun.trace(
                "host.openShortcuts result success=\(success) "
                    + "(iOS accepted the URL; not proof Reminders were created)"
            )
        }
    }

    static func logShortcutCallback(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let status = items.first { $0.name == "status" }?.value ?? "unknown"
        let errorMessage = items.first { $0.name == "errorMessage" }?.value
        let errorCode = items.first { $0.name == "errorCode" }?.value
        AIAgentShortcutRun.trace(
            "host.shortcutCallback status=\(status) errorCode=\(errorCode ?? "-") "
                + "errorMessage=\(errorMessage ?? "-") "
                + "(Shortcuts finished; does not prove reminder rows exist)"
        )
    }

    private static func shortcutsURL(name: String, text: String) -> URL? {
        #if DEBUG
        return AIAgentShortcutRun.shortcutsRunURL(
            name: name,
            text: text,
            xSuccess: "osgkeyboard://skill/shortcut-result?status=success",
            xError: "osgkeyboard://skill/shortcut-result?status=error",
            xCancel: "osgkeyboard://skill/shortcut-result?status=cancel"
        )
        #else
        return AIAgentShortcutRun.shortcutsRunURL(name: name, text: text)
        #endif
    }
}
