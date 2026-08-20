// AIAgentSkillsView.swift
// OSGKeyboard · Main App
//
// Catalog of AI Agent clipboard skills. Enabled cards (max 8) appear on
// the keyboard after a copy; long-press drag rearranges that row live,
// like Home Screen icons. Export skills confirm a companion Shortcut
// before they can occupy a slot. Users can add custom export skills.

import OSGKeyboardShared
import SwiftUI
import UIKit

struct AIAgentSkillsView: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var store = AIAgentSkillLayoutStore.shared

    @State private var viewingSkill: AIClipboardSkill?
    @State private var editingDraft: SkillEditorDraft?
    @State private var showFullAlert = false
    @State private var pasteAccessVerified = AppPermissions.hasVerifiedPasteAccess
    @State private var pasteAccessNeedsRecovery = false
    @State private var showPasteNoTextAlert = false
    @State private var showPasteAccessSuccess = false
    /// True while a skill card is lifted; locks the page scroll like SpringBoard.
    @State private var isReordering = false

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    private var skillCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                CardPageContent(spacing: Spacing.xl) {
                    if showsClipboardAccessGuide {
                        clipboardAccessGuide
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    enabledSection
                    if !store.availableSkills.isEmpty {
                        availableSection
                    }
                }
                .tabBarScrollBottomPadding()
            }
            .scrollDisabled(isReordering)
            .background(palette.background)
            .navigationTitle("skills.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingDraft = .blank()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("skills.add"))
                }
            }
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
            AppL10n.string("skills.full.title", language: config.uiLanguage),
            isPresented: $showFullAlert
        ) {
            Button("common.done") { showFullAlert = false }
        } message: {
            Text(AppL10n.string("skills.full.message", language: config.uiLanguage))
        }
        .alert(
            AppL10n.string("clipboard.paste.noText.title", language: config.uiLanguage),
            isPresented: $showPasteNoTextAlert
        ) {
            Button("common.done") { showPasteNoTextAlert = false }
        } message: {
            Text(AppL10n.string("clipboard.paste.noText.message", language: config.uiLanguage))
        }
        .onAppear {
            store.reload()
            refreshPasteAccessState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPasteAccessState()
            pasteAccessNeedsRecovery = false
        }
    }

    private var clipboardAccessGuide: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: clipboardGuideIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(clipboardGuideTint)
                    .frame(width: 36, height: 36)
                    .background(clipboardGuideTint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(clipboardGuideTitle)
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                    Text(clipboardGuideBody)
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !showPasteAccessSuccess {
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
        .overlay(skillCardShape.stroke(palette.divider, lineWidth: 0.5))
        .accessibilityIdentifier("skills.clipboard.guide")
    }

    private func guideRow(
        titleKey: LocalizedStringKey,
        systemImage: String,
        trailing: String
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 22)
            Text(titleKey)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: trailing)
                .font(.system(size: 12, weight: .semibold))
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
        !config.clipboardHistoryEnabled || !pasteAccessVerified || showPasteAccessSuccess
    }

    private var clipboardGuideTitle: LocalizedStringKey {
        if showPasteAccessSuccess {
            return "skills.clipboard.guide.success.title"
        }
        if !config.clipboardHistoryEnabled {
            return "skills.clipboard.guide.title"
        }
        if pasteAccessNeedsRecovery {
            return "skills.clipboard.guide.recovery.title"
        }
        return "skills.clipboard.guide.verify.title"
    }

    private var clipboardGuideBody: LocalizedStringKey {
        if showPasteAccessSuccess {
            return "skills.clipboard.guide.success.body"
        }
        if !config.clipboardHistoryEnabled {
            return "skills.clipboard.guide.body"
        }
        if pasteAccessNeedsRecovery {
            return "skills.clipboard.guide.recovery.body"
        }
        return "skills.clipboard.guide.verify.body"
    }

    private var clipboardGuideIcon: String {
        if showPasteAccessSuccess {
            return "checkmark"
        }
        return pasteAccessNeedsRecovery ? "exclamationmark" : "clipboard"
    }

    private var clipboardGuideTint: Color {
        pasteAccessNeedsRecovery ? palette.warning : palette.accent
    }

    private var clipboardGuideActionTitle: LocalizedStringKey {
        if !config.clipboardHistoryEnabled {
            return "skills.clipboard.guide.enableHistory"
        }
        if pasteAccessNeedsRecovery {
            return "skills.clipboard.guide.openSystemSettings"
        }
        return "skills.clipboard.guide.verify.action"
    }

    private var clipboardGuideActionIcon: String {
        if !config.clipboardHistoryEnabled {
            return "clock.arrow.circlepath"
        }
        return pasteAccessNeedsRecovery ? "gearshape" : "checkmark.shield"
    }

    private var clipboardGuideActionTrailing: String {
        pasteAccessNeedsRecovery ? "arrow.up.right" : "arrow.right"
    }

    private var clipboardGuideActionIdentifier: String {
        if !config.clipboardHistoryEnabled {
            return "skills.clipboard.guide.enableHistory"
        }
        if pasteAccessNeedsRecovery {
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
        if pasteAccessNeedsRecovery {
            AppPermissions.openSystemSettings()
            return
        }
        verifyPasteAccess()
    }

    private func verifyPasteAccess() {
        switch AppPermissions.requestPasteAccess() {
        case .verified:
            withAnimation(Motion.soft) {
                pasteAccessVerified = true
                pasteAccessNeedsRecovery = false
                showPasteAccessSuccess = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(Motion.soft) {
                    showPasteAccessSuccess = false
                }
            }
        case .noTextAvailable:
            showPasteNoTextAlert = true
        case .unavailable:
            withAnimation(Motion.soft) {
                pasteAccessVerified = false
                pasteAccessNeedsRecovery = true
            }
        }
    }

    private func refreshPasteAccessState() {
        pasteAccessVerified = AppPermissions.hasVerifiedPasteAccess
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
                EnabledSkillsReorderGrid(
                    skills: store.enabledSkills,
                    isReordering: $isReordering,
                    onTap: handleCardTap,
                    onEdit: handleEdit,
                    onMoveToIndex: { id, index in
                        store.moveEnabled(id: id, toIndex: index)
                    },
                    card: { skill in
                        skillCardVisual(skill, isEnabled: true)
                    }
                )
            }
        }
    }

    private var availableSection: some View {
        CardSection("skills.available.section") {
            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach(store.availableSkills) { skill in
                    skillCardInteractive(skill, isEnabled: false)
                }
            }
        }
    }

    private func skillCardInteractive(_ skill: AIClipboardSkill, isEnabled: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                handleCardTap(skill)
            } label: {
                skillCardVisual(skill, isEnabled: isEnabled)
            }
            .buttonStyle(.plain)

            Button {
                handleEdit(skill)
            } label: {
                Color.clear
                    .frame(
                        width: CatalogCardChrome.editHitSize,
                        height: CatalogCardChrome.editHitSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("skills.edit"))
        }
        .contextMenu {
            if skill.isUserCreated {
                Button("common.delete", role: .destructive) {
                    store.deleteUserSkill(id: skill.id)
                }
            }
        }
    }

    private func skillCardVisual(_ skill: AIClipboardSkill, isEnabled: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: skill.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(skillTitle(skill))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .padding(.trailing, 32)
                Text(skillDescription(skill))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(Spacing.md)

            CatalogCardChrome.editIcon(palette: palette)
                .padding(Spacing.sm)
                .allowsHitTesting(false)

            if isEnabled {
                CatalogCardChrome.checkIcon(palette: palette)
            }
        }
        .background(
            isEnabled ? palette.accentMuted : palette.surface,
            in: skillCardShape
        )
        .overlay(skillCardShape.stroke(
            isEnabled ? palette.accent : palette.divider,
            lineWidth: isEnabled ? 1.5 : 0.5
        ))
        .clipShape(skillCardShape)
        .contentShape(skillCardShape)
        .containerShape(skillCardShape)
    }

    private func skillTitle(_ skill: AIClipboardSkill) -> String {
        if let name = skill.customName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return AppL10n.string(skill.cardTitleKey, language: config.uiLanguage)
    }

    private func skillDescription(_ skill: AIClipboardSkill) -> String {
        if skill.isUserCreated {
            let summary = skill.customSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !summary.isEmpty { return summary }
            return AppL10n.string("skills.custom.description", language: config.uiLanguage)
        }
        return AppL10n.string(skill.descriptionKey, language: config.uiLanguage)
    }

    private func handleCardTap(_ skill: AIClipboardSkill) {
        if skill.requiresShortcut, !store.layout.hasConfirmedShortcut(skill.id) {
            viewingSkill = skill
            return
        }
        if store.layout.isEnabled(skill.id) {
            store.disable(skill.id)
        } else {
            addOrWarn(skill)
        }
    }

    private func handleEdit(_ skill: AIClipboardSkill) {
        if skill.isUserCreated, let user = store.userSkill(id: skill.id) {
            editingDraft = .from(user)
        } else {
            viewingSkill = skill
        }
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

/// Home-screen style reorder: long-press lifts the card, other cells slide
/// into the gap as the finger crosses midpoints, drop settles in place.
private struct EnabledSkillsReorderGrid<Card: View>: View {
    let skills: [AIClipboardSkill]
    @Binding var isReordering: Bool
    let onTap: (AIClipboardSkill) -> Void
    let onEdit: (AIClipboardSkill) -> Void
    let onMoveToIndex: (String, Int) -> Void
    let card: (AIClipboardSkill) -> Card

    @State private var draggingID: String?
    @State private var dragTranslation: CGSize = .zero
    @State private var originFrame: CGRect = .zero
    @State private var cellFrames: [String: CGRect] = [:]
    @State private var ignoreTap = false

    private static var spaceName: String { "enabledSkillsGrid" }
    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach(skills) { skill in
                    gridCell(skill)
                }
            }
            .animation(
                .interactiveSpring(response: 0.28, dampingFraction: 0.86),
                value: skills.map(\.id)
            )

            if let draggingID, let skill = skills.first(where: { $0.id == draggingID }) {
                card(skill)
                    .frame(width: originFrame.width, height: originFrame.height)
                    .scaleEffect(1.07)
                    .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
                    .offset(
                        x: originFrame.minX + dragTranslation.width,
                        y: originFrame.minY + dragTranslation.height
                    )
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(.named(Self.spaceName))
        .onPreferenceChange(SkillCellFrameKey.self) { cellFrames = $0 }
    }

    private func gridCell(_ skill: AIClipboardSkill) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard draggingID == nil, !ignoreTap else { return }
                onTap(skill)
            } label: {
                card(skill)
                    .opacity(draggingID == skill.id ? 0 : 1)
            }
            .buttonStyle(.plain)

            Button {
                guard draggingID == nil, !ignoreTap else { return }
                onEdit(skill)
            } label: {
                Color.clear
                    .frame(
                        width: CatalogCardChrome.editHitSize,
                        height: CatalogCardChrome.editHitSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("skills.edit"))
            .opacity(draggingID == skill.id ? 0 : 1)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SkillCellFrameKey.self,
                    value: [skill.id: proxy.frame(in: .named(Self.spaceName))]
                )
            }
        }
        .simultaneousGesture(reorderGesture(for: skill))
    }

    private func reorderGesture(for skill: AIClipboardSkill) -> some Gesture {
        LongPressGesture(minimumDuration: 0.22)
            .sequenced(
                before: DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named(Self.spaceName)
                )
            )
            .onChanged { value in
                switch value {
                case .second(_, let drag):
                    liftIfNeeded(skill)
                    guard let drag else { return }
                    dragTranslation = drag.translation
                    moveSlotIfNeeded(at: drag.location)
                default:
                    break
                }
            }
            .onEnded { _ in
                endDrag()
            }
    }

    private func liftIfNeeded(_ skill: AIClipboardSkill) {
        guard draggingID == nil else { return }
        originFrame = cellFrames[skill.id] ?? .zero
        draggingID = skill.id
        isReordering = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
    }

    private func moveSlotIfNeeded(at point: CGPoint) {
        guard let draggingID else { return }
        guard let target = nearestIndex(to: point) else { return }
        guard skills[target].id != draggingID else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onMoveToIndex(draggingID, target)
    }

    private func nearestIndex(to point: CGPoint) -> Int? {
        guard !skills.isEmpty else { return nil }
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, skill) in skills.enumerated() {
            guard let frame = cellFrames[skill.id] else { continue }
            let dx = point.x - frame.midX
            let dy = point.y - frame.midY
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func endDrag() {
        let wasDragging = draggingID != nil
        if let draggingID, let slot = cellFrames[draggingID], originFrame.width > 0 {
            withAnimation(.snappy(duration: 0.2)) {
                dragTranslation = CGSize(
                    width: slot.minX - originFrame.minX,
                    height: slot.minY - originFrame.minY
                )
            } completion: {
                clearDragState()
            }
        } else {
            clearDragState()
        }
        guard wasDragging else { return }
        ignoreTap = true
        DispatchQueue.main.async {
            ignoreTap = false
        }
    }

    private func clearDragState() {
        draggingID = nil
        dragTranslation = .zero
        isReordering = false
    }
}

