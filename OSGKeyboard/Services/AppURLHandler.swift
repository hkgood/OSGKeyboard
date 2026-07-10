// AppURLHandler.swift
// OSGKeyboard · Main App
//
// iOS 26 URL handling via the UIScene lifecycle. `application(_:open:options:)`
// and `UIApplication.OpenURLOptionsKey.sourceApplication` are deprecated in
// iOS 26; the only supported way to read `sourceApplication` (scheme D
// host-return whitelist) is `UIOpenURLContext.options.sourceApplication` from a
// scene delegate — SwiftUI's `.onOpenURL` does not expose it.

import UIKit
import OSGKeyboardShared

/// Buffers launch/open URLs until the SwiftUI root registers a handler.
///
/// On a cold launch the scene delivers the URL in `scene(_:willConnectTo:)`,
/// which fires *before* the SwiftUI view hierarchy is on screen. Without
/// buffering, that first `osgkeyboard://startflow` (the keyboard → app
/// handoff) would be dropped.
@MainActor
final class AppOpenURLRouter {
    static let shared = AppOpenURLRouter()

    private var handler: ((URL) -> Void)?
    private var pending: [URL] = []

    private init() {}

    /// Register the live handler and flush anything buffered before launch.
    func register(_ handler: @escaping (URL) -> Void) {
        self.handler = handler
        let buffered = pending
        pending.removeAll()
        buffered.forEach(handler)
    }

    func route(_ url: URL) {
        if let handler {
            handler(url)
        } else {
            pending.append(url)
        }
    }
}

final class AppURLHandler: NSObject, UIApplicationDelegate {
    /// SwiftUI `@main` apps get no scene delegate by default. Attach ours so
    /// scene-based URL delivery — the only iOS 26 path to `sourceApplication` —
    /// reaches `AppSceneDelegate`. We deliberately do NOT create a window here;
    /// SwiftUI's `WindowGroup` still owns the UI.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = AppSceneDelegate.self
        return configuration
    }

    /// 后台音频会话仍 running 时，用户强杀常会进入此回调（约 5 秒清理窗口）。
    /// 同步释放麦克风 + 结束 Live Activity，避免重开后「麦克风被占用」。
    func applicationWillTerminate(_ application: UIApplication) {
        MainActor.assumeIsolated {
            FlowTerminationCoordinator.performSynchronousTerminationCleanup()
        }
    }
}

final class AppSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold launch: the URL arrives in the connection options.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        handle(connectionOptions.urlContexts)
    }

    /// Warm open while the app is already running or suspended in memory.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handle(URLContexts)
    }

    private func handle(_ contexts: Set<UIOpenURLContext>) {
        // Extract Sendable primitives up front so we never hop a
        // non-Sendable `UIOpenURLContext` across the actor boundary.
        let items: [(url: URL, source: String?)] = contexts.map {
            ($0.url, $0.options.sourceApplication)
        }
        guard !items.isEmpty else { return }

        // Scene delegate callbacks are delivered on the main thread.
        MainActor.assumeIsolated {
            for item in items {
                // `sourceApplication` is only non-nil when the caller belongs to
                // the same Apple Developer Team (our own keyboard extension) —
                // exactly what the host-return whitelist relies on. Record it
                // ONLY for the `startflow` handoff: overwriting it for every
                // deep link (e.g. `osgkeyboard://settings`) could point a later
                // cold-start "return to host" at the wrong app.
                if let source = item.source, item.url.host == "startflow" {
                    FlowSessionBridge.setPendingHostBundleId(source)
                }
                AppOpenURLRouter.shared.route(item.url)
            }
        }
    }
}
