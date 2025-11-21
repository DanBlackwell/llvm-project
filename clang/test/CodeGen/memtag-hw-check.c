// Test that the MTE hardware compatibility check is emitted

// RUN: %clang_cc1 -fsanitize=memtag-stack \
// RUN:   -emit-llvm -o - %s | FileCheck %s

int main(void) {
  return 0;
}

// CHECK: @llvm.global_ctors = {{.*}}@__memtag_hw_compat_check_ctor
// CHECK: @__memtag_hw_compat_check = internal ifunc void (), ptr @__memtag_hw_compat_check.resolver
// CHECK: define internal void @__memtag_hw_compat_check._Mmemtag()
// CHECK: define internal void @__memtag_hw_compat_check.default()
// CHECK: call i32 @write(i32 2,
// CHECK: call void @abort()
// CHECK: define internal ptr @__memtag_hw_compat_check.resolver()
// CHECK: define internal void @__memtag_hw_compat_check_ctor()
