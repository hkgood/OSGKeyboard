// OSGKeyboardMacApp.swift
// OSGKeyboard · Mac
//
// Entry point. A borderless, System-Settings-style main window plus a
// rock-solid AppKit status-bar item (NSStatusItem) with a dictation popover.
// Light / dark follows the user's Appearance preference (Settings ▸ General).

import AppKit
import SwiftUI

@main
struct OSGKeyboardMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = MacDictationViewModel.shared

    // Mac-local appearance preference. Drives both the SwiftUI colour scheme
    // and — via `applyToApp` — the AppKit window chrome / popover.
    @AppStorage(MacAppearancePreference.storageKey) private var appearanceRaw = MacAppearancePreference.system.rawValue

    private var appearance: MacAppearancePreference {
        MacAppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        Window("OSGKeyboard", id: "main") {
            MacRootView(viewModel: viewModel)
                .macSystemPalette()
                .environment(\.locale, viewModel.config.uiLanguage.swiftUILocale)
                .preferredColorScheme(appearance.colorScheme)
                .task { await viewModel.onAppear() }
                .onAppear { MacAppearancePreference.applyToApp(appearance) }
                .onChange(of: appearanceRaw) { MacAppearancePreference.applyToApp(appearance) }
                .onReceive(NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)) { _ in
                    viewModel.reloadConfigFromCloud()
                }
                .onReceive(NotificationCenter.default.publisher(for: .personalDictionaryDidSyncFromCloud)) { _ in
                    viewModel.refreshDictionaryFromCloud()
                }
                .onReceive(NotificationCenter.default.publisher(for: .usageStatisticsDidSyncFromCloud)) { _ in
                    viewModel.usageStatistics.reloadFromDisk()
                }
                .onReceive(NotificationCenter.default.publisher(for: .speechHistoryDidSyncFromCloud)) { _ in
                    viewModel.speechHistory.reloadFromDisk()
                }
        }
        // Borderless titlebar → content (sidebar + traffic lights) runs to the
        // very top, matching macOS System Settings.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_024, height: 720)
    }
}

// MARK: - Reopening the main window from AppKit

/// Bridges SwiftUI's `openWindow` action out to AppKit code (the status-bar
/// popover) that has no access to the scene environment.
@MainActor
final class MacWindowBridge {
    static let shared = MacWindowBridge()
    var open: (() -> Void)?
    private init() {}
}

@MainActor
enum MacMainWindow {
    /// Bring the app forward and show the main window, recreating it if the
    /// user had closed it.
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        MacWindowBridge.shared.open?()
    }
}

// MARK: - Status-bar item (AppKit)

/// Owns the menu-bar `NSStatusItem` and its dictation popover. Implemented in
/// AppKit rather than SwiftUI's `MenuBarExtra` because the latter is flaky
/// when combined with a primary `Window` scene (the icon can silently vanish).
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MacAppearancePreference.applyToApp(.current)
        configurePopover()
        configureStatusItem()

        // The menu bar always follows the *system* appearance, so the status
        // item must ignore the app's forced light/dark override. Re-pin the
        // button appearance whenever the system theme flips.
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(systemAppearanceDidChange),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default.removeObserver(self)
    }

    /// Keep the app alive after the last window closes — it lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.makeStatusBarImage()
            button.image?.accessibilityDescription = "OSGKeyboard"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item
        applyStatusItemAppearance()
    }

    /// Builds the menu-bar glyph from the dedicated horizontal status mark.
    /// Height is pinned to the tallest practical menu-bar slot so the logo reads
    /// clearly; width follows the asset's aspect ratio.
    private static func makeStatusBarImage() -> NSImage? {
        guard let image = NSImage(named: "OSGStatusMark")
            ?? NSImage(named: "OSGBrandMark")
            ?? NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "OSGKeyboard") else {
            return nil
        }
        let height: CGFloat = 9
        let aspect = max(image.size.width / max(image.size.height, 1), 1)
        image.size = NSSize(width: height * aspect, height: height)
        image.isTemplate = true
        return image
    }

    /// Pins the status-bar button to the current *system* appearance so its
    /// template image tint matches the real menu-bar background — regardless of
    /// the in-app light/dark preference forced on `NSApp.appearance`.
    private func applyStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?
            .lowercased().contains("dark") ?? false
        button.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    @objc private func systemAppearanceDidChange() {
        // The global-domain default lags the notification by a hair; hop to the
        // next runloop tick so `AppleInterfaceStyle` reflects the new value.
        DispatchQueue.main.async { [weak self] in
            self?.applyStatusItemAppearance()
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 420)
        popover.contentViewController = NSHostingController(rootView: MacMenuBarPopover())
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// SwiftUI content hosted inside the status-bar popover. Shares the single
/// view model and follows the same appearance preference as the main window.
private struct MacMenuBarPopover: View {
    @ObservedObject private var viewModel = MacDictationViewModel.shared
    @AppStorage(MacAppearancePreference.storageKey) private var appearanceRaw = MacAppearancePreference.system.rawValue

    var body: some View {
        MacContentView(viewModel: viewModel)
            .frame(width: 340)
            .macSystemPalette()
            .environment(\.locale, viewModel.config.uiLanguage.swiftUILocale)
            .preferredColorScheme(MacAppearancePreference(rawValue: appearanceRaw)?.colorScheme ?? nil)
    }
}
