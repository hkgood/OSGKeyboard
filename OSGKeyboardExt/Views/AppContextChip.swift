// AppContextChip.swift
// OSGKeyboard · Keyboard Extension
//
// Surfaces the v0.3.0 per-app polish context on the keyboard top
// bar. The LLM prompt already adapts to the detected context (see
// `PolishingService.buildPrompt(for:context:)`), but without a UI
// cue the user has no way to know "I'm currently in code mode" —
// and no way to override the heuristic when it guesses wrong.
//
// Tap the chip → cycle through the five `AppContext` cases. The new
// value is written to `AppGroupStore.setDetectedAppContext(_:at:)`,
// so the next `PolishingService` call picks it up immediately.

import SwiftUI
import OSGKeyboardShared

struct AppContextChip: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var state: KeyboardViewController.State

    var body: some View {
        Menu {
            ForEach(AppContext.allCases, id: \.self) { context in
                Button {
                    state.setAppContext(context)
                } label: {
                    if context == state.appContext {
                        Label(menuLabel(for: context), systemImage: "checkmark")
                    } else {
                        Text(menuLabel(for: context))
                    }
                }
            }
        } label: {
            label
        }
        .menuStyle(.button)
        .accessibilityLabel(ExtL10n.text("keyboard.appContext.a11y"))
        .accessibilityHint(ExtL10n.text("keyboard.appContext.a11yHint"))
    }

    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName(for: state.appContext))
            Text(chipText)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, Spacing.xs + 2)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .background(palette.surfaceElevated, in: Capsule())
        .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
    }

    private var chipText: String {
        ExtL10n.text("keyboard.appContext.chip.\(state.appContext.rawValue)")
    }

    private func menuLabel(for context: AppContext) -> String {
        ExtL10n.text("keyboard.appContext.menu.\(context.rawValue)")
    }

    private func iconName(for context: AppContext) -> String {
        switch context {
        case .code:     return "chevron.left.forwardslash.chevron.right"
        case .email:    return "envelope"
        case .chat:     return "bubble.left"
        case .document: return "doc.text"
        case .unknown:  return "questionmark.circle"
        }
    }
}