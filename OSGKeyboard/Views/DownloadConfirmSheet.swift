// DownloadConfirmSheet.swift
// OSGKeyboard · Main App
//
// One-step confirmation before an on-device model download starts.
// Progress and cancellation live on `OnDeviceModelsView` — this
// sheet dismisses as soon as the user confirms.

import SwiftUI
import OSGKeyboardShared

struct DownloadConfirmSheet: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.dismiss) private var dismiss

    let model: OnDeviceModel
    let onConfirm: () -> Void

    private let sheetHeight: CGFloat = 340

    /// Horizontal inset for copy — 50% wider than the default `Spacing.md`.
    private var textHorizontalInset: CGFloat { Spacing.md * 1.5 }

    /// Top inset — 50% more than the previous `Spacing.xl` (24 → 36).
    private var topContentInset: CGFloat { Spacing.xl * 1.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topContent
            Spacer(minLength: Spacing.md)
            actionButtons
        }
        .padding(.horizontal, textHorizontalInset)
        .padding(.top, topContentInset)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, minHeight: sheetHeight, maxHeight: sheetHeight, alignment: .topLeading)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    // MARK: - Top

    private var topContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(AppL10n.format("settings.models.confirm.downloadTitle %@", model.displayName))
                .font(TypeStyle.title3)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppL10n.format("settings.models.confirm.body %lld", model.approximateSizeMB))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: Spacing.sm) {
            Button {
                onConfirm()
                dismiss()
            } label: {
                Text(AppL10n.format("settings.models.confirm.download %lld", model.approximateSizeMB))
            }
            .primaryButton()
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Text("settings.models.confirm.cancel")
            }
            .secondaryButton()
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    DownloadConfirmSheet(model: .qwen3ASR) { }
        .environment(\.themePalette, Palette.light)
}
