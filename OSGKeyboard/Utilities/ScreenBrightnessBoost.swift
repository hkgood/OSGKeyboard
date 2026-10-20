// ScreenBrightnessBoost.swift
// OSGKeyboard · Main App
//
// Reference-counted full-brightness hold for content another device scans,
// such as the invitation QR code. iOS keeps an app-set brightness after the
// app leaves the foreground, so the hold restores the user's level while the
// app is in the background and reapplies it on return.

import SwiftUI
import UIKit

@MainActor
protocol ScreenBrightnessControlling: AnyObject {
    var brightness: CGFloat { get set }
}

extension UIScreen: ScreenBrightnessControlling {}

@MainActor
final class ScreenBrightnessBoost {
    static let shared = ScreenBrightnessBoost(screenProvider: foregroundScreen)

    private let screenProvider: @MainActor () -> ScreenBrightnessControlling?
    private var holdCount = 0
    private var isInForeground = true
    /// Set only while boosted, so the user's level is captured exactly once.
    private var boost: (screen: ScreenBrightnessControlling, originalBrightness: CGFloat)?

    init(screenProvider: @escaping @MainActor () -> ScreenBrightnessControlling?) {
        self.screenProvider = screenProvider
    }

    func acquire() {
        holdCount += 1
        update()
    }

    func release() {
        guard holdCount > 0 else { return }
        holdCount -= 1
        update()
    }

    func setInForeground(_ inForeground: Bool) {
        isInForeground = inForeground
        update()
    }

    private func update() {
        let wantsBoost = holdCount > 0 && isInForeground
        if wantsBoost, boost == nil, let screen = screenProvider() {
            boost = (screen, screen.brightness)
            screen.brightness = 1
        } else if !wantsBoost, let boost {
            boost.screen.brightness = boost.originalBrightness
            self.boost = nil
        }
    }

    private static func foregroundScreen() -> ScreenBrightnessControlling? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }
}

extension View {
    /// Holds full screen brightness while this view is on screen.
    func boostsScreenBrightness() -> some View {
        modifier(ScreenBrightnessBoostModifier())
    }
}

private struct ScreenBrightnessBoostModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { ScreenBrightnessBoost.shared.acquire() }
            .onDisappear { ScreenBrightnessBoost.shared.release() }
            // `.inactive` is skipped on purpose: Control Center makes the scene
            // inactive, and restoring there would fight a manual adjustment.
            .onChange(of: scenePhase) { _, phase in
                ScreenBrightnessBoost.shared.setInForeground(phase != .background)
            }
    }
}
