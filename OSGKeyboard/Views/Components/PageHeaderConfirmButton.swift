// PageHeaderConfirmButton.swift
// OSGKeyboard · Main App
//
// 圆形黑色图标按钮；确认框以 popover 从按钮向下展开（非底部 action sheet）。

import SwiftUI
import OSGKeyboardShared

struct PageHeaderConfirmButton: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let confirmMessage: LocalizedStringKey
    let confirmActionTitle: LocalizedStringKey
    let onConfirm: () -> Void

    @State private var showConfirm = false

    private let buttonSize: CGFloat = 36

    var body: some View {
        Button {
            showConfirm = true
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: buttonSize, height: buttonSize)
                .background(circleFill, in: Circle())
                .overlay(Circle().stroke(circleStroke, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .popover(isPresented: $showConfirm, arrowEdge: .top) {
            confirmPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    /// 浅色模式：更亮的圆底 + 黑色图标；深色模式：抬升表面色 + 浅色图标。
    private var circleFill: Color {
        switch colorScheme {
        case .dark:
            return palette.surfaceElevated
        default:
            return Color.white
        }
    }

    private var circleStroke: Color {
        colorScheme == .dark ? palette.dividerStrong : palette.divider
    }

    private var iconColor: Color {
        colorScheme == .dark ? palette.textPrimary : .black
    }

    private var confirmPopover: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(confirmTitle)
                .font(TypeStyle.headline)
                .foregroundStyle(palette.textPrimary)

            Text(confirmMessage)
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)
                Button(LocalizedStringKey("common.cancel")) {
                    showConfirm = false
                }
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.textSecondary)

                Button(confirmActionTitle) {
                    showConfirm = false
                    onConfirm()
                }
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.danger)
            }
        }
        .padding(Spacing.md)
        .frame(minWidth: 260)
    }
}