private struct SkillCellFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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

private struct SkillDetailSheet: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var store: AIAgentSkillLayoutStore
    @ObservedObject private var config = ProviderConfig.shared

    let skill: AIClipboardSkill
    let onDismiss: () -> Void
    let onAddOrWarn: (AIClipboardSkill) -> Void
    let onConfirmInstall: (AIClipboardSkill) -> Void

    /// Inner stack height; nav chrome + home indicator are added for the detent.
    @State private var contentHeight: CGFloat = 280
    private let navigationChrome: CGFloat = 72

    var body: some View {
        NavigationStack {
            ScrollView {
                CardPageContent(
                    spacing: Spacing.md,
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
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    let next = newHeight + navigationChrome
                    if abs(contentHeight - next) > 1 {
                        contentHeight = next
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(palette.background)
            .navigationTitle("skills.detail.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.height(clampedSheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
        .animation(.easeInOut(duration: 0.2), value: clampedSheetHeight)
    }

    private var clampedSheetHeight: CGFloat {
        let screen = UIScreen.main.bounds.height
        let maximum = screen * 0.92
        return min(max(contentHeight, 280), maximum)
    }

    private var skillDescription: String {
        if skill.isUserCreated {
            let summary = skill.customSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !summary.isEmpty { return summary }
            return AppL10n.string("skills.custom.description", language: config.uiLanguage)
        }
        if skill.requiresShortcut, !store.layout.hasConfirmedShortcut(skill.id) {
            return AppL10n.string("skills.install.lead", language: config.uiLanguage)
        }
        if skill.requiresShortcut, store.layout.isEnabled(skill.id) {
            return AppL10n.string("skills.action.turnOffHint", language: config.uiLanguage)
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
                .foregroundStyle(palette.accent)
                .frame(width: 36, height: 36)
                .background(palette.accentMuted, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
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

    private var headerTitle: String {
        if let name = skill.customName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return AppL10n.string(skill.cardTitleKey, language: config.uiLanguage)
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("skills.editor.prompt")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
            Text(promptText)
                .font(.body.monospaced())
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .surfaceCard()
        }
    }

    private var thinkingRow: some View {
        Toggle("skills.editor.thinking", isOn: .constant(skill.thinkingEnabled))
            .disabled(true)
            .font(TypeStyle.body)
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
        Button(action: action) {
            Text(titleKey)
                .font(TypeStyle.bodyEmph)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(prominent ? palette.textOnAccent : palette.textPrimary)
                .background(
                    prominent ? palette.accent : palette.surfaceElevated,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(prominent ? Color.clear : palette.dividerStrong, lineWidth: 0.5)
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
                Section("skills.editor.name") {
                    TextField("skills.editor.namePlaceholder", text: $name)
                }
                Section("skills.editor.summary") {
                    TextField("skills.editor.summaryPlaceholder", text: $summary, axis: .vertical)
                        .lineLimit(6...12)
                        .frame(minHeight: 108, alignment: .top)
                }
                Section("skills.editor.icon") {
                    Button {
                        showSymbolPicker = true
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: systemImage)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .frame(width: 44, height: 44)
                                .background(
                                    palette.accentMuted,
                                    in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("skills.editor.iconChoose")
                                    .foregroundStyle(palette.textPrimary)
                                Text(systemImage)
                                    .font(TypeStyle.caption)
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Section {
                    TextEditor(text: $prompt)
                        .font(.body.monospaced())
                        .frame(minHeight: 180)
                } header: {
                    HStack {
                        Text("skills.editor.prompt")
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
                    TextField("skills.editor.linkPlaceholder", text: $shortcutLink)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("skills.editor.shortcutNamePlaceholder", text: $shortcutName)
                    if isLookingUp {
                        Text("skills.editor.lookingUp")
                            .font(TypeStyle.caption)
                            .foregroundStyle(palette.textTertiary)
                    } else if let lookupMessage {
                        Text(lookupMessage)
                            .font(TypeStyle.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                } header: {
                    Text("skills.editor.shortcut")
                } footer: {
                    Text("skills.editor.shortcutHint")
                }
                Section {
                    Toggle("skills.editor.thinking", isOn: $thinkingEnabled)
                } footer: {
                    Text("skills.editor.thinkingHint")
                }
                if !draft.isNew {
                    Section {
                        Button("common.delete", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(draft.isNew ? "skills.add" : "skills.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        do {
                            try save()
                            dismiss()
                        } catch {
                            saveError = localizedSaveError(error)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showSymbolPicker) {
                SkillSymbolPicker(selection: $systemImage)
            }
            .alert("skills.delete.title", isPresented: $confirmDelete) {
                Button("common.cancel", role: .cancel) {}
                Button("common.delete", role: .destructive) {
                    onDelete(draft.id)
                    dismiss()
                }
            } message: {
                Text("skills.delete.message")
            }
            .alert(
                Text("skills.error.title"),
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("common.done") { saveError = nil }
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
                                .foregroundStyle(
                                    symbol == selection ? palette.textOnAccent : palette.textPrimary
                                )
                                .frame(width: 44, height: 44)
                                .background(
                                    symbol == selection ? palette.accent : palette.surfaceElevated,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            .navigationTitle("skills.editor.icon")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: Text("skills.editor.iconSearch"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
