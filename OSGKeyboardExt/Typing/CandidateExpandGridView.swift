// CandidateExpandGridView.swift
// OSGKeyboard · Keyboard Extension
//
// UIKit grid for the expanded Chinese candidate panel. UILabel cells +
// UICollectionView recycling stay far cheaper than hundreds of SwiftUI Buttons.

import OSGKeyboardShared
import SwiftUI
import UIKit

struct CandidateExpandGridView: UIViewRepresentable {
    var candidates: [TypingCandidate]
    var textColor: UIColor
    var dividerColor: UIColor
    var onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.showsVerticalScrollIndicator = true
        view.delaysContentTouches = false
        view.canCancelContentTouches = true
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.register(Cell.self, forCellWithReuseIdentifier: Cell.reuseID)
        context.coordinator.collectionView = view
        return view
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let idsChanged = coordinator.candidates.map(\.id) != candidates.map(\.id)
        let styleChanged =
            coordinator.textColor != textColor || coordinator.dividerColor != dividerColor

        coordinator.onSelect = onSelect
        coordinator.textColor = textColor
        coordinator.dividerColor = dividerColor
        coordinator.candidates = candidates

        if idsChanged || styleChanged {
            uiView.reloadData()
        }
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        let columns = TypingLayoutMetrics.expandGridColumns
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
            heightDimension: .absolute(TypingLayoutMetrics.expandCellHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(TypingLayoutMetrics.expandCellHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            repeatingSubitem: item,
            count: columns
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .zero
        return UICollectionViewCompositionalLayout(section: section)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var candidates: [TypingCandidate] = []
        var textColor: UIColor = .label
        var dividerColor: UIColor = .separator
        var onSelect: (Int) -> Void
        weak var collectionView: UICollectionView?

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            candidates.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: Cell.reuseID,
                for: indexPath
            ) as! Cell
            let index = indexPath.item
            cell.configure(
                text: candidates[index].text,
                emphasized: index == 0,
                textColor: textColor,
                dividerColor: dividerColor,
                showDivider: !isLastRow(index: index)
            )
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            onSelect(indexPath.item)
        }

        private func isLastRow(index: Int) -> Bool {
            let columns = TypingLayoutMetrics.expandGridColumns
            guard !candidates.isEmpty else { return true }
            let row = index / columns
            let lastRow = (candidates.count - 1) / columns
            return row == lastRow
        }
    }

    private final class Cell: UICollectionViewCell {
        static let reuseID = "CandidateExpandCell"

        private let label = UILabel()
        private let divider = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            contentView.backgroundColor = .clear
            isAccessibilityElement = true
            accessibilityTraits = .button

            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)

            divider.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(divider)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
                label.topAnchor.constraint(equalTo: contentView.topAnchor),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                divider.heightAnchor.constraint(equalToConstant: 1.0 / 3.0)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(
            text: String,
            emphasized: Bool,
            textColor: UIColor,
            dividerColor: UIColor,
            showDivider: Bool
        ) {
            label.text = text
            label.textColor = textColor
            label.font = .systemFont(
                ofSize: emphasized ? 19 : 18,
                weight: emphasized ? .medium : .regular
            )
            divider.backgroundColor = dividerColor
            divider.isHidden = !showDivider
            accessibilityLabel = text
        }

        override var isHighlighted: Bool {
            didSet {
                contentView.alpha = isHighlighted ? 0.45 : 1
            }
        }
    }
}
