// HostBundleProbe.swift
// OSGKeyboard · Keyboard Extension
//
// 识别当前宿主 App 的 bundle ID，供冷启动跳转主 App 后自动跳回。
// 依赖私有 arbiter 探针（`OSGHostArbiterProbe`），Debug / TestFlight / Release 均生效；
// 探针装不上（系统 < 26.4、私有符号改名）时识别结果为 nil，退化为“不自动跳回”。
// 调试日志与首页测试卡片仍只在 DEBUG 编译。

import Foundation
import OSGKeyboardShared

enum HostAppIdentity {
    /// 最近一次识别到的宿主；识别不到、或宿主是 OSG 自己时为 nil。
    static var currentBundleId: String? {
        guard let bundleId = OSGHostArbiterProbe.lastCapturedBundleId,
              !HostAppURLRegistry.isOwnBundleId(bundleId) else {
            return nil
        }
        return bundleId
    }

    /// 键盘弹出时主动让 arbiter 回调一次，避免宿主没变时拿不到最新 ID。
    static func refreshOnPresentation() {
        OSGHostArbiterProbe.pingArbiter()
    }

    /// 跳转主 App（`startflow`）前调用：把当前宿主写进 App Group，主 App 就绪后据此跳回。
    /// 识别不到时写 nil，清掉上一次残留，避免跳回错误的 App。
    static func publishReturnTarget() {
        let bundleId = currentBundleId
        FlowSessionBridge.setPendingHostBundleId(bundleId)
        #if DEBUG
        let returnable = HostAppURLRegistry.lookup(bundleId: bundleId) != nil
        HostBundleProbeLog.append(
            event: "startflow",
            bundleId: bundleId,
            detail: returnable ? "returnable" : "no-return-url"
        )
        #endif
    }

    /// 键盘收起时作废识别结果，下次弹出由新回调重新填充。
    static func invalidate() {
        OSGHostArbiterProbe.invalidateCapturedBundleId()
    }
}

#if DEBUG
/// 调试：把探针回调写进 App Group，主 App 首页的测试卡片读取展示。
enum HostBundleProbe {
    /// 只需安装一次；回调可能来自非主线程，闭包必须是 nonisolated。
    static func installLogging() {
        OSGHostArbiterProbe.setCaptureHandler { @Sendable bundleId, detail in
            HostBundleProbeLog.append(event: "arbiter", bundleId: bundleId, detail: detail)
        }
    }

    /// 键盘弹出时记一条标记，便于把记录和每次弹出对应起来（ping 由 `HostAppIdentity` 负责）。
    static func recordPresentation() {
        HostBundleProbeLog.append(
            event: "appear",
            bundleId: nil,
            detail: OSGHostArbiterProbe.isInstalled ? "hook=installed" : "hook=missing"
        )
    }
}
#endif
