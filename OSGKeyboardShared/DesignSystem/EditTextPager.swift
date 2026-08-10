// EditTextPager.swift
// OSGKeyboard · Shared

import SwiftUI

public struct EditTextPager: View {
    @Environment(\.themePalette) private var palette

    private let originalTitle: String
    private let originalText: String
    private let editedTitle: String
    private let editedText: String?
    private let contentBottomInset: CGFloat
    @Binding private var selectedPage: Int?

    public init(
        originalTitle: String,
        originalText: String,
        editedTitle: String,
        editedText: String?,
        contentBottomInset: CGFloat = 0,
        selectedPage: Binding<Int?>
    ) {
        self.originalTitle = originalTitle
        self.originalText = originalText
        self.editedTitle = editedTitle
        self.editedText = editedText
        self.contentBottomInset = contentBottomInset
        self._selectedPage = selectedPage
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    textPage(title: originalTitle, text: originalText)
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: .topLeading
                        )
                        .id(0)

                    if let editedText {
                        textPage(title: editedTitle, text: editedText)
                            .frame(
                                width: proxy.size.width,
                                height: proxy.size.height,
                                alignment: .topLeading
                            )
                            .id(1)
                    }
                }
                .frame(height: proxy.size.height, alignment: .top)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedPage)
            .clipped()
            .accessibilityIdentifier("edit.textPager")
        }
    }

    private func textPage(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
            ScrollView(.vertical) {
                Text(text)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.disabled)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, contentBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A fully clear expanded frame is not a reliable UIKit ScrollView hit
        // target inside keyboard extensions. This imperceptible rendered layer
        // makes the complete page participate in native pan hit testing.
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(text)")
    }
}
