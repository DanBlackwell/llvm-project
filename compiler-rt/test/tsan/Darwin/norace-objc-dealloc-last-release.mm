// RUN: %clang_tsan %s -o %t -framework Foundation
// RUN: %env_tsan_opts=track_objc_deinit_races=1 %run %t 2>&1 | FileCheck %s

// A background thread writes an ivar and then releases its reference; the main
// thread drops the last reference. The subclass -dealloc body touches the ivar
// before [super dealloc], so the ordering must come from the last-release
// acquire, not from NSObject's -dealloc.

#import <Foundation/Foundation.h>

#import "../test.h"

@interface MyClass : NSObject {
  long instance_variable;
}
- (void)set:(long)value;
@end

@implementation MyClass
- (void)set:(long)value {
  instance_variable = value;
}
- (void)dealloc {
  instance_variable = 0;
  [super dealloc];
}
@end

int main() {
  barrier_init(&barrier, 2);
  MyClass *obj = [MyClass new];
  [obj retain];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [obj set:1];
    [obj release];
    barrier_wait(&barrier);
  });
  // TSan-invisible barrier: orders the releases without adding a
  // happens-before edge, so only the release edge can order them.
  barrier_wait(&barrier);
  [obj release];  // last release -> -dealloc
  fprintf(stderr, "Done.\n");
  return 0;
}

// CHECK-NOT: WARNING: ThreadSanitizer
// CHECK: Done.
