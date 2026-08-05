// BootProbe.m
// OSGKeyboard · Keyboard Extension
//
// Runs at dyld load — before any Swift `KeyboardViewController` init.
// If Console shows this line but never `KVC.init`, Swift/Shared init is the
// killer. If even this line is missing, the extension was jetsammed during
// dyld (usually host coexistence or an oversized Shared+Rime mapping).

#import <Foundation/Foundation.h>
#include <unistd.h>

__attribute__((constructor))
static void OSGKeyboardExtBootProbe(void) {
    NSLog(@"[OSGDiag/boot] dyld.constructor pid=%d", getpid());
}
