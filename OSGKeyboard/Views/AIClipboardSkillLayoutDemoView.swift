// AIClipboardSkillLayoutDemoView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// Interactive layout preview of AI Agent clipboard skills on the real
// `AIKeyboardView`. Launch with `--ai-skills-demo` and optional
// `--skills-count=N` (1...8).

#if DEBUG
import SwiftUI
import OSGKeyboardShared

struct AIClipboardSkillLayoutDemoView: View {
    @StateObject private var state = KeyboardState()
    @StateObject private var typing = TypingSessionController()
    @State private var count: Int = Self.initialCount

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
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .preferredColorScheme(.light)
        .onAppear { apply(count) }
        .onChange(of: count) { _, newValue in apply(newValue) }
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

    private func apply(_ count: Int) {
        let clamped = min(max(count, 1), 8)
        AIKeyboardView.debugPreviewSkills = Self.previewSkills(count: clamped)
        state.surface = .ai
        state.aiServiceAvailable = true
        state.micDisabled = false
        state.layoutWidth = 390
        state.usesIPadLayoutMetrics = false
        state.clipboardHistoryEnabled = true
        state.enabledClipboardSkillIDs = Array(
            AIClipboardSkillCatalog.catalog.map(\.id).prefix(clamped)
        )
        state.aiSession.enter()
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
            ),
        ]
        extras = Array(extras.prefix(count - catalog.count))
        return catalog + extras
    }
}
#endif
