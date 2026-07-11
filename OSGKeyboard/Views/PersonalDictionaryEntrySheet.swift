// PersonalDictionaryEntrySheet.swift
// OSGKeyboard · Main App
//
// Minimal add / edit sheet for a single personal-dictionary term.

import SwiftUI
import OSGKeyboardShared

struct PersonalDictionaryEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette: ThemePalette

    let initialTerm: String
    let isEditing: Bool
    let onSave: (String) -> Void

    @State private var term: String = ""
    @FocusState private var termFocused: Bool

    /// 紧凑高度：导航栏 + 输入行 + 说明文字，避免 `.medium` 半屏留白。
    private static let sheetHeight: CGFloat = 208

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField("settings.personalDictionary.add.field", text: $term)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(palette.accent)
                    .focused($termFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsListRow()
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .stroke(termFocused ? palette.accent : palette.divider, lineWidth: termFocused ? 1 : 0.5)
                    )

                Text("settings.personalDictionary.add.footer")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(
                isEditing
                    ? "settings.personalDictionary.edit.title"
                    : "settings.personalDictionary.add.title"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(trimmedTerm.isEmpty)
                        .tint(palette.accent)
                }
            }
            .onAppear {
                term = initialTerm
                termFocused = true
            }
        }
        .presentationDetents([.height(Self.sheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private var trimmedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedTerm.isEmpty else { return }
        onSave(trimmedTerm)
        dismiss()
    }
}
