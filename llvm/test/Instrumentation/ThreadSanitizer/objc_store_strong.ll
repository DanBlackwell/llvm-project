; Check that without the Objective-C module flag, calls are not inspected.
; RUN: opt < %s -passes=tsan -S | FileCheck %s --check-prefix=CHECK-NO-OBJC
; RUN: sed 's/^; MODULE-FLAG:/!llvm.module.flags = !{!0}/' %s | opt -passes=tsan -S | FileCheck %s

target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128"
target triple = "arm64-apple-macosx"

; MODULE-FLAG:
!0 = !{i32 1, !"Objective-C Version", i32 2}

declare void @llvm.objc.storeStrong(ptr, ptr) nounwind
declare void @objc_storeStrong(ptr, ptr) nounwind

define void @test_storeStrong_intrinsic(ptr %addr, ptr %val) nounwind uwtable sanitize_thread {
; CHECK-LABEL: define void @test_storeStrong_intrinsic
; CHECK: call void @__tsan_write8(ptr %addr)
; CHECK-NEXT: call void @llvm.objc.storeStrong(ptr %addr, ptr %val)
; CHECK: ret void
; CHECK-NO-OBJC-LABEL: define void @test_storeStrong_intrinsic
; CHECK-NO-OBJC-NOT: __tsan_write8
; CHECK-NO-OBJC: call void @llvm.objc.storeStrong(ptr %addr, ptr %val)
  call void @llvm.objc.storeStrong(ptr %addr, ptr %val)
  ret void
}

define void @test_storeStrong_call(ptr %addr, ptr %val) nounwind uwtable sanitize_thread {
; CHECK-LABEL: define void @test_storeStrong_call
; CHECK: call void @__tsan_write8(ptr %addr)
; CHECK-NEXT: call void @objc_storeStrong(ptr %addr, ptr %val)
; CHECK: ret void
; CHECK-NO-OBJC-LABEL: define void @test_storeStrong_call
; CHECK-NO-OBJC-NOT: __tsan_write8
; CHECK-NO-OBJC: call void @objc_storeStrong(ptr %addr, ptr %val)
  call void @objc_storeStrong(ptr %addr, ptr %val)
  ret void
}

define void @test_no_sanitize(ptr %addr, ptr %val) nounwind uwtable {
; CHECK-LABEL: define void @test_no_sanitize
; CHECK-NOT: __tsan_write8
; CHECK: call void @llvm.objc.storeStrong(ptr %addr, ptr %val)
; CHECK: ret void
  call void @llvm.objc.storeStrong(ptr %addr, ptr %val)
  ret void
}
