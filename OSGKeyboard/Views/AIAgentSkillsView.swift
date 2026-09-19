// AIAgentSkillsView.swift
// OSGKeyboard · Main App
//
// Catalog of installed and available AI Agent clipboard skills. Selecting a
// row opens its detail page; installation state is managed there. Export
// skills confirm a companion Shortcut before installation completes.

import Foundation
import OSGKeyboardShared
import SwiftUI

private enum SkillRoute: Hashable {
    case detail(String)
}

struct AIAgentSkillsView: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var store = AIAgentSkillLayoutStore.shared

    @State private var editingDraft: SkillEditorDraft?
    @StateObject private var pasteAccess = PasteAccessController()
    @State private var path = NavigationPath()
    private var skillCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                CardPageContent {
                    if showsClipboardAccessGuide {
                        clipboardAccessGuide
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    PersonalReplyStyleSection()
                    installedSection
                    if !store.skillManagementAvailableSkills.isEmpty {
                        uninstalledSection
                    }
                }
                .tabBarScrollBottomPadding()
            }
            .background(palette.background)
            .navigationTitle(AppL10n.string("skills.title"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SkillRoute.self) { route in
                switch route {
                case .detail(let skillID):
                    if let skill = store.mergedCatalog.first(where: { $0.id == skillID }) {
                        skillDetailView(skill)
                    } else {
                        ContentUnavailableView(
                            "skills.installed.empty",
                            systemImage: "wand.and.sparkles"
                        )
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingDraft = .blank()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(palette.textPrimary)
                    .accessibilityLabel(Text(AppL10n.string("skills.add")))
                }
            }
        }
        .navigationStackTabBarVisibility(isRoot: path.isEmpty)
        .sheet(item: $editingDraft) { draft in
            SkillEditorSheet(
                draft: draft,
                onSave: { try saveDraft($0) },
                onDelete: { id in
                    store.deleteUserSkill(id: id)
                    editingDraft = nil
                }
            )
        }
        .alert(
            AppL10n.string("clipboard.paste.noText.title", language: config.uiLanguage),
            isPresented: $pasteAccess.showNoTextAlert
        ) {
            Button(AppL10n.string("common.done")) { pasteAccess.showNoTextAlert = false }
        } message: {
            Text(AppL10n.string("clipboard.paste.noText.message", language: config.uiLanguage))
        }
        .onAppear {
            store.reload()
            refreshOfficialSkillCatalog(
                reason: "AIAgentSkillsView.onAppear",
                force: true
            )
            pasteAccess.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.reload()
            refreshOfficialSkillCatalog(
                reason: "AIAgentSkillsView.active",
                force: true
            )
            pasteAccess.refresh(clearRecovery: true)
        }
    }

    private var clipboardAccessGuide: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                skillIcon(systemImage: clipboardGuideIcon)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppL10n.string(clipboardGuideTitle))
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                    Text(AppL10n.string(clipboardGuideBody))
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !pasteAccess.showSuccess {
                Button(action: performClipboardGuideAction) {
                    guideRow(
                        titleKey: clipboardGuideActionTitle,
                        systemImage: clipboardGuideActionIcon,
                        trailing: clipboardGuideActionTrailing
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(clipboardGuideActionIdentifier)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(palette.surface, in: skillCardShape)
        .cardElevation()
        .accessibilityIdentifier("skills.clipboard.guide")
    }

    private func guideRow(
        titleKey: String,
        systemImage: String,
        trailing: String
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .symbolRenderingMode(.monochrome)
                .frame(width: 22)
            Text(AppL10n.string(titleKey))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: trailing)
                .font(TypeStyle.caption.weight(.semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Spacing.sm)
        .frame(minHeight: 44)
        .background(
            palette.surfaceElevated,
            in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private var showsClipboardAccessGuide: Bool {
        !config.clipboardHistoryEnabled || !pasteAccess.isVerified || pasteAccess.showSuccess
    }

    private var clipboardGuideTitle: String {
        if pasteAccess.showSuccess {
            return "skills.clipboard.guide.success.title"
        }
        if !config.clipboardHistoryEnabled {
            return "skills.clipboard.guide.title"
        }
        if pasteAccess.needsRecovery {
            return "skills.clipboard.guide.recovery.title"
        }
        return "skills.clipboard.guide.verify.title"
    }

    private var clipboardGuideBody: String {
        if pasteAccess.showSuccess {
            return "skills.clipboard.guide.success.body"
        }
        if !config.clipboardHistoryEnabled {
            return "skills.clipboard.guide.body"
        }
        if pasteAccess.needsRecovery {
            return "skills.clipboard.guide.recovery.body"
        }
        return "skills.clipboard.guide.verify.body"
    }

    private var clipboardGuideIcon: String {
        if pasteAccess.showSuccess {
            return "checkmark"
        }
        return pasteAccess.needsRecovery ? "exclamationmark" : "clipboard"
    }

    private var clipboardGuideActionTitle: String {
        if !config.clipboardHistoryEnabled {
            return "skills.clipboard.guide.enableHistory"
        }
        if pasteAccess.needsRecovery {
            return "skills.clipboard.guide.openSystemSettings"
        }
        return "skills.clipboard.guide.verify.action"
    }

    private var clipboardGuideActionIcon: String {
        if !config.clipboardHistoryEnabled {
            return "clock.arrow.circlepath"
        }
        return pasteAccess.needsRecovery ? "gearshape" : "checkmark.shield"
    }

    private var clipboardGuideActionTrailing: String {
        pasteAccess.needsRecovery ? "arrow.up.right" : "arrow.right"
    }

    private var clipboardGuideActionIdentifier: String {
        if !config.clipboardHistoryEnabled {
            return "skills.clipboard.guide.enableHistory"
        }
        if pasteAccess.needsRecovery {
            return "skills.clipboard.guide.openSystemSettings"
        }
        return "skills.clipboard.guide.verifyPaste"
    }

    private func performClipboardGuideAction() {
        if !config.clipboardHistoryEnabled {
            withAnimation(Motion.soft) {
                config.clipboardHistoryEnabled = true
            }
            return
        }
        if pasteAccess.needsRecovery {
            AppPermissions.openSystemSettings()
            return
        }
        pasteAccess.verify(flashSuccess: true)
    }

    private func refreshOfficialSkillCatalog(reason: String, force: Bool) {
        Task {
            let outcome = await OfficialSkillCatalogRefreshService.shared.refreshIfNeeded(
                reason: reason,
                force: force
            )
            if outcome.didUpdateCache {
                store.reload()
            }
        }
    }

    private var installedSection: some View {
        CardSection(
            title: AppL10n.format(
                "skills.installed.section",
                language: config.uiLanguage,
                store.skillManagementEnabledSkills.count
            )
        ) {
            if store.skillManagementEnabledSkills.isEmpty {
                Text(AppL10n.string("skills.installed.empty"))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: CardLayoutMetrics.compactItemSpacing) {
                    ForEach(store.skillManagementEnabledSkills) { skill in
                        skillListItem(skill)
                    }
                }
            }
        }
    }

    private var uninstalledSection: some View {
        CardSection(title: AppL10n.string("skills.uninstalled.section")) {
            LazyVStack(spacing: CardLayoutMetrics.compactItemSpacing) {
                ForEach(store.skillManagementAvailableSkills) { skill in
                    skillListItem(skill)
                }
            }
        }
    }

    private func skillListItem(_ skill: AIClipboardSkill) -> some View {
        NavigationLink(value: SkillRoute.detail(skill.id)) {
            skillListRow(skill)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if skill.isUserCreated {
                Button(AppL10n.string("common.delete"), role: .destructive) {
                    store.deleteUserSkill(id: skill.id)
                }
            }
        }
    }

    private func skillListRow(_ skill: AIClipboardSkill) -> some View {
        HStack(spacing: Spacing.md) {
            skillIcon(systemImage: skill.systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(skillTitle(skill))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(skillDescription(skill))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(TypeStyle.caption.weight(.semibold))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 18)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(palette.surface, in: skillCardShape)
        .clipShape(skillCardShape)
        .cardElevation()
        .contentShape(Rectangle())
    }

    private func skillIcon(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .symbolRenderingMode(.monochrome)
            .frame(width: 38, height: 38)
            .background(
                palette.textPrimary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
            )
    }

    private func skillDetailView(_ skill: AIClipboardSkill) -> some View {
        SkillDetailView(
            store: store,
            skill: skill,
            onInstall: addOrWarn,
            onConfirmInstall: confirmShortcutInstall,
            onEdit: {
                guard let user = store.userSkill(id: skill.id) else { return }
                editingDraft = .from(user)
            }
        )
    }

    private func skillTitle(_ skill: AIClipboardSkill) -> String {
        if let name = skill.customName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return AppL10n.string(skill.cardTitleKey, language: config.uiLanguage)
    }

    private func skillDescription(_ skill: AIClipboardSkill) -> String {
        let summary = skill.customSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !summary.isEmpty { return summary }
        if skill.isUserCreated {
            return AppL10n.string("skills.custom.description", language: config.uiLanguage)
        }
        return AppL10n.string(skill.descriptionKey, language: config.uiLanguage)
    }

    private func addOrWarn(_ skill: AIClipboardSkill) {
        switch store.enable(skill.id) {
        case .enabled, .alreadyEnabled:
            break
        case .needsShortcut, .unknown:
            break
        }
    }

    private func confirmShortcutInstall(_ skill: AIClipboardSkill) {
        switch store.confirmShortcutAndEnable(skill.id) {
        case .enabled, .alreadyEnabled:
            break
        case .needsShortcut, .unknown:
            break
        }
    }

    private func saveDraft(_ draft: SkillEditorDraft) throws {
        let rawShortcutLink = draft.shortcutLink.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let shortcutURL: URL?
        if rawShortcutLink.isEmpty {
            shortcutURL = nil
        } else {
            guard let parsedURL = AIShortcutShareLink.parse(rawShortcutLink) else {
                throw AIUserSkillValidationError.invalidShortcutLink
            }
            shortcutURL = parsedURL
        }
        let skill = AIUserSkill(
            id: draft.id,
            name: draft.name,
            summary: draft.summary,
            systemImage: draft.systemImage,
            prompt: draft.prompt,
            shortcutICloudURL: shortcutURL,
            shortcutName: draft.shortcutName,
            thinkingEnabled: draft.thinkingEnabled
        )
        try store.saveUserSkill(skill)
        editingDraft = nil
    }
}

private struct SkillEditorDraft: Identifiable, Equatable {
    let id: String
    let isNew: Bool
    var name: String
    var summary: String
    var systemImage: String
    var prompt: String
    var shortcutLink: String
    var shortcutName: String
    var thinkingEnabled: Bool

    static func blank() -> SkillEditorDraft {
        SkillEditorDraft(
            id: "user.\(UUID().uuidString.lowercased())",
            isNew: true,
            name: "",
            summary: "",
            systemImage: AIUserSkillLimits.defaultSystemImage,
            prompt: AIUserSkillLimits.newPromptTemplate,
            shortcutLink: "",
            shortcutName: "",
            thinkingEnabled: false
        )
    }

    static func from(_ skill: AIUserSkill) -> SkillEditorDraft {
        SkillEditorDraft(
            id: skill.id,
            isNew: false,
            name: skill.name,
            summary: skill.summary,
            systemImage: skill.systemImage,
            prompt: skill.prompt,
            shortcutLink: skill.shortcutICloudURL?.absoluteString ?? "",
            shortcutName: skill.shortcutName,
            thinkingEnabled: skill.thinkingEnabled
        )
    }
}

private struct SkillDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @ObservedObject var store: AIAgentSkillLayoutStore
    @ObservedObject private var config = ProviderConfig.shared

    let skill: AIClipboardSkill
    let onInstall: (AIClipboardSkill) -> Void
    let onConfirmInstall: (AIClipboardSkill) -> Void
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            CardPageContent(
                topPadding: Spacing.md,
                bottomPadding: Spacing.xl
            ) {
                header
                Text(skillDescription)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                promptBlock
                thinkingRow
                skillActions
            }
        }
        .background(palette.background)
        .navigationTitle(AppL10n.string("skills.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if skill.isUserCreated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppL10n.string("skills.edit"), action: onEdit)
                }
            }
        }
    }

    private var skillDescription: String {
        let summary = skill.customSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !summary.isEmpty { return summary }
        if skill.isUserCreated {
            return AppL10n.string("skills.custom.description", language: config.uiLanguage)
        }
        if skill.requiresShortcut, !store.layout.hasConfirmedShortcut(skill.id) {
            return AppL10n.string("skills.install.lead", language: config.uiLanguage)
        }
        return AppL10n.string(skill.descriptionKey, language: config.uiLanguage)
    }

    private var promptText: String {
        AIClipboardSkillCatalog.instruction(
            for: skill,
            locale: config.uiLanguage.resolvedLanguageCode() == "zh-Hans" ? "zh" : "en",
            translationTargetLocaleId: config.translationTargetLocaleId
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: skill.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 38, height: 38)
                .background(
                    palette.textPrimary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(TypeStyle.title3)
                    .foregroundStyle(palette.textPrimary)
                if skill.isDefault {
                    Text(AppL10n.string("skills.badge.default"))
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var headerTitle: String {
        if let name = skill.customName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return AppL10n.string(skill.cardTitleKey, language: config.uiLanguage)
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(AppL10n.string("skills.editor.prompt"))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
            Text(promptText)
                .font(.body.monospaced())
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .background(
                    palette.surface,
                    in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                )
        }
    }

    private var thinkingRow: some View {
        Toggle(AppL10n.string("skills.editor.thinking"), isOn: .constant(skill.thinkingEnabled))
            .disabled(true)
            .font(TypeStyle.body)
    }

    @ViewBuilder
    private var skillActions: some View {
        if skill.requiresShortcut {
            if !store.layout.hasConfirmedShortcut(skill.id) {
                shortcutInstallBlock
            } else {
                if isInstalled {
                    fullWidthButton("skills.action.uninstall", prominent: false) {
                        store.disable(skill.id)
                        dismiss()
                    }
                } else {
                    fullWidthButton("skills.action.install", prominent: true) {
                        onInstall(skill)
                    }
                }
                fullWidthButton("skills.action.reinstallShortcut", prominent: false) {
                    openShortcutInstall()
                }
            }
        } else if isInstalled {
            fullWidthButton("skills.action.uninstall", prominent: false) {
                store.disable(skill.id)
                dismiss()
            }
        } else {
            fullWidthButton("skills.action.install", prominent: true) {
                onInstall(skill)
            }
        }
    }

    private var isInstalled: Bool {
        store.layout.isEnabled(skill.id)
    }

    private var shortcutInstallBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            fullWidthButton("skills.install.openShortcuts", prominent: true) {
                openShortcutInstall()
            }
            fullWidthButton("skills.install.confirmAdded", prominent: false) {
                onConfirmInstall(skill)
            }
            if store.layout.isEnabled(skill.id) {
                fullWidthButton("skills.action.uninstall", prominent: false) {
                    store.disable(skill.id)
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func fullWidthButton(
        _ titleKey: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
        Button(action: action) {
            Text(AppL10n.string(titleKey))
                .font(TypeStyle.bodyEmph)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(prominent ? palette.textOnAccent : palette.textPrimary)
                .background(
                    prominent ? palette.accent : palette.surfaceElevated,
                    in: shape
                )
        }
        .buttonStyle(.plain)
    }

    private func openShortcutInstall() {
        AIAgentShortcutInstaller.openInstallPage(for: skill)
    }
}

private struct SkillEditorSheet: View {
    let draft: SkillEditorDraft
    let onSave: (SkillEditorDraft) throws -> Void
    let onDelete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @State private var name: String
    @State private var summary: String
    @State private var systemImage: String
    @State private var prompt: String
    @State private var shortcutLink: String
    @State private var shortcutName: String
    @State private var thinkingEnabled: Bool
    @State private var showSymbolPicker = false
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    @State private var lookupTask: Task<Void, Never>?
    @State private var saveError: String?
    @State private var confirmDelete = false

    init(
        draft: SkillEditorDraft,
        onSave: @escaping (SkillEditorDraft) throws -> Void,
        onDelete: @escaping (String) -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: draft.name)
        _summary = State(initialValue: draft.summary)
        _systemImage = State(initialValue: draft.systemImage)
        _prompt = State(initialValue: draft.prompt)
        _shortcutLink = State(initialValue: draft.shortcutLink)
        _shortcutName = State(initialValue: draft.shortcutName)
        _thinkingEnabled = State(initialValue: draft.thinkingEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppL10n.string("skills.editor.name")) {
                    TextField(AppL10n.string("skills.editor.namePlaceholder"), text: $name)
                        .settingsListRow()
                        .cardListRow(elevated: false)
                }
                Section(AppL10n.string("skills.editor.summary")) {
                    TextField(AppL10n.string("skills.editor.summaryPlaceholder"), text: $summary, axis: .vertical)
                        .lineLimit(6...12)
                        .frame(minHeight: 108, alignment: .top)
                        .settingsListRow(alignment: .topLeading)
                        .cardListRow(elevated: false)
                }
                Section(AppL10n.string("skills.editor.icon")) {
                    Button {
                        showSymbolPicker = true
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                                .symbolRenderingMode(.monochrome)
                                .frame(width: 38, height: 38)
                                .background(
                                    palette.textPrimary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppL10n.string("skills.editor.iconChoose"))
                                    .foregroundStyle(palette.textPrimary)
                                Text(systemImage)
                                    .font(TypeStyle.caption)
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(TypeStyle.caption.weight(.semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .settingsListRow()
                    .cardListRow(elevated: false)
                }
                Section {
                    TextEditor(text: $prompt)
                        .font(.body.monospaced())
                        .frame(minHeight: 180)
                        .padding(Spacing.md)
                        .cardListRow(elevated: false)
                } header: {
                    HStack {
                        Text(AppL10n.string("skills.editor.prompt"))
                        Spacer()
                        Text("\(prompt.count)/\(AIUserSkillLimits.maximumPromptCharacters)")
                            .foregroundStyle(
                                prompt.count > AIUserSkillLimits.maximumPromptCharacters
                                    ? palette.danger
                                    : palette.textTertiary
                            )
                    }
                }
                Section {
                    VStack(spacing: 0) {
                        TextField(AppL10n.string("skills.editor.linkPlaceholder"), text: $shortcutLink)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .settingsListRow()

                        Divider().background(palette.divider)

                        TextField(AppL10n.string("skills.editor.shortcutNamePlaceholder"), text: $shortcutName)
                            .settingsListRow()

                        if isLookingUp {
                            Divider().background(palette.divider)
                            Text(AppL10n.string("skills.editor.lookingUp"))
                                .font(TypeStyle.caption)
                                .foregroundStyle(palette.textTertiary)
                                .settingsListRow()
                        } else if let lookupMessage {
                            Divider().background(palette.divider)
                            Text(lookupMessage)
                                .font(TypeStyle.caption)
                                .foregroundStyle(palette.textTertiary)
                                .settingsListRow()
                        }
                    }
                    .cardListRow(elevated: false)
                } header: {
                    Text(AppL10n.string("skills.editor.shortcut"))
                } footer: {
                    Text(AppL10n.string("skills.editor.shortcutHint"))
                }
                Section {
                    Toggle(AppL10n.string("skills.editor.thinking"), isOn: $thinkingEnabled)
                        .settingsListRow()
                        .cardListRow(elevated: false)
                } footer: {
                    Text(AppL10n.string("skills.editor.thinkingHint"))
                }
                if !draft.isNew {
                    Section {
                        Button(AppL10n.string("common.delete"), role: .destructive) {
                            confirmDelete = true
                        }
                        .settingsListRow()
                        .cardListRow(elevated: false)
                    }
                }
            }
            .navigationTitle(draft.isNew ? "skills.add" : "skills.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppL10n.string("common.cancel")) { dismiss() }
                        .tint(palette.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppL10n.string("common.save")) {
                        do {
                            try save()
                            dismiss()
                        } catch {
                            saveError = localizedSaveError(error)
                        }
                    }
                    .disabled(!canSave)
                    .tint(palette.textPrimary)
                }
            }
            .sheet(isPresented: $showSymbolPicker) {
                SkillSymbolPicker(selection: $systemImage)
            }
            .alert(AppL10n.string("skills.delete.title"), isPresented: $confirmDelete) {
                Button(AppL10n.string("common.cancel"), role: .cancel) {}
                Button(AppL10n.string("common.delete"), role: .destructive) {
                    onDelete(draft.id)
                    dismiss()
                }
            } message: {
                Text(AppL10n.string("skills.delete.message"))
            }
            .alert(
                Text(AppL10n.string("skills.error.title")),
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button(AppL10n.string("common.done")) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .onChange(of: shortcutLink) { _, newValue in
                lookupShortcutNameIfNeeded(from: newValue)
            }
            .onDisappear {
                lookupTask?.cancel()
            }
        }
    }

    private var canSave: Bool {
        let trimmedShortcutLink = shortcutLink.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let validShortcutConfiguration = trimmedShortcutLink.isEmpty
            || (
                AIShortcutShareLink.parse(trimmedShortcutLink) != nil
                    && !shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && prompt.count <= AIUserSkillLimits.maximumPromptCharacters
            && validShortcutConfiguration
    }

    private var currentDraft: SkillEditorDraft {
        var next = draft
        next.name = name
        next.summary = summary
        next.systemImage = systemImage
        next.prompt = prompt
        next.shortcutLink = shortcutLink
        next.shortcutName = shortcutName
        next.thinkingEnabled = thinkingEnabled
        return next
    }

    private func save() throws {
        try onSave(currentDraft)
    }

    private func localizedSaveError(_ error: Error) -> String {
        switch error as? AIUserSkillValidationError {
        case .emptyName: return AppL10n.string("skills.error.emptyName")
        case .emptyPrompt: return AppL10n.string("skills.error.emptyPrompt")
        case .emptyShortcutName: return AppL10n.string("skills.error.emptyShortcutName")
        case .invalidShortcutLink: return AppL10n.string("skills.error.invalidLink")
        case .emptyIcon: return AppL10n.string("skills.error.emptyIcon")
        case .promptTooLong: return AppL10n.string("skills.error.promptTooLong")
        case nil: return AppL10n.string("skills.error.generic")
        }
    }

    private func lookupShortcutNameIfNeeded(from raw: String) {
        lookupTask?.cancel()
        guard let url = AIShortcutShareLink.parse(raw) else {
            lookupMessage = nil
            isLookingUp = false
            return
        }
        isLookingUp = true
        lookupMessage = nil
        lookupTask = Task {
            do {
                let fetched = try await AIShortcutShareMetadata.fetchName(from: url)
                try Task.checkCancellation()
                await MainActor.run {
                    isLookingUp = false
                    if shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        shortcutName = fetched
                    }
                    lookupMessage = AppL10n.format(
                        "skills.editor.resolvedName",
                        language: nil,
                        fetched
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    isLookingUp = false
                    lookupMessage = AppL10n.string("skills.editor.lookupFailed")
                }
            }
        }
    }
}

private struct SkillSymbolPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @State private var query = ""

    private let columns = [
        GridItem(.adaptive(minimum: 44), spacing: 6)
    ]

    private var filtered: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return SFSymbolCatalog.names }
        return SFSymbolCatalog.names.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(filtered, id: \.self) { symbol in
                        Button {
                            selection = symbol
                            dismiss()
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(
                                    symbol == selection
                                        ? palette.textPrimary.opacity(0.12)
                                        : palette.surfaceElevated,
                                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(symbol))
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .background(palette.background)
            .navigationTitle(AppL10n.string("skills.editor.icon"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: Text(AppL10n.string("skills.editor.iconSearch")))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppL10n.string("common.done")) { dismiss() }
                        .tint(palette.textPrimary)
                }
            }
        }
        .presentationDetents([.large])
    }
}
