// AIClipboardSkillLayoutDemoView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// Interactive layout preview and What's New recording host for AI Agent
// clipboard skills on the real unified `AIKeyboardView`. Launch with
// `--ai-skills-demo`, optional `--skills-count=N` (1...8), and optional
// `--whats-new-lang=zh|en`.

#if DEBUG
import OSGKeyboardShared
import SwiftUI

struct AIClipboardSkillLayoutDemoView: View {
    @StateObject private var config = ProviderConfig.shared
    @StateObject private var state = KeyboardState()
    @StateObject private var typing = TypingSessionController()
    @State private var count: Int = Self.initialCount

    init() {
        AIKeyboardView.debugSkipsLongPressCoach = true
        AIKeyboardView.debugKeepsSkillTip = true
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Spacer(minLength: 0)
            AIKeyboardView(
                state: state,
                typing: typing,
                onInsert: { _ in }
            )
            .background(Palette.light.background)
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea())
        .environment(\.locale, language == .en ? Locale(identifier: "en") : Locale(identifier: "zh-Hans"))
        .preferredColorScheme(.light)
        .task { await runTimeline() }
        .onChange(of: count) { _, newValue in showSkills(newValue) }
        .onDisappear {
            AIKeyboardView.debugPreviewSkills = nil
            AIKeyboardView.debugSkipsLongPressCoach = false
            AIKeyboardView.debugKeepsSkillTip = false
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Text("技能布局预览")
                .font(.headline)
                .foregroundStyle(.white)
            HStack(spacing: 16) {
                Button {
                    count = max(1, count - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                }
                Text("\(count) 个")
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 72)
                Button {
                    count = min(8, count + 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                }
            }
            .foregroundStyle(.green)
            HStack(spacing: 8) {
                ForEach([3, 5, 8], id: \.self) { n in
                    Button("\(n)") {
                        count = n
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(count == n ? .green : .gray)
                }
            }
        }
        .padding(.top, 56)
        .padding(.bottom, 16)
    }

    private func prepareState() {
        config.uiLanguage = language == .en ? .english : .chinese
        AIKeyboardView.debugPreviewSkills = nil
        state.surface = .voice
        state.aiServiceAvailable = true
        state.micDisabled = false
        state.layoutWidth = 390
        state.usesIPadLayoutMetrics = false
        state.clipboardHistoryEnabled = true
        state.undoAvailable = true
        state.editAvailable = true
        state.clipboardSuggestionText = language == .en
            ? "Meeting at 3pm tomorrow"
            : "明天下午三点开会"
        state.skillTipText = language == .en
            ? "Copied text is ready"
            : "复制内容已就绪"
        state.aiSession.enter()
    }

    private func showSkills(_ count: Int) {
        let clamped = min(max(count, 1), 8)
        AIKeyboardView.debugPreviewSkills = Self.previewSkills(count: clamped)
        state.enabledClipboardSkillIDs = Array(
            AIClipboardSkillCatalog.catalog.map(\.id).prefix(clamped)
        )
    }

    private func runTimeline() async {
        prepareState()
        try? await Task.sleep(for: .seconds(3))
        state.clipboardSuggestionText = nil
        state.skillTipText = nil
        showSkills(count)
        try? await Task.sleep(for: .seconds(8))
    }

    private var language: WhatsNewDemoScenario.Language {
        let prefix = "--whats-new-lang="
        guard let argument = ProcessInfo.processInfo.arguments.first(
            where: { $0.hasPrefix(prefix) }
        ) else {
            return .zh
        }
        return WhatsNewDemoScenario.Language(
            rawValue: String(argument.dropFirst(prefix.count))
        ) ?? .zh
    }

    private static var initialCount: Int {
        let prefix = "--skills-count="
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
           let value = Int(arg.dropFirst(prefix.count)),
           (1...8).contains(value) {
            return value
        }
        return 5
    }

    private static func previewSkills(count: Int) -> [AIClipboardSkill] {
        let catalog = AIClipboardSkillCatalog.catalog
        if count <= catalog.count {
            return Array(catalog.prefix(count))
        }
        var extras: [AIClipboardSkill] = [
            AIClipboardSkill(
                id: "preview-polish",
                systemImage: "wand.and.stars",
                titleKey: "keyboard.ai.skill.previewPolish",
                cardTitleKey: "skills.reply.name",
                descriptionKey: "skills.reply.description",
                kind: .transform,
                isDefault: false
            ),
            AIClipboardSkill(
                id: "preview-ideas",
                systemImage: "lightbulb.fill",
                titleKey: "keyboard.ai.skill.previewIdeas",
                cardTitleKey: "skills.summarize.name",
                descriptionKey: "skills.summarize.description",
                kind: .transform,
                isDefault: false
            ),
            AIClipboardSkill(
                id: "preview-tone",
                systemImage: "theatermasks.fill",
                titleKey: "keyboard.ai.skill.previewTone",
                cardTitleKey: "skills.translate.name",
                descriptionKey: "skills.translate.description",
                kind: .transform,
                isDefault: false
            )
        ]
        extras = Array(extras.prefix(count - catalog.count))
        return catalog + extras
    }
}
#endif
