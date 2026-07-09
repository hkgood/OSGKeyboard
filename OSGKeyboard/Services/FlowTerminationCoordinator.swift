// FlowTerminationCoordinator.swift
// OSGKeyboard · Main App
//
// 桥接 `UIApplicationDelegate.applicationWillTerminate` 与 `FlowSessionManager`。
// SwiftUI 里 `FlowSessionManager` 是 `@StateObject`，AppDelegate 无法直接持有；
// 此处用弱引用在进程退出窗口（约 5 秒）内同步释放麦克风与 Live Activity。

import Foundation

@MainActor
enum FlowTerminationCoordinator {
    private static weak var sessionManager: FlowSessionManager?

    /// `FlowSessionManager.init()` 注册当前实例。
    static func register(_ manager: FlowSessionManager) {
        sessionManager = manager
    }

    /// 强杀 / 系统终止时调用。必须在主线程执行（`applicationWillTerminate` 保证）。
    static func performSynchronousTerminationCleanup() {
        sessionManager?.prepareForProcessTermination()
        FlowLiveActivityController.endAllSynchronouslyOnTerminate()
    }
}
