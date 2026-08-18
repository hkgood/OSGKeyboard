// BootProbe.m
// OSGKeyboard · Keyboard Extension
//
// Runs at dyld load — before any Swift `KeyboardViewController` init.
// If Console shows this line but never `KVC.init`, Swift/Shared init is the
// killer. If even this line is missing, the extension was jetsammed during
// dyld (usually host coexistence or an oversized Shared+Rime mapping).

#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <mach/task_info.h>
#include <unistd.h>

static double OSGKeyboardExtPhysFootprintMB(void) {
    task_vm_info_data_t info = {0};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(
        mach_task_self(),
        TASK_VM_INFO,
        (task_info_t)&info,
        &count
    );
    if (result != KERN_SUCCESS) {
        return -1;
    }
    return (double)info.phys_footprint / 1048576.0;
}

__attribute__((constructor))
static void OSGKeyboardExtBootProbe(void) {
    NSLog(
        @"[OSGDiag/boot] dyld.constructor pid=%d foot=%.1fMB",
        getpid(),
        OSGKeyboardExtPhysFootprintMB()
    );
}
