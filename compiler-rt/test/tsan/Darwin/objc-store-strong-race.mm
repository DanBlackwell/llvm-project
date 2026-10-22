// RUN: %clangxx_tsan %s -o %t -fobjc-arc -framework Foundation
// RUN: %deflake %run %t 2>&1 | FileCheck %s

#import <Foundation/Foundation.h>

#import "../test.h"

@interface MyObj : NSObject {
@public
  __strong id strongField;
}
@end

@implementation MyObj
@end

int main() {
  barrier_init(&barrier, 2);

  MyObj *container = [MyObj new];

  pthread_t t1, t2;
  pthread_create(&t1, nullptr, [](void *ctx) -> void * {
    MyObj *c = (__bridge MyObj *)ctx;
    c->strongField = nil;
    barrier_wait(&barrier);
    return nullptr;
  }, (__bridge void *)container);
  pthread_create(&t2, nullptr, [](void *ctx) -> void * {
    MyObj *c = (__bridge MyObj *)ctx;
    barrier_wait(&barrier);
    c->strongField = nil;
    return nullptr;
  }, (__bridge void *)container);

  pthread_join(t1, nullptr);
  pthread_join(t2, nullptr);
  fprintf(stderr, "Done.\n");
  return 0;
}

// CHECK: WARNING: ThreadSanitizer: data race
// CHECK:   Write of size 8
// CHECK:   Previous write of size 8
// CHECK: Done.
