// TypingRootView.swift
// OSGKeyboard · Keyboard Extension
//
// Typing surface: candidate bar + QWERTY / 123 / symbols.
// Top-leading control returns to the voice surface.

import SwiftUI
import OSGKeyboardShared

enum TypingLayoutMetrics {
    // Size decisions live in `TypingSurfaceMetrics` (Shared) so the UIKit
    // height constraint and this SwiftUI grid cannot disagree.
    static let outerPaddingTop: CGFloat = TypingSurfaceMetrics.outerPaddingTop
    static let outerPaddingBottom: CGFloat = TypingSurfaceMetrics.outerPaddingBottom
    static let topRegionHeight: CGFloat = TypingSurfaceMetrics.topRegionHeight
    static let verticalKeySpacing: CGFloat = TypingSurfaceMetrics.verticalKeySpacing
    static let keyCornerRadius: CGFloat = KeyboardChromeLayout.actionKeyCornerRadius
    /// Shared top row + three 50 pt key rows + native spacing + bottom row.
    static let totalHeight: CGFloat = KeyboardChromeLayout.totalHeight
    /// Collapsed candidate strip: keep this small so ScrollView doesn't fight ▼.
    static let collapsedBarCandidateLimit = 10
    /// Trailing ▼/▲ control (visual chip + hit pad); lives in an HStack, not over text.
    static let expandChevronHitWidth: CGFloat = 44
    static let expandChevronVisualSize: CGFloat = 34
    static let expandGridColumns = 5
    static let expandCellHeight: CGFloat = 42

    // MARK: - iPad (regular size class) metrics

    static func metrics(isIPad: Bool, width: CGFloat) -> TypingKeyLayoutBuilder.Metrics {
        TypingSurfaceMetrics.metrics(isIPad: isIPad, width: width)
    }

    static func contentHeight(isIPad: Bool, width: CGFloat) -> CGFloat {
        TypingSurfaceMetrics.contentHeight(isIPad: isIPad, width: width)
    }
}

