// FlowSessionDarwin.swift
// OSGKeyboard · Shared
//
// Cross-process Darwin notification when the host app changes Flow session
// state (start, extend, end). Keyboard extension listens without polling alone.

import Foundation

public enum FlowSessionDarwin {
    public static let notificationName = "com.osgkeyboard.flow.session.changed"
    /// Posted when the host app writes a transcription result or error.
    public static let transcriptionNotificationName = "com.osgkeyboard.flow.transcription.changed"
    /// Posted when the host app publishes or clears the ready contract.
    public static let hostReadyNotificationName = "com.osgkeyboard.flow.host.ready.changed"

    public static func postSessionChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }

    public static func postTranscriptionChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(transcriptionNotificationName as CFString),
            nil,
            nil,
            true
        )
    }

    public static func postHostReadyChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(hostReadyNotificationName as CFString),
            nil,
            nil,
            true
        )
    }
}

/// Observes Darwin notifications on a background thread; invokes
/// `handler` on the main actor.
public final class FlowSessionDarwinObserver {
    private final class Box: @unchecked Sendable {
        let handler: @MainActor () -> Void
        init(handler: @escaping @MainActor () -> Void) { self.handler = handler }
    }

    private let box: Box
    private let token: UnsafeMutableRawPointer
    private let notificationName: CFString

    public init(
        notificationName: String = FlowSessionDarwin.notificationName,
        handler: @escaping @MainActor () -> Void
    ) {
        let box = Box(handler: handler)
        self.box = box
        self.token = Unmanaged.passRetained(box).toOpaque()
        self.notificationName = notificationName as CFString

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            token,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<Box>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in box.handler() }
            },
            self.notificationName,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            token,
            CFNotificationName(notificationName),
            nil
        )
        Unmanaged<Box>.fromOpaque(token).release()
    }
}
