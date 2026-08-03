#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable candidate copied out of librime-owned memory.
@interface OSGRimeCandidate : NSObject
@property(nonatomic, copy, readonly) NSString *text;
@property(nonatomic, copy, readonly) NSString *comment;
/// Absolute librime candidate index for `select_candidate` (stable across UI reorder).
@property(nonatomic, readonly) NSInteger index;
- (instancetype)initWithText:(NSString *)text
                     comment:(NSString *)comment
                       index:(NSInteger)index;
@end

/// Immutable runtime snapshot consumed by SwiftUI.
@interface OSGRimeSnapshot : NSObject
@property(nonatomic, copy, readonly) NSString *preedit;
@property(nonatomic, copy, readonly) NSArray<OSGRimeCandidate *> *candidates;
@property(nonatomic, copy, readonly) NSString *commitText;
@property(nonatomic, readonly) BOOL composing;
- (instancetype)initWithPreedit:(NSString *)preedit
                     candidates:(NSArray<OSGRimeCandidate *> *)candidates
                     commitText:(NSString *)commitText
                      composing:(BOOL)composing;
@end

/// Minimal Objective-C++ façade over librime's C API.
///
/// Callers must serialize access. A bridge owns one session; setup and
/// initialization are process-global inside librime.
@interface OSGRimeBridge : NSObject

@property(nonatomic, readonly) BOOL running;

- (instancetype)initWithSharedDataDirectory:(NSString *)sharedDataDirectory
                          userDataDirectory:(NSString *)userDataDirectory
                        distributionVersion:(NSString *)distributionVersion;

- (BOOL)start:(NSError * _Nullable * _Nullable)error;
- (void)stopSession;
- (void)finalizeRuntime;
- (BOOL)deployWithFullCheck:(BOOL)fullCheck
                       error:(NSError * _Nullable * _Nullable)error;

- (BOOL)selectSchema:(NSString *)schemaIdentifier;
- (BOOL)setASCIIMode:(BOOL)enabled;
- (BOOL)processKeyCode:(int)keyCode modifiers:(int)modifiers;
- (BOOL)selectCandidateAtIndex:(NSInteger)index;
- (BOOL)commitComposition;
- (void)clearComposition;
- (NSString *)rawInput;
- (OSGRimeSnapshot *)snapshotWithCandidateLimit:(NSInteger)limit;

@end

/// X11-compatible key symbols used by librime.
FOUNDATION_EXPORT const int OSGRimeKeyBackSpace;
FOUNDATION_EXPORT const int OSGRimeKeyReturn;

NS_ASSUME_NONNULL_END
