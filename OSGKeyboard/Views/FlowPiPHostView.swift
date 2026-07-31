// FlowPiPHostView.swift
// OSGKeyboard · Main App
//
// Hidden host for the PiP sample-buffer display layer (must live in the window hierarchy).

import SwiftUI
import UIKit

struct FlowPiPHostView: UIViewRepresentable {
    let attach: (UIView) -> Void

    func makeUIView(context: Context) -> FlowPiPHostUIView {
        // Non-trivial size: a 1×1 / fully invisible host often keeps
        // `isPictureInPicturePossible` false for sample-buffer sources.
        let view = FlowPiPHostUIView(frame: CGRect(x: 0, y: 0, width: 64, height: 36))
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isOpaque = false
        view.onMovedToWindow = { [weak view] in
            guard let view else { return }
            attach(view)
        }
        attach(view)
        return view
    }

    func updateUIView(_ uiView: FlowPiPHostUIView, context: Context) {
        attach(uiView)
    }
}

/// Reports window membership so PiP start can wait for a real hierarchy.
final class FlowPiPHostUIView: UIView {
    var onMovedToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onMovedToWindow?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onMovedToWindow?()
    }
}
