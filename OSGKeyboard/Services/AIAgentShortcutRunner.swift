// AIAgentShortcutRunner.swift
// OSGKeyboard · Main App
//
// Consumes the keyboard's pending export-skill payload. Navigate opens a
// map URL in the host. Other exports open the companion Shortcut.

import OSGKeyboardShared
import UIKit

enum AIAgentShortcutRunner {
    /// `onReminders` / `onEvents` receive the parsed payload for the built-in
    /// native Reminders / Calendar skills so the caller can drive EventKit +
    /// present UI. `onEvents` gets the canonical `start|end|title|location`
    /// lines (decoded host-side by `AIEventExporter`). Other exports still open
    /// their companion Shortcut here.
    @MainActor
    static func runPendingIfNeeded(
        onReminders: ([String]) -> Void = { _ in },
        onEvents: ([String]) -> Void = { _ in }
    ) {
        AIAgentShortcutRun.trace("host.runPending begin")
        let store = AppGroupStore()
        guard let payload = store.consumePendingShortcutRun() else { return }
        guard let skill = store.resolvedAgentSkillCatalog.first(where: { $0.id == payload.skillID }) else {
            AIAgentShortcutRun.trace(
                "host.runPending skip unknownSkill=\(payload.skillID)"
            )
            return
        }
        if skill.id == AIClipboardSkillCatalog.navigateID {
            openMap(for: payload)
            return
        }
        if skill.id == AIClipboardSkillCatalog.extractTodosID {
            AIAgentShortcutRun.trace("host.runPending nativeReminders items=\(payload.titles.count)")
            onReminders(payload.titles)
            return
        }
        if skill.id == AIClipboardSkillCatalog.extractEventsID {
            AIAgentShortcutRun.trace("host.runPending nativeCalendar items=\(payload.titles.count)")
            onEvents(payload.titles)
            return
        }
        guard let name = skill.shortcutName else {
            AIAgentShortcutRun.trace(
                "host.runPending skip missingShortcut skill=\(payload.skillID)"
            )
            return
        }
        let text = payload.joinedTitles
        AIAgentShortcutRun.traceBody("host.titlesToShortcut", text)
        guard let url = shortcutsURL(name: name, text: text) else {
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

    /// 高德 → 百度 → Apple Maps. Do not bounce through Shortcuts.
    private static func openMap(for payload: AIAgentShortcutRunPayload) {
        guard let urlString = AIMapNavigation.shortcutInput(
            from: payload.joinedTitles,
            canOpen: { UIApplication.shared.canOpenURL($0) }
        ), let url = URL(string: urlString) else {
            AIAgentShortcutRun.trace("host.runPending skip navigateURLBuildFailed")
            return
        }
        AIAgentShortcutRun.trace(
            "host.openMap scheme=\(url.scheme ?? "") host=\(url.host ?? "")"
        )
        AIAgentShortcutRun.traceBody("host.mapURL", urlString)
        UIApplication.shared.open(url) { success in
            AIAgentShortcutRun.trace("host.openMap result success=\(success)")
        }
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
