// TypingRootView.swift
// OSGKeyboard · Keyboard Extension
//
// Typing surface: candidate bar + QWERTY / 123 / symbols.
// Top-leading control returns to the voice surface.

import SwiftUI
import OSGKeyboardShared

enum TypingLayoutMetrics {
    static let outerPaddingTop: CGFloat = 4
    static let outerPaddingBottom: CGFloat = 4
    static let topRegionHeight: CGFloat = KeyboardTopBarMetrics.height
    static let keyRowHeight: CGFloat = 50
    static let keyRowSpacing: CGFloat = 7
    static let keyHorizontalSpacing: CGFloat = 6
    static let bottomRowHeight: CGFloat = KeyboardChromeLayout.actionKeyHeight
    static let verticalKeySpacing: CGFloat = 8
    static let secondRowInset: CGFloat = 18
    static let keyCornerRadius: CGFloat = KeyboardChromeLayout.actionKeyCornerRadius
    /// Match the voice surface's shared 20 / 60 / 20 bottom-row geometry.
    static let bottomActionSpacing: CGFloat = KeyboardChromeLayout.actionKeySpacing
    /// Shared top row + three 50 pt key rows + native spacing + bottom row.
    static let totalHeight: CGFloat = KeyboardChromeLayout.totalHeight
    /// Collapsed candidate strip: keep this small so ScrollView doesn't fight ▼.
    static let collapsedBarCandidateLimit = 10
    /// Trailing ▼/▲ control (visual chip + hit pad); lives in an HStack, not over text.
    static let expandChevronHitWidth: CGFloat = 44
    static let expandChevronVisualSize: CGFloat = 34
    static let expandGridColumns = 5
    static let expandCellHeight: CGFloat = 42
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
    /// Key currently under the finger (grid-level touch pad).
    @State private var highlightedKeyID: String?

    static let totalHeight: CGFloat = TypingLayoutMetrics.totalHeight

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
        .frame(maxWidth: KeyboardChromeLayout.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .frame(height: Self.totalHeight)
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
            candidateBar
        } else {
            idleTopBar
        }
    }

    private var hasCandidateContent: Bool {
        !typing.composition.preedit.isEmpty || !typing.composition.candidates.isEmpty
    }

    private var idleTopBar: some View {
        HStack(spacing: Spacing.xs) {
            KeyboardBrandLogo(action: state.openSettings)

            if let err = typing.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.danger)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            KeyboardTopControls(
                state: state,
                typing: typing,
                palette: palette,
                onInsert: onInsert
            )
        }
        .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
    }

    // MARK: - Candidates

    private var candidateBar: some View {
        // HStack (not overlay / safeAreaInset): ▼ never paints over candidate text.
        HStack(spacing: 0) {
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

            if typing.canExpandCandidatePanel {
                expandChevronButton
            } else {
                Color.clear.frame(width: KeyboardTopBarMetrics.nestedHorizontalInset)
            }
        }
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
                    onHighlightChange: { highlightedKeyID = $0 },
                    onCommit: { commitTypingKey($0) },
                    onDeleteFire: { apply(typing.handleKey("⌫")) },
                    onShiftBegan: { typing.beginShiftHold() },
                    onShiftEnded: { typing.endShiftHold() }
                )

                ForEach(layout.keys) { key in
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

    private func makeTypingKeyLayout(size: CGSize) -> TypingKeyLayout {
        let pageLabel = typing.page == .letters ? "123" : "ABC"
        let spaceLabel = typing.language == .chinese ? "空格" : "space"
        let returnLabel: String = {
            switch state.returnKeyRole {
            case .newline: return "return"
            case .send: return ExtL10n.string(state.returnKeyRole.titleKey)
            }
        }()

        let layout = TypingKeyLayoutBuilder.build(
            size: size,
            letterRows: typing.keyRows,
            pageSwitchLabel: pageLabel,
            spaceLabel: spaceLabel,
            returnLabel: returnLabel,
            metrics: TypingKeyLayoutBuilder.Metrics(
                keyRowHeight: TypingLayoutMetrics.keyRowHeight,
                keyRowSpacing: TypingLayoutMetrics.keyRowSpacing,
                keyHorizontalSpacing: TypingLayoutMetrics.keyHorizontalSpacing,
                secondRowInset: TypingLayoutMetrics.secondRowInset,
                bottomRowHeight: TypingLayoutMetrics.bottomRowHeight,
                bottomActionSpacing: TypingLayoutMetrics.bottomActionSpacing,
                gridToBottomSpacing: TypingLayoutMetrics.keyRowSpacing
            ),
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
        let pressed = highlightedKeyID == key.id
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(
                cornerRadius: TypingLayoutMetrics.keyCornerRadius,
                style: .continuous
            )
            .fill(visualKeyFill(for: key, pressed: showPressed))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: TypingLayoutMetrics.keyCornerRadius,
                style: .continuous
            )
            .stroke(visualKeyBorder(for: key), lineWidth: 0.5)
        )
        .shadow(
            color: Color.black.opacity(showPressed ? 0.04 : 0.13),
            radius: showPressed ? 0.5 : 1,
            y: showPressed ? 0 : 1
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
        switch state.returnKeyRole {
        case .newline:
            Image(systemName: "arrow.turn.down.left")
                .font(.system(size: 21, weight: .medium))
        case .send:
            ExtL10n.text(state.returnKeyRole.titleKey)
                .font(.system(size: 15, weight: .semibold))
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
        switch state.returnKeyRole {
        case .newline: return keyFill
        case .send: return sendKeyFill
        }
    }

    private var returnKeyPressedFill: Color {
        switch state.returnKeyRole {
        case .newline: return keyPressedFill
        case .send: return sendKeyPressedFill
        }
    }

    private var returnKeyBorder: Color {
        switch state.returnKeyRole {
        case .newline:
            return palette.divider
        case .send:
            return Color.black.opacity(colorScheme == .dark ? 0.10 : 0.08)
        }
    }

    private var returnKeyAccessibilityLabel: String {
        switch state.returnKeyRole {
        case .newline: return "return"
        case .send: return ExtL10n.string(state.returnKeyRole.titleKey)
        }
    }

    private var returnKeyTextColor: Color {
        switch state.returnKeyRole {
        case .newline:
            return keyTextColor
        case .send:
            return .white
        }
    }

    /// The send key stays recognizable in both appearances without becoming neon.
    private var sendKeyFill: Color {
        NativeKeyboardKeyColors.sendFill(for: colorScheme)
    }

    private var sendKeyPressedFill: Color {
        NativeKeyboardKeyColors.sendPressedFill(for: colorScheme)
    }
}
