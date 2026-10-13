//===-- tsan_interceptors_objc.cpp ----------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file is a part of ThreadSanitizer (TSan), a race detector.
//
// ObjC release-to-dealloc race tracking (Darwin only).
//
// -release publishes the releaser's clock on the object's address and the last
// release (or -dealloc) acquires it, so retained uses happen-before the
// destructor. We swizzle NSObject's -release/-dealloc because objc_release lives
// in the shared cache and can't be interposed; it also forces objc_release off
// the inline refcount path.
//
//===----------------------------------------------------------------------===//

#include "sanitizer_common/sanitizer_platform.h"
#if SANITIZER_APPLE

#  include <dlfcn.h>
#  include <mach-o/dyld.h>
#  include <objc/objc.h>
#  include <objc/runtime.h>

#  include "sanitizer_common/sanitizer_atomic.h"
#  include "sanitizer_common/sanitizer_common.h"
#  include "tsan_flags.h"
#  include "tsan_interface_ann.h"
#  include "tsan_rtl.h"

namespace __tsan {

namespace {
struct ObjCRuntime {
  Class (*getClass)(const char *name);
  SEL (*registerName)(const char *name);
  Method (*getInstanceMethod)(Class cls, SEL sel);
  IMP (*getMethodImplementation)(Method m);
  IMP (*setMethodImplementation)(Method m, IMP imp);
  const char *(*getClassName)(id obj);
  uptr (*rootRetainCount)(id obj);

  bool Resolve() {
    rootRetainCount =
        (decltype(rootRetainCount))dlsym(RTLD_DEFAULT, "_objc_rootRetainCount");
    getClass = (decltype(getClass))dlsym(RTLD_DEFAULT, "objc_getClass");
    registerName = (decltype(registerName))dlsym(RTLD_DEFAULT, "sel_registerName");
    getInstanceMethod =
        (decltype(getInstanceMethod))dlsym(RTLD_DEFAULT, "class_getInstanceMethod");
    getMethodImplementation =
        (decltype(getMethodImplementation))dlsym(RTLD_DEFAULT, "method_getImplementation");
    setMethodImplementation =
        (decltype(setMethodImplementation))dlsym(RTLD_DEFAULT, "method_setImplementation");
    getClassName = (decltype(getClassName))dlsym(RTLD_DEFAULT, "object_getClassName");
    return getClass && registerName && getInstanceMethod &&
           getMethodImplementation && setMethodImplementation;
  }
};

atomic_uint32_t installed;

void *(*dispatch_get_context_fn)(id obj);

// objc_getClass crashes until libobjc has built its class table.
bool IsObjCRuntimeReady() {
  static void **realized_classes = nullptr;
  if (!realized_classes)
    realized_classes = (void **)dlsym(RTLD_DEFAULT, "gdb_objc_realized_classes");
  return realized_classes && *realized_classes != nullptr;
}

ObjCRuntime objc;

typedef void (*ReleaseIMP)(id self, SEL _cmd);
typedef void (*DeallocIMP)(id self, SEL _cmd);
ReleaseIMP orig_release;
DeallocIMP orig_dealloc;

// Tagged pointers have no backing allocation.
bool IsTaggedObjCPointer(id obj) {
  const uptr kPossibleTaggedBits = 0x8000000000000001ull;
  return ((uptr)obj & kPossibleTaggedBits) != 0;
}

// On the last reference, acquire before -dealloc runs: subclass -dealloc bodies
// run before NSObject's. The count isn't read atomically with the decrement, so
// concurrent releases can miss this.
void TsanReleaseTrampoline(id self, SEL _cmd) {
  if (self && !IsTaggedObjCPointer(self)) {
    if (objc.rootRetainCount && objc.rootRetainCount(self) == 1)
      __tsan_acquire((void *)self);
    else
      __tsan_release((void *)self);
  }
  orig_release(self, _cmd);
}

void TsanDeallocTrampoline(id self, SEL _cmd) {
  if (self && !IsTaggedObjCPointer(self))
    __tsan_acquire((void *)self);
  orig_dealloc(self, _cmd);
}

DeallocIMP orig_dispatch_dealloc;

// A dispatch finalizer runs on another thread after the object is freed, and
// TSan drops the object's sync var on free. Carry the edge on the context
// pointer instead; the finalizer wrapper in the libdispatch interceptors
// acquires it.
void TsanDispatchDeallocTrampoline(id self, SEL _cmd) {
  if (self && !IsTaggedObjCPointer(self)) {
    if (dispatch_get_context_fn) {
      void *ctxt = dispatch_get_context_fn(self);
      if (ctxt)
        __tsan_release(ctxt);
    }
    __tsan_acquire((void *)self);
  }
  orig_dispatch_dealloc(self, _cmd);
}

// For classes that override NSObject's -dealloc, e.g. OS_dispatch_object.
bool SwizzleOwnDealloc(const char *cls_name, DeallocIMP *orig, IMP replacement) {
  Class cls = objc.getClass(cls_name);
  if (!cls)
    return false;
  SEL dealloc_sel = objc.registerName("dealloc");
  Method m = objc.getInstanceMethod(cls, dealloc_sel);
  if (!m)
    return false;
  IMP cur = objc.getMethodImplementation(m);
  if (cur == (IMP)&TsanDeallocTrampoline)
    return false;
  *orig = (DeallocIMP)cur;
  objc.setMethodImplementation(m, replacement);
  return true;
}

bool SwizzleNSObject() {
  Class ns = objc.getClass("NSObject");
  if (!ns)
    return false;

  SEL release_sel = objc.registerName("release");
  SEL dealloc_sel = objc.registerName("dealloc");
  Method release_m = objc.getInstanceMethod(ns, release_sel);
  Method dealloc_m = objc.getInstanceMethod(ns, dealloc_sel);
  if (!release_m || !dealloc_m)
    return false;

  orig_release = (ReleaseIMP)objc.getMethodImplementation(release_m);
  orig_dealloc = (DeallocIMP)objc.getMethodImplementation(dealloc_m);

  objc.setMethodImplementation(release_m, (IMP)&TsanReleaseTrampoline);
  objc.setMethodImplementation(dealloc_m, (IMP)&TsanDeallocTrampoline);
  return true;
}

bool TryInstallObjCHooks() {
  if (atomic_load(&installed, memory_order_acquire))
    return true;
  if (!IsObjCRuntimeReady())
    return false;
  if (!objc.Resolve())
    return false;
  if (!SwizzleNSObject())
    return false;

  dispatch_get_context_fn = (decltype(dispatch_get_context_fn))dlsym(
      RTLD_DEFAULT, "dispatch_get_context");
  SwizzleOwnDealloc("OS_dispatch_object", &orig_dispatch_dealloc,
                    (IMP)&TsanDispatchDeallocTrampoline);
  atomic_store(&installed, 1, memory_order_release);
  VPrintf(1, "ThreadSanitizer: ObjC deinit-race tracking installed\n");
  return true;
}

}  // namespace

// Must run from a module constructor: Initialize() can run inside _objc_init,
// before libobjc is usable.
void InstallObjCDeinitRaceTracking() {
  if (!flags()->track_objc_deinit_races)
    return;
  TryInstallObjCHooks();
}

}  // namespace __tsan

#endif  // SANITIZER_APPLE