struct TypingRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: KeyboardState
    @ObservedObject var typing: TypingSessionController

    var onInsert: (String) -> Void
    var onDeleteBackward: () -> Void

    /// After the first expand, keep the panel tree mounted and only toggle
    /// opacity so subsequent ▼/▲ taps stay cheap.
    @State private var candidatePanelMounted = false
    /// Keys currently under a finger (grid-level touch pad, multi-touch).
    @State private var highlightedKeyIDs: Set<String> = []

    static func totalHeight(isIPad: Bool = false, width: CGFloat = 0) -> CGFloat {
        TypingLayoutMetrics.contentHeight(isIPad: isIPad, width: width)
    }

    private var palette: ThemePalette {
        colorScheme == .dark ? Palette.dark : Palette.light
    }

    var body: some View {
        let expanded = typing.isCandidatePanelExpanded
        VStack(spacing: 0) {
            topRegion
                .frame(height: TypingLayoutMetrics.topRegionHeight)

            // Keep the QWERTY tree mounted; only toggle visibility so ▼/▲
            // does not destroy GeometryReader key rows every time.
            ZStack(alignment: .top) {
                typingKeySurface
                    .padding(.top, TypingLayoutMetrics.verticalKeySpacing)
                    .opacity(expanded ? 0 : 1)
                    .allowsHitTesting(!expanded)
                    .accessibilityHidden(expanded)

                if expanded || candidatePanelMounted {
                    expandedCandidatePanel
                        .padding(.top, TypingLayoutMetrics.verticalKeySpacing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(expanded ? 1 : 0)
                        .allowsHitTesting(expanded)
                        .accessibilityHidden(!expanded)
                        .transition(.identity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, TypingLayoutMetrics.outerPaddingTop)
        .padding(.bottom, TypingLayoutMetrics.outerPaddingBottom)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        // No content-width cap: a key grid has to span the host width or the
        // user's muscle memory for the system keyboard's absolute key
        // positions is wrong on every key.
        .frame(maxWidth: .infinity)
        .frame(
            height: Self.totalHeight(
                isIPad: state.usesIPadLayoutMetrics,
                width: state.layoutWidth
            )
        )
        .background(Color.clear)
        .environment(\.themePalette, palette)
        // enterTypingMode is owned by KeyboardViewController.viewWillAppear
        // when surface == .typing — avoid a duplicate prepare here.
        .onChange(of: typing.isCandidatePanelExpanded) { _, isExpanded in
            if isExpanded { candidatePanelMounted = true }
        }
        .onChange(of: hasCandidateContent) { _, hasContent in
            if !hasContent { candidatePanelMounted = false }
        }
        .onAppear {
            // Primary warm-up lives in KVC.viewWillAppear (covers app switch).
            // Keep this for first mount / surface flip into typing.
            KeyboardHapticFeedback.prepare()
        }
    }

    // MARK: - Shared top region

    @ViewBuilder
    private var topRegion: some View {
        if hasCandidateContent {
            // Composing Chinese/English candidates hide the clipboard strip.
            candidateBar
        } else if state.canShowClipboardEntry,
                  let suggestion = state.clipboardSuggestionText,
                  !suggestion.isEmpty {
            // Same slot as logo + capsule tabs — hide chrome until dismissed.
            ClipboardSuggestionBar(
                text: suggestion,
                onInsert: { state.insertClipboardText(suggestion) },
                onDismiss: state.dismissClipboardSuggestion
            )
            .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
        } else {
            idleTopBar
        }
    }

    private var hasCandidateContent: Bool {
        !typing.composition.preedit.isEmpty || !typing.composition.candidates.isEmpty
    }

    private var idleTopBar: some View {
        ZStack {
            KeyboardTopControls(
                state: state,
                typing: typing,
                palette: palette,
                onInsert: onInsert
            )

            HStack(spacing: Spacing.xs) {
                KeyboardBrandLogo(action: state.openSettings)
                // Globe key now lives at the bottom-left of the keyboard (matching
                // iOS system layout); see the typingKeySurface ForEach.

                if let err = typing.lastError {
                    typingErrorLabel(err)
                }

                // iOS-style editing cluster (undo / redo / copy / cut) — iPad only,
                // where the top bar has room to mirror the system shortcut row.
                if state.usesIPadLayoutMetrics {
                    editingToolbar
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
    }

    /// Rime failures that only host-side deployment can fix become a tappable
    /// jump into the app; everything else stays a plain read-only notice.
    @ViewBuilder
    private func typingErrorLabel(_ message: String) -> some View {
        if typing.lastErrorNeedsHostDeployment {
            Button(action: state.openInputMethodSetup) {
                HStack(spacing: 2) {
                    Text(message)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(palette.danger)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(ExtL10n.text("keyboard.typing.setupA11yHint"))
        } else {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(palette.danger)
                .lineLimit(1)
        }
    }

    // MARK: - Candidates

    private var candidateBar: some View {
        // HStack (not overlay / safeAreaInset): ▼ never paints over candidate text.
        // Globe key now lives at the bottom-left of the keyboard (matching
        // iOS system layout); see the typingKeySurface ForEach.
        HStack(spacing: 0) {
            if state.usesIPadLayoutMetrics {
                editingToolbar
                    .padding(.leading, KeyboardTopBarMetrics.nestedHorizontalInset)
            }
            if typing.language == .english {
                englishQuickTypeBar
            } else {
                chineseCandidateStrip
            }

            if typing.canExpandCandidatePanel {
                expandChevronButton
            } else {
                Color.clear.frame(width: KeyboardTopBarMetrics.nestedHorizontalInset)
            }
        }
    }

    /// Three equal QuickType slots. Space applies only `role == .correction`.
    private var englishQuickTypeBar: some View {
        HStack(spacing: 0) {
            ForEach(
                Array(
                    typing.composition.candidates
                        .prefix(EnglishSuggestionEngine.slotCount)
                        .enumerated()
                ),
                id: \.element.id
            ) { index, candidate in
                if index > 0 {
                    Rectangle()
                        .fill(palette.dividerStrong)
                        .frame(width: 1, height: 18)
                }
                englishQuickTypeSlot(candidate, index: index)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, KeyboardTopBarMetrics.nestedHorizontalInset)
    }

    private func englishQuickTypeSlot(_ candidate: TypingCandidate, index: Int) -> some View {
        let label = candidate.isQuoted ? "\"\(candidate.text)\"" : candidate.text
        let weight: Font.Weight = candidate.role == .correction ? .semibold : .regular
        return Text(label)
            .font(.system(size: 17, weight: weight))
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
            .onTapGesture {
                apply(typing.selectCandidate(at: index))
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(candidate.text)
    }

    private var chineseCandidateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                if typing.composition.candidates.isEmpty {
                    selectedCandidateLabel(text: typing.composition.preedit)
                } else if typing.isCandidatePanelExpanded {
                    candidateChip(text: typing.composition.candidates[0].text) {
                        apply(typing.selectCandidate(at: 0))
                    }
                } else {
                    ForEach(
                        Array(
                            typing.composition.candidates
                                .prefix(TypingLayoutMetrics.collapsedBarCandidateLimit)
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, candidate in
                        if index == 0 {
                            candidateChip(text: candidate.text) {
                                apply(typing.selectCandidate(at: index))
                            }
                        } else {
                            Text(candidate.text)
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, 10)
                                .frame(height: 40)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    apply(typing.selectCandidate(at: index))
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(candidate.text)
                        }
                    }
                }
            }
            .padding(.leading, KeyboardTopBarMetrics.nestedHorizontalInset)
            .padding(.trailing, Spacing.xs)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// Opaque chip like the translation control so ▼ never shares pixels with text.
    private var expandChevronButton: some View {
        Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                typing.toggleCandidatePanelExpanded()
            }
        } label: {
            Image(systemName: typing.isCandidatePanelExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(
                    width: TypingLayoutMetrics.expandChevronVisualSize,
                    height: TypingLayoutMetrics.expandChevronVisualSize
                )
                .background(expandChevronFill, in: Circle())
                .overlay(Circle().stroke(palette.divider, lineWidth: 0.5))
                .frame(
                    width: TypingLayoutMetrics.expandChevronHitWidth,
                    height: KeyboardTopBarMetrics.height
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, KeyboardTopBarMetrics.nestedHorizontalInset)
        .accessibilityLabel(typing.isCandidatePanelExpanded ? "收起候选" : "更多候选")
    }

    private var expandChevronFill: Color {
        colorScheme == .dark ? Color(white: 0.30) : .white
    }

    // MARK: - Editing toolbar (iPad)

    /// iOS-style editing cluster: undo / redo / copy / cut. Mirrors the system
    /// keyboard's shortcut row; surfaced only on iPad where the top bar fits.
    @ViewBuilder
    private var editingToolbar: some View {
        HStack(spacing: 2) {
            editingToolbarButton(
                systemName: "arrow.uturn.backward",
                label: ExtL10n.string("keyboard.undoA11y"),
                enabled: state.undoAvailable
            ) { state.undoLastInsertion() }
            editingToolbarButton(
                systemName: "arrow.uturn.forward",
                label: ExtL10n.string("keyboard.redoA11y"),
                enabled: state.redoAvailable
            ) { state.redoLastInsertion() }
            editingToolbarButton(
                systemName: "doc.on.doc",
                label: ExtL10n.string("keyboard.copyA11y"),
                enabled: state.copyAvailable
            ) { state.copySelection() }
            editingToolbarButton(
                systemName: "scissors",
                label: ExtL10n.string("keyboard.cutA11y"),
                enabled: state.cutAvailable
            ) { state.cutSelection() }
        }
    }

    private func editingToolbarButton(
        systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(enabled ? palette.textSecondary : palette.textTertiary)
                .frame(width: 34, height: 34)
                .background(enabled ? editingToolbarButtonFill : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    private var editingToolbarButtonFill: Color {
        colorScheme == .dark ? Color(white: 0.30) : .white
    }

    /// UIKit-recycled labels — no SwiftUI Button per candidate.
    private var expandedCandidatePanel: some View {
        CandidateExpandGridView(
            candidates: typing.composition.candidates,
            textColor: UIColor(keyTextColor),
            dividerColor: UIColor(palette.dividerStrong),
            onSelect: { index in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    apply(typing.selectCandidate(at: index))
                }
            }
        )
        .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
    }

    private func candidateChip(text: String, action: @escaping () -> Void) -> some View {
        selectedCandidateLabel(text: text)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(text)
    }

    private func selectedCandidateLabel(text: String) -> some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 19, weight: .medium))
                .lineLimit(1)
            if !typing.composition.preedit.isEmpty {
                Text(typing.composition.preedit)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(keyTextColor)
        .padding(.horizontal, 12)
        .frame(minWidth: 56, minHeight: 40)
        .background(
            selectedCandidateFill,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    // MARK: - Keys

    /// Visual keys + grid-level touch pad (Phase 1 gap fill + Phase 2
    /// down → move → up). Geometry is shared via ``TypingKeyLayoutBuilder``.
    private var typingKeySurface: some View {
        GeometryReader { proxy in
            let layout = makeTypingKeyLayout(size: proxy.size)
            ZStack(alignment: .topLeading) {
                TypingKeyTouchPad(
                    layout: layout,
                    hapticIntensity: state.keyboardHapticIntensity,
                    onHighlightChange: { highlightedKeyIDs = $0 },
                    onCommit: { commitTypingKey($0) },
                    onDeleteFire: { apply(typing.handleKey("⌫")) },
                    onShiftBegan: { typing.beginShiftHold() },
                    onShiftEnded: { typing.endShiftHold() }
                )

                ForEach(layout.keys) { key in
                    if key.id == TypingKeyLayoutBuilder.BottomKeyID.globe.rawValue {
                        // Globe key: SystemGlobeKey's UIButton handles its own
                        // tap (advance) / long-press (system input-mode list),
                        // so leave hit testing enabled here. The touch pad sits
                        // underneath but the UIButton intercepts touches in
                        // this frame, so hit testing against `layout.keys`
                        // never fires for the globe slot.
                        SystemGlobeKey(
                            state: state,
                            width: key.visualFrame.width,
                            height: key.visualFrame.height
                        )
                        .frame(width: key.visualFrame.width, height: key.visualFrame.height)
                        .position(
                            x: key.visualFrame.midX,
                            y: key.visualFrame.midY
                        )
                    } else {
                        visualTypingKey(key)
                            .frame(width: key.visualFrame.width, height: key.visualFrame.height)
                            .position(
                                x: key.visualFrame.midX,
                                y: key.visualFrame.midY
                            )
                            // Touches go to the UIKit pad; visuals stay for VoiceOver.
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func makeTypingKeyLayout(size: CGSize) -> TypingKeyLayout {
        let isIPad = state.usesIPadLayoutMetrics
        // Select metrics from the same width the controller used to size the
        // keyboard. Using `size` here would compare the grid's own width to
        // its height (always landscape) and could pick a different bucket than
        // the height constraint, clipping the bottom row.
        let metrics = TypingLayoutMetrics.metrics(isIPad: isIPad, width: state.layoutWidth)
        let pageLabel = typing.page == .letters ? "123" : "ABC"
        let spaceLabel = typing.language == .chinese ? "空格" : "space"
        let returnLabel: String = {
            if state.returnKeyRole.usesActionFill {
                return ExtL10n.string(state.returnKeyRole.titleKey)
            }
            return "return"
        }()

        // iPad spends its extra width on comma / period like the system
        // keyboard, instead of stretching the space bar across it.
        let punctuationKeys: TypingKeyLayoutBuilder.PunctuationKeys? = isIPad
            ? (typing.language == .chinese
                ? .init(comma: "，", period: "。")
                : .init(comma: ",", period: "."))
            : nil

        let layout = TypingKeyLayoutBuilder.build(
            size: size,
            letterRows: typing.keyRows,
            pageSwitchLabel: pageLabel,
            spaceLabel: spaceLabel,
            returnLabel: returnLabel,
            metrics: metrics,
            includeGlobeKey: state.showsSystemGlobeKey,
            punctuationKeys: punctuationKeys,
            // iPad top letter row carries the small number overlay (1–0),
            // mirroring the iOS system keyboard. iPhone keeps the clean row.
            showTopRowNumbers: isIPad,
            keyWeight: { label, index, rowIndex in
                keyWeight(label: label, index: index, rowIndex: rowIndex)
            }
        )
        let validNext = PinyinNextKeyResolver.validNextKeys(
            rawInput: typing.composition.rawInput,
            schema: typing.schema,
            language: typing.language,
            page: typing.page
        )
        return layout.withHitWeights(
            PinyinNextKeyResolver.hitWeights(for: layout.keys, validNext: validNext)
        )
    }

    @ViewBuilder
    private func visualTypingKey(_ key: TypingKeyHitTarget) -> some View {
        let pressed = highlightedKeyIDs.contains(key.id)
        let isBottom = key.id.hasPrefix("bottom.")
        let isShift = key.label == "⇧"
        let shiftLit = isShift && typing.isShiftEnabled
        let showPressed = pressed || shiftLit

        Group {
            if key.label == "⌫" {
                Image(systemName: "delete.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(keyTextColor)
            } else if key.label == "⇧" {
                Image(systemName: typing.isShiftEnabled ? "shift.fill" : "shift")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(keyTextColor)
            } else if key.id == TypingKeyLayoutBuilder.BottomKeyID.return.rawValue {
                returnKeyLabel
                    .foregroundStyle(returnKeyTextColor)
            } else if isBottom {
                let isSpecial = key.id == TypingKeyLayoutBuilder.BottomKeyID.pageSwitch.rawValue
                Text(key.label)
                    .font(
                        .system(
                            size: isSpecial ? 15 : 17,
                            weight: isSpecial ? .semibold : .regular
                        )
                    )
                    .foregroundStyle(keyTextColor)
            } else {
                // Letter / character key. On iPad the top row carries a small
                // grey number overlay (1–0), mirroring the iOS system keyboard;
                // `displayNumber` is nil everywhere else, so the layout is a
                // single centred letter there.
                VStack(spacing: 1) {
                    if let number = key.displayNumber {
                        Text(number)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.textSecondary.opacity(0.7))
                    }
                    let isSpecial = ["123", "#+=", "ABC"].contains(key.label)
                    Text(key.label)
                        .font(
                            .system(
                                size: isSpecial ? 15 : 22,
                                weight: isSpecial ? .semibold : .regular
                            )
                        )
                        .foregroundStyle(keyTextColor)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(
                cornerRadius: TypingLayoutMetrics.keyCornerRadius,
                style: .continuous
            )
            .fill(visualKeyFill(for: key, pressed: showPressed))
        )
        // 无投影：与 NativeKeyboardKeySurface 一致，靠填充 + 描边表达层次。
        .overlay(
            RoundedRectangle(
                cornerRadius: TypingLayoutMetrics.keyCornerRadius,
                style: .continuous
            )
            .stroke(visualKeyBorder(for: key), lineWidth: 0.5)
        )
        .scaleEffect(pressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(accessibilityLabel(for: key)))
        .accessibilityAction {
            commitTypingKey(key)
        }
    }

    private func visualKeyFill(for key: TypingKeyHitTarget, pressed: Bool) -> Color {
        if key.id == TypingKeyLayoutBuilder.BottomKeyID.return.rawValue {
            return pressed ? returnKeyPressedFill : returnKeyFill
        }
        return pressed ? keyPressedFill : keyFill
    }

    private func visualKeyBorder(for key: TypingKeyHitTarget) -> Color {
        if key.id == TypingKeyLayoutBuilder.BottomKeyID.return.rawValue {
            return returnKeyBorder
        }
        return palette.divider
    }

    private func accessibilityLabel(for key: TypingKeyHitTarget) -> String {
        switch key.id {
        case TypingKeyLayoutBuilder.BottomKeyID.return.rawValue:
            return returnKeyAccessibilityLabel
        case TypingKeyLayoutBuilder.BottomKeyID.space.rawValue:
            return key.label
        default:
            if key.label == "⇧" { return "shift" }
            if key.label == "⌫" { return "delete" }
            return key.label
        }
    }

    private func commitTypingKey(_ key: TypingKeyHitTarget) {
        switch key.id {
        case TypingKeyLayoutBuilder.BottomKeyID.pageSwitch.rawValue:
            typing.setPage(typing.page == .letters ? .numbers : .letters)
        case TypingKeyLayoutBuilder.BottomKeyID.space.rawValue:
            apply(typing.handleSpace())
        case TypingKeyLayoutBuilder.BottomKeyID.return.rawValue:
            apply(typing.handleReturn())
        case TypingKeyLayoutBuilder.BottomKeyID.comma.rawValue,
             TypingKeyLayoutBuilder.BottomKeyID.period.rawValue:
            // Route through the engine so a pending composition commits first,
            // exactly as punctuation typed from the symbols page does.
            apply(typing.handleKey(key.label))
        default:
            switch key.behavior {
            case .commitOnRelease:
                apply(typing.handleKey(key.label))
            case .deleteRepeat:
                apply(typing.handleKey("⌫"))
            case .shiftHold:
                // Mirror a completed Shift tap for VoiceOver / accessibility.
                typing.beginShiftHold()
                typing.endShiftHold()
            }
        }
    }

    @ViewBuilder
    private var returnKeyLabel: some View {
        if state.returnKeyRole.usesActionFill {
            ExtL10n.text(state.returnKeyRole.titleKey)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Image(systemName: "arrow.turn.down.left")
                .font(.system(size: 21, weight: .medium))
        }
    }

    private func apply(_ output: TypingOutput) {
        guard !output.isEmpty else {
            typing.syncAutocapitalization()
            return
        }
        if output.deleteCount > 0 {
            for _ in 0..<output.deleteCount {
                onDeleteBackward()
            }
        }
        if !output.text.isEmpty {
            onInsert(output.text)
        }
        // Notes / some hosts lag `documentContextBeforeInput` — pass the edit we
        // just applied so sentence Shift can arm after Return / "." immediately.
        typing.syncAutocapitalization(
            accountingForInsert: output.text,
            deleteCount: output.deleteCount
        )
    }

    private func keyWeight(label: String, index: Int, rowIndex: Int) -> CGFloat {
        // Match system: page switchers + delete are wider than character keys.
        if label == "⌫" || label == "⇧" || label == "#+=" || label == "123" {
            return 1.35
        }
        if rowIndex == 2 && index == 0 {
            // Double-pinyin semicolon occupies the normal Shift footprint.
            return 1.35
        }
        return 1
    }

    private var keyFill: Color {
        NativeKeyboardKeyColors.fill(for: colorScheme)
    }

    private var keyPressedFill: Color {
        NativeKeyboardKeyColors.pressedFill(for: colorScheme)
    }

    private var keyTextColor: Color {
        NativeKeyboardKeyColors.text(for: colorScheme)
    }

    private var selectedCandidateFill: Color {
        colorScheme == .dark ? Color(white: 0.36) : .white
    }

    private var returnKeyFill: Color {
        state.returnKeyRole.usesActionFill ? sendKeyFill : keyFill
    }

    private var returnKeyPressedFill: Color {
        state.returnKeyRole.usesActionFill ? sendKeyPressedFill : keyPressedFill
    }

    private var returnKeyBorder: Color {
        if state.returnKeyRole.usesActionFill {
            return Color.black.opacity(colorScheme == .dark ? 0.10 : 0.08)
        }
        return palette.divider
    }

    private var returnKeyAccessibilityLabel: String {
        if state.returnKeyRole.usesActionFill {
            return ExtL10n.string(state.returnKeyRole.titleKey)
        }
        return "return"
    }

    private var returnKeyTextColor: Color {
        state.returnKeyRole.usesActionFill ? .white : keyTextColor
    }

    /// The send key stays recognizable in both appearances without becoming neon.
    private var sendKeyFill: Color {
        NativeKeyboardKeyColors.sendFill(for: colorScheme)
    }

    private var sendKeyPressedFill: Color {
        NativeKeyboardKeyColors.sendPressedFill(for: colorScheme)
    }
}
