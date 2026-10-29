// OSGHostArbiterProbe.m
// OSGKeyboard · Keyboard Extension
//
// 宿主识别探针（所有构建配置均编译），见头文件说明。所有私有符号都在运行时按字符串查找，
// 任何一步找不到都静默放弃，并保证原始实现照常执行。

#import "OSGHostArbiterProbe.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/lock.h>

static NSString *const kArbiterClientClassName = @"_UIKeyboardArbiterClient";
static NSString *const kDestinationClassName = @"_UIKeyboardArbiterClientInputDestination";
static NSString *const kEnabledSelectorName = @"enabled";
static NSString *const kSharedClientSelectorName = @"automaticSharedArbiterClient";
static NSString *const kCheckConnectionSelectorName = @"checkConnection";
static NSString *const kKeyboardChangedSelectorName = @"queue_keyboardChanged:onComplete:";
static NSString *const kSourceBundleIdKey = @"_sourceBundleIdentifier";

static os_unfair_lock sLock = OS_UNFAIR_LOCK_INIT;
static OSGHostArbiterCaptureHandler _Nullable sHandler = nil;
static NSString *_Nullable sLastCapturedBundleId = nil;
static IMP _Nullable sOriginalKeyboardChangedIMP = NULL;
static BOOL sInstalled = NO;

#pragma mark - Trampolines

// 替换 -[_UIKeyboardArbiterClientInputDestination queue_keyboardChanged:onComplete:]。
// bundle ID 在参数 change 上，不在 self 上。
static void OSGSwizzledKeyboardChanged(id self, SEL _cmd, id change, id completion) {
    NSString *bundleId = nil;
    if (change) {
        @try {
            id value = [change valueForKey:kSourceBundleIdKey];
            if ([value isKindOfClass:[NSString class]]) {
                bundleId = [(NSString *)value copy];
            }
        } @catch (__unused NSException *exception) {
            // 字段改名时 KVC 会抛异常；吞掉，保证原始实现继续执行。
        }
    }
    NSString *detail = change ? NSStringFromClass([change class]) : @"change=nil";

    os_unfair_lock_lock(&sLock);
    // 读不到 ID 的回调同样覆盖旧值：宿主已经变了，旧 ID 不能再用。
    sLastCapturedBundleId = bundleId.length > 0 ? bundleId : nil;
    OSGHostArbiterCaptureHandler handler = sHandler;
    os_unfair_lock_unlock(&sLock);
    if (handler) {
        handler(bundleId, detail);
    }

    if (sOriginalKeyboardChangedIMP) {
        ((void (*)(id, SEL, id, id))sOriginalKeyboardChangedIMP)(self, _cmd, change, completion);
    }
}

// 替换 +[_UIKeyboardArbiterClient enabled]：iOS 26.4 用它控制是否派发上面的回调。
static BOOL OSGAlwaysEnabled(__unused id self, __unused SEL _cmd) {
    return YES;
}

@implementation OSGHostArbiterProbe

+ (void)load {
    if (@available(iOS 26.4, *)) {
        [self installHooks];
    }
}

+ (void)installHooks {
    Class clientClass = NSClassFromString(kArbiterClientClassName);
    if (clientClass) {
        Method enabled = class_getClassMethod(clientClass, NSSelectorFromString(kEnabledSelectorName));
        if (enabled) {
            method_setImplementation(enabled, (IMP)&OSGAlwaysEnabled);
        }
    }

    Class destinationClass = NSClassFromString(kDestinationClassName);
    if (!destinationClass) return;
    Method keyboardChanged = class_getInstanceMethod(
        destinationClass,
        NSSelectorFromString(kKeyboardChangedSelectorName)
    );
    if (!keyboardChanged) return;
    sOriginalKeyboardChangedIMP = method_getImplementation(keyboardChanged);
    method_setImplementation(keyboardChanged, (IMP)&OSGSwizzledKeyboardChanged);
    sInstalled = YES;
}

+ (BOOL)isInstalled {
    return sInstalled;
}

+ (NSString *)lastCapturedBundleId {
    os_unfair_lock_lock(&sLock);
    NSString *bundleId = [sLastCapturedBundleId copy];
    os_unfair_lock_unlock(&sLock);
    return bundleId;
}

+ (void)invalidateCapturedBundleId {
    os_unfair_lock_lock(&sLock);
    sLastCapturedBundleId = nil;
    os_unfair_lock_unlock(&sLock);
}

+ (void)setCaptureHandler:(OSGHostArbiterCaptureHandler)handler {
    os_unfair_lock_lock(&sLock);
    sHandler = [handler copy];
    os_unfair_lock_unlock(&sLock);
}

+ (void)pingArbiter {
    Class clientClass = NSClassFromString(kArbiterClientClassName);
    SEL sharedSelector = NSSelectorFromString(kSharedClientSelectorName);
    if (!clientClass || ![clientClass respondsToSelector:sharedSelector]) return;

    id client = ((id (*)(id, SEL))objc_msgSend)(clientClass, sharedSelector);
    SEL checkSelector = NSSelectorFromString(kCheckConnectionSelectorName);
    if (client && [client respondsToSelector:checkSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(client, checkSelector);
    }
}

@end
