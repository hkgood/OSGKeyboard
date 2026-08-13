// AIAgentSkillsView.swift
// OSGKeyboard · Main App
//
// Catalog of AI Agent clipboard skills. Enabled cards (max 8) appear on
// the keyboard after a copy; long-press drag reorders that row. Export
// skills confirm a companion Shortcut before they can occupy a slot.

import SwiftUI
import UIKit
import OSGKeyboardShared

struct AIAgentSkillsView: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var store = AIAgentSkillLayoutStore.shared

    @State private var viewingSkill: AIClipboardSkill?
    @State private var showFullAlert = false

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                CardPageContent(spacing: Spacing.xl) {
                    if !config.clipboardHistoryEnabled {
                        clipboardHistoryBanner
                    }
                    enabledSection
                    if !store.availableSkills.isEmpty {
                        availableSection
                    }
                }
                .tabBarScrollBottomPadding()
            }
            .background(palette.background)
            .navigationTitle("skills.title")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $viewingSkill) { skill in
            SkillDetailSheet(
                store: store,
                skill: skill,
                onDismiss: { viewingSkill = nil },
                onAddOrWarn: addOrWarn,
                onConfirmInstall: confirmShortcutInstall
            )
        }
        .alert(
            AppL10n.string("skills.full.title", language: config.uiLanguage),
            isPresented: $showFullAlert
        ) {
            Button("common.done") { showFullAlert = false }
        } message: {
            Text(AppL10n.string("skills.full.message", language: config.uiLanguage))
        }
        .onAppear { store.reload() }
    }

    private var clipboardHistoryBanner: some View {
        Text("skills.clipboardHistory.banner")
            .font(TypeStyle.caption)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
    }

    private var enabledSection: some View {
        CardSection(
            title: AppL10n.format(
                "skills.enabled.section",
                language: config.uiLanguage,
                store.enabledSkills.count,
                AIAgentSkillLayout.maximumEnabled
            )
        ) {
            if store.enabledSkills.isEmpty {
                Text("skills.enabled.empty")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.sm) {
                    ForEach(store.enabledSkills) { skill in
                        skillCard(skill, showsEnabledBadge: true)
                            .onTapGesture { viewingSkill = skill }
                            .draggable(skill.id) {
                                skillCard(skill, showsEnabledBadge: true)
                                    .frame(width: 160)
                            }
                            .dropDestination(for: String.self) { items, _ in
                                guard let dragged = items.first else { return false }
                                store.moveEnabled(id: dragged, onto: skill.id)
                                return true
                            }
                    }
                }
            }
        }
    }

    private var availableSection: some View {
        CardSection("skills.available.section") {
            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach(store.availableSkills) { skill in
                    Button {
                        viewingSkill = skill
                    } label: {
                        skillCard(skill, showsEnabledBadge: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func skillCard(_ skill: AIClipboardSkill, showsEnabledBadge: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: skill.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Spacer(minLength: 0)
                if showsEnabledBadge {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            Text(AppL10n.string(skill.cardTitleKey, language: config.uiLanguage))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Text(AppL10n.string(skill.descriptionKey, language: config.uiLanguage))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(Spacing.md)
        .background(
            showsEnabledBadge ? palette.accentMuted : palette.surface,
            in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(
                    showsEnabledBadge ? palette.accent : palette.divider,
                    lineWidth: showsEnabledBadge ? 1.5 : 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func addOrWarn(_ skill: AIClipboardSkill) {
        switch store.enable(skill.id) {
        case .enabled, .alreadyEnabled:
            viewingSkill = nil
        case .full:
            showFullAlert = true
        case .needsShortcut, .unknown:
            break
        }
    }

    private func confirmShortcutInstall(_ skill: AIClipboardSkill) {
        switch store.confirmShortcutAndEnable(skill.id) {
        case .enabled, .alreadyEnabled:
            viewingSkill = nil
        case .full:
            showFullAlert = true
        case .needsShortcut, .unknown:
            break
        }
    }
}

private struct SkillDetailSheet: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var store: AIAgentSkillLayoutStore
    @ObservedObject private var config = ProviderConfig.shared

    let skill: AIClipboardSkill
    let onDismiss: () -> Void
    let onAddOrWarn: (AIClipboardSkill) -> Void
    let onConfirmInstall: (AIClipboardSkill) -> Void

    /// Content stack height; nav chrome is added for the detent.
    @State private var contentHeight: CGFloat = 240
    private let navigationChrome: CGFloat = 56

    var body: some View {
        NavigationStack {
            CardPageContent(
                spacing: Spacing.md,
                topPadding: Spacing.md,
                bottomPadding: Spacing.lg
            ) {
                header
                explanation
                skillActions
            }
            .background(palette.background)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                let next = newHeight + navigationChrome
                if abs(contentHeight - next) > 1 {
                    contentHeight = next
                }
            }
            .navigationTitle("skills.detail.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
        .animation(.easeInOut(duration: 0.2), value: contentHeight)
    }

    private var explanation: some View {
        Text(AppL10n.string(explanationKey, language: config.uiLanguage))
            .font(TypeStyle.body)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80, alignment: .topLeading)
    }

    private var explanationKey: String {
        if skill.requiresShortcut, !store.layout.hasConfirmedShortcut(skill.id) {
            return "skills.install.lead"
        }
        if skill.requiresShortcut, store.layout.isEnabled(skill.id) {
            return "skills.action.turnOffHint"
        }
        return skill.descriptionKey
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: skill.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 36, height: 36)
                .background(palette.accentMuted, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(AppL10n.string(skill.cardTitleKey, language: config.uiLanguage))
                    .font(TypeStyle.title3)
                    .foregroundStyle(palette.textPrimary)
                if skill.isDefault {
                    Text("skills.badge.default")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var skillActions: some View {
        let enabled = store.layout.isEnabled(skill.id)
        if skill.requiresShortcut {
            if !store.layout.hasConfirmedShortcut(skill.id) {
                shortcutInstallBlock
            } else {
                if enabled {
                    fullWidthButton("skills.action.turnOff", prominent: false) {
                        store.disable(skill.id)
                        onDismiss()
                    }
                } else {
                    fullWidthButton("skills.action.addToKeyboard", prominent: true) {
                        onAddOrWarn(skill)
                    }
                }
                fullWidthButton("skills.action.reinstallShortcut", prominent: false) {
                    openShortcutInstall()
                }
            }
        } else if enabled {
            fullWidthButton("skills.action.turnOff", prominent: false) {
                store.disable(skill.id)
                onDismiss()
            }
        } else {
            fullWidthButton("skills.action.addToKeyboard", prominent: true) {
                onAddOrWarn(skill)
            }
        }
    }

    private var shortcutInstallBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            fullWidthButton("skills.install.openShortcuts", prominent: true) {
                openShortcutInstall()
            }
            fullWidthButton("skills.install.confirmAdded", prominent: false) {
                onConfirmInstall(skill)
            }
        }
    }

    @ViewBuilder
    private func fullWidthButton(
        _ titleKey: LocalizedStringKey,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let label = Text(titleKey)
            .frame(maxWidth: .infinity, minHeight: 38)
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
        }
    }

    private func openShortcutInstall() {
        AIAgentShortcutInstaller.openInstallPage(for: skill)
    }
}
