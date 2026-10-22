; Check that without the Objective-C module flag, calls are not inspected.
; RUN: opt < %s -passes=tsan -S | FileCheck %s --check-prefix=CHECK-NO-OBJC
; RUN: sed 's/^; MODULE-FLAG:/!llvm.module.flags = !{!0}/' %s | opt -passes=tsan -S | FileCheck %s

target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128"
target triple = "arm64-apple-macosx"

; MODULE-FLAG:
!0 = !{i32 1, !"Objective-C Version", i32 2}

declare ptr @llvm.objc.storeWeak(ptr, ptr) nounwind
declare ptr @llvm.objc.loadWeak(ptr) nounwind
declare ptr @llvm.objc.loadWeakRetained(ptr) nounwind
declare ptr @llvm.objc.initWeak(ptr, ptr) nounwind
declare void @llvm.objc.destroyWeak(ptr) nounwind
declare void @llvm.objc.copyWeak(ptr, ptr) nounwind
declare void @llvm.objc.moveWeak(ptr, ptr) nounwind

declare ptr @objc_storeWeak(ptr, ptr) nounwind
declare ptr @objc_loadWeak(ptr) nounwind
declare ptr @objc_loadWeakRetained(ptr) nounwind
declare ptr @objc_initWeak(ptr, ptr) nounwind
declare void @objc_destroyWeak(ptr) nounwind
declare void @objc_copyWeak(ptr, ptr) nounwind
declare void @objc_moveWeak(ptr, ptr) nounwind

define ptr @test_storeWeak_intrinsic(ptr %addr, ptr %val) nounwind uwtable sanitize_thread {
; CHECK-LABEL: define ptr @test_storeWeak_intrinsic
; CHECK: call void @__tsan_write8(ptr %addr)
; CHECK-NEXT: %res = call ptr @llvm.objc.storeWeak(ptr %addr, ptr %val)
; CHECK: ret ptr %res
; CHECK-NO-OBJC-LABEL: define ptr @test_storeWeak_intrinsic
; CHECK-NO-OBJC-NOT: __tsan_write8
; CHECK-NO-OBJC: %res = call ptr @llvm.objc.storeWeak(ptr %addr, ptr %val)
  %res = call ptr @llvm.objc.storeWeak(ptr %addr, ptr %val)
  ret ptr %res
}

define ptr @test_loadWeak_intrinsic(ptr %addr) nounwind uwtable sanitize_thread {
; CHECK-LABEL: define ptr @test_loadWeak_intrinsic
; CHECK: call void @__tsan_read8(ptr %addr)
; CHECK-NEXT: %res = call ptr @llvm.objc.loadWeak(ptr %addr)
; CHECK: ret ptr %res
  %res = call ptr @llvm.objc.loadWeak(ptr %addr)
  ret ptr %res
}

define ptr @test_loadWeakRetained_intrinsic(ptr %addr) nounwind uwtable sanitize_thread {
; CHECK-LABEL: define ptr @test_loadWeakRetained_intrinsic
; CHECK: call void @__tsan_read8(ptr %addr)
; CHECK-NEXT: %res = call ptr @llvm.objc.loadWeakRetained(ptr %addr)
; CHECK: ret ptr %res
  %res = call ptr @llvm.objc.loadWeakRetained(ptr %addr)
  ret ptr %res
}

define ptr @test_initWeak_intrinsic(ptr %addr, ptr %val) nounwind uwtable sanitize_thread {
; CHECK-LABEL: define ptr @test_initWeak_intrinsic
; CHECK: call void @__tsan_write8(ptr %addr)
; CHECK-NEXT: %res = call ptr @llvm.objc.initWeak(ptr %addr, ptr %val)
; CHECK: ret ptr %res
  %res = call ptr @llvm.objc.initWeak(ptr %addr, ptr %val)
  ret ptr %res
}

define void @test_destroyWeak_intrinsic(ptr %addr) nounwind uwtable sanitize_thread {
; CHECK-LABEL: define void @test_destroyWeak_intrinsic
; CHECK: call void @__tsan_write8(ptr %addr)
; CHECK-NEXT: call void @llvm.objc.destroyWeak(ptr %addr)
; CHECK: ret void
  call void @llvm.objc.destroyWeak(ptr %addr)
  ret void
}

define void @test_copyWeak_intrinsic(ptr %dst, ptr %src) nounwind uwtable sanitize_thread {
; CHECK-LABEL: define void @test_copyWeak_intrinsic
; CHECK: call void @__tsan_read8(ptr %src)
; CHECK-NEXT: call void @__tsan_write8(ptr %dst)
; CHECK-NEXT: call void @llvm.objc.copyWeak(ptr %dst, ptr %src)
; CHECK: ret void
  call void @llvm.objc.copyWeak(ptr %dst, ptr %src)
  ret void
}

define void @test_moveWeak_intrinsic(ptr %dst, ptr %src) nounwind uwtable sanitize_thread {
; CHECK-LABEL: define void @test_moveWeak_intrinsic
; CHECK: call void @__tsan_write8(ptr %src)
; CHECK-NEXT: call void @__tsan_write8(ptr %dst)
; CHECK-NEXT: call void @llvm.objc.moveWeak(ptr %dst, ptr %src)
; CHECK: ret void
  call void @llvm.objc.moveWeak(ptr %dst, ptr %src)
  ret void
}

define void @test_direct_calls(ptr %dst, ptr %src, ptr %val) nounwind uwtable sanitize_thread {
; CHECK-LABEL: define void @test_direct_calls
; CHECK: call void @__tsan_write8(ptr %dst)
; CHECK-NEXT: call ptr @objc_storeWeak(ptr %dst, ptr %val)
; CHECK: call void @__tsan_read8(ptr %src)
; CHECK-NEXT: call ptr @objc_loadWeak(ptr %src)
; CHECK: call void @__tsan_read8(ptr %src)
; CHECK-NEXT: call ptr @objc_loadWeakRetained(ptr %src)
; CHECK: call void @__tsan_write8(ptr %dst)
; CHECK-NEXT: call ptr @objc_initWeak(ptr %dst, ptr %val)
; CHECK: call void @__tsan_write8(ptr %dst)
; CHECK-NEXT: call void @objc_destroyWeak(ptr %dst)
; CHECK: call void @__tsan_read8(ptr %src)
; CHECK-NEXT: call void @__tsan_write8(ptr %dst)
; CHECK-NEXT: call void @objc_copyWeak(ptr %dst, ptr %src)
; CHECK: call void @__tsan_write8(ptr %src)
; CHECK-NEXT: call void @__tsan_write8(ptr %dst)
; CHECK-NEXT: call void @objc_moveWeak(ptr %dst, ptr %src)
; CHECK: ret void
  call ptr @objc_storeWeak(ptr %dst, ptr %val)
  call ptr @objc_loadWeak(ptr %src)
  call ptr @objc_loadWeakRetained(ptr %src)
  call ptr @objc_initWeak(ptr %dst, ptr %val)
  call void @objc_destroyWeak(ptr %dst)
  call void @objc_copyWeak(ptr %dst, ptr %src)
  call void @objc_moveWeak(ptr %dst, ptr %src)
  ret void
}
