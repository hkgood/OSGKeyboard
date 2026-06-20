// PageHeaderRow.swift
// OSGKeyboard · Main App
//
// 左对齐页面标题 + 同行右侧操作区。不用 navigation toolbar 放标题，
// 避免 iOS 把 leading/trailing 项挤进「…」溢出菜单。

import SwiftUI
import OSGKeyboardShared

struct PageHeaderRow<Trailing: View>: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text(title)
                .font(TypeStyle.title2)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }
}

extension PageHeaderRow where Trailing == EmptyView {
    init(title: LocalizedStringKey) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}
