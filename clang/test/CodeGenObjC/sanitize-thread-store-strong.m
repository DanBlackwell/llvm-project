// RUN: %clang_cc1 -triple arm64-apple-macosx -emit-llvm -fblocks -fobjc-arc -fsanitize=thread -o - %s | FileCheck %s

// CHECK-LABEL: define{{.*}} void @test_store_strong(
// CHECK: [[DST:%.*]] = load ptr, ptr %dst.addr, align 8
// CHECK-NEXT: call void @__tsan_write8(ptr [[DST]])
// CHECK-NEXT: call void @llvm.objc.storeStrong(ptr [[DST]], ptr %{{.*}})
void test_store_strong(__strong id *dst, id val) {
  *dst = val;
}
