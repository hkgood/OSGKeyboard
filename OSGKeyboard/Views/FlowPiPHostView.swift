// FlowPiPHostView.swift
// OSGKeyboard · Main App
//
// Hidden host for the PiP sample-buffer display layer (must live in the window hierarchy).

import SwiftUI
import UIKit

struct FlowPiPHostView: UIViewRepresentable {
    let attach: (UIView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        attach(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        attach(uiView)
    }
}
