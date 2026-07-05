// KeyboardSoundFeedback.swift
// OSGKeyboard · Keyboard Extension
//
// Plays the built-in iOS keyboard click sounds so the custom bottom-row
// keys (space / return / delete) sound identical to the stock keyboard.

import UIKit
import AudioToolbox

/// 让键盘扩展支持系统点击音。`UIDevice.playInputClick()` 只有在「某个
/// 可见的输入视图遵循本协议且返回 true」时才会发声。键盘扩展的根视图
/// 由系统包在一个 `UIInputView` 里，因此对它做追溯遵循即可开启点击音。
extension UIInputView: @retroactive UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}

/// 播放系统键盘原声，让空格 / 回车 / 删除键与系统键盘完全一致。
///
/// 空格 / 回车走官方 `playInputClick()`：这是键盘扩展里最可靠的方式，
/// 会自动尊重「键盘咔嗒声」设置与响铃/静音开关。删除键因为 `playInputClick()`
/// 无法选择其专属音色，改用系统删除音 `1155`。两者都要求扩展已开启
/// 「完全访问」才会发声。
enum KeyboardSoundFeedback {
    /// 删除键音（单次删除，以及长按连删时的每一次删除）。
    private static let deleteSoundID: SystemSoundID = 1155

    /// 普通按键点击音（空格、回车）。
    @MainActor
    static func keyClick() {
        UIDevice.current.playInputClick()
    }

    /// 删除键点击音。
    static func deleteClick() {
        // 未开「完全访问」时该调用是无效空操作，但仍可能短暂阻塞，
        // 放到后台线程可保证连删手感不卡顿。
        DispatchQueue.global(qos: .userInteractive).async {
            AudioServicesPlaySystemSound(deleteSoundID)
        }
    }
}
