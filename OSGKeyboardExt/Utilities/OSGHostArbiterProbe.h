// OSGHostArbiterProbe.h
// OSGKeyboard · Keyboard Extension
//
// 宿主识别探针（Debug / TestFlight / Release 均编译）：iOS 26.4+ 通过
// _UIKeyboardArbiterClient 回调读取宿主 App 的 bundle ID，供冷启动后自动跳回。
// 原理参考 editorss/KeyboardHostBundleID（MIT）。
// 必须在 +load 安装，否则可能错过键盘首次切换宿主时的回调。
// 所有私有符号运行时按字符串查找，任何一步失败都静默退化为“识别不到宿主”。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 回调可能在 arbiter 的私有队列上触发，不保证主线程。
typedef void (^OSGHostArbiterCaptureHandler)(NSString *_Nullable bundleId, NSString *_Nullable detail);

@interface OSGHostArbiterProbe : NSObject

/// 钩子是否已成功安装（私有类或方法不存在时为 NO）。
@property (class, nonatomic, readonly) BOOL isInstalled;

/// 最近一次回调读到的宿主 bundle ID；回调读不到或已作废时为 nil。线程安全。
@property (class, nonatomic, readonly, nullable) NSString *lastCapturedBundleId;

/// 作废上一次的识别结果（键盘收起时调用，避免把上一个宿主当成当前宿主）。
+ (void)invalidateCapturedBundleId;

/// 每次 arbiter 回调都会调用；设置为 nil 取消。
+ (void)setCaptureHandler:(nullable OSGHostArbiterCaptureHandler)handler;

/// 主动让 arbiter 检查连接，可能触发一次回调，但不保证。
+ (void)pingArbiter;

@end

NS_ASSUME_NONNULL_END
