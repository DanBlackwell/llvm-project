// RUN: %clang_tsan %s -o %t -framework Foundation
// RUN: %env_tsan_opts=track_objc_deinit_races=1 %deflake %run %t 2>&1 | FileCheck %s

// A background thread uses the object through an unretained reference, so it
// has no release edge, and the main thread's last release runs -dealloc.

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
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [obj set:1];
    barrier_wait(&barrier);
  });
  barrier_wait(&barrier);
  [obj release];
  fprintf(stderr, "Done.\n");
  return 0;
}

// CHECK: WARNING: ThreadSanitizer: data race
// CHECK:   Write of size 8
// CHECK:     #0 {{.*}}dealloc
// CHECK:   Previous write of size 8
// CHECK:     #0 {{.*}}set:
// CHECK: Done.
