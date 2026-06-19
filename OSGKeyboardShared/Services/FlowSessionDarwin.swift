// FlowSessionDarwin.swift
// OSGKeyboard · Shared
//
// Cross-process Darwin notification when the host app changes Flow session
// state (start, extend, end). Keyboard extension listens without polling alone.

import Foundation

public enum FlowSessionDarwin {
    public static let notificationName = "com.osgkeyboard.flow.session.changed"

    public static func postSessionChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }
}

/// Observes Flow session Darwin notifications on a background thread; invokes
/// `handler` on the main actor.
public final class FlowSessionDarwinObserver {
    private final class Box: @unchecked Sendable {
        let handler: @MainActor () -> Void
        init(handler: @escaping @MainActor () -> Void) { self.handler = handler }
    }

    private let box: Box
    private let token: UnsafeMutableRawPointer

    public init(handler: @escaping @MainActor () -> Void) {
        let box = Box(handler: handler)
        self.box = box
        self.token = Unmanaged.passRetained(box).toOpaque()

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            token,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<Box>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in box.handler() }
            },
            FlowSessionDarwin.notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            token,
            CFNotificationName(FlowSessionDarwin.notificationName as CFString),
            nil
        )
        Unmanaged<Box>.fromOpaque(token).release()
    }
}
