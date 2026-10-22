// RUN: %clangxx_tsan %s -o %t -fobjc-arc -framework Foundation
// RUN: %deflake %run %t storeWeak 2>&1 | FileCheck %s --check-prefix=CHECK-WRITE-WRITE
// RUN: %deflake %run %t loadWeakRetained 2>&1 | FileCheck %s --check-prefix=CHECK-WRITE-READ
// RUN: %deflake %run %t loadWeak 2>&1 | FileCheck %s --check-prefix=CHECK-WRITE-READ
// RUN: %deflake %run %t initWeak 2>&1 | FileCheck %s --check-prefix=CHECK-WRITE-WRITE
// RUN: %deflake %run %t destroyWeak 2>&1 | FileCheck %s --check-prefix=CHECK-WRITE-WRITE
// RUN: %deflake %run %t copyWeak-src 2>&1 | FileCheck %s --check-prefix=CHECK-WRITE-READ
// RUN: %deflake %run %t copyWeak-dst 2>&1 | FileCheck %s --check-prefix=CHECK-WRITE-WRITE
// RUN: %deflake %run %t moveWeak-src 2>&1 | FileCheck %s --check-prefix=CHECK-WRITE-WRITE
// RUN: %deflake %run %t moveWeak-dst 2>&1 | FileCheck %s --check-prefix=CHECK-WRITE-WRITE

#import <Foundation/Foundation.h>
#include <string.h>

#import "../test.h"

extern "C" {
id objc_loadWeak(void **location);
id objc_initWeak(void **location, id val);
void objc_destroyWeak(void **location);
void objc_copyWeak(void **to, void **from);
void objc_moveWeak(void **to, void **from);
}

@interface MyObj : NSObject {
@public
  __weak id weakField;
}
@end

@implementation MyObj
@end

int main(int argc, char *argv[]) {
  if (argc < 2)
    return 1;
  barrier_init(&barrier, 2);

  MyObj *container = [MyObj new];
  NSObject *v1 = [NSObject new];
  container->weakField = v1;

  pthread_t t1, t2;
  if (strcmp(argv[1], "storeWeak") == 0) {
    pthread_create(&t1, nullptr, [](void *ctx) -> void * {
      MyObj *c = (__bridge MyObj *)ctx;
      c->weakField = nil;
      barrier_wait(&barrier);
      return nullptr;
    }, (__bridge void *)container);
    pthread_create(&t2, nullptr, [](void *ctx) -> void * {
      MyObj *c = (__bridge MyObj *)ctx;
      barrier_wait(&barrier);
      c->weakField = nil;
      return nullptr;
    }, (__bridge void *)container);
  } else if (strcmp(argv[1], "loadWeakRetained") == 0) {
    pthread_create(&t1, nullptr, [](void *ctx) -> void * {
      MyObj *c = (__bridge MyObj *)ctx;
      id tmp = c->weakField;
      (void)tmp;
      barrier_wait(&barrier);
      return nullptr;
    }, (__bridge void *)container);
    pthread_create(&t2, nullptr, [](void *ctx) -> void * {
      MyObj *c = (__bridge MyObj *)ctx;
      barrier_wait(&barrier);
      c->weakField = nil;
      return nullptr;
    }, (__bridge void *)container);
  } else if (strcmp(argv[1], "loadWeak") == 0) {
    void *slot = nullptr;
    objc_initWeak(&slot, v1);
    pthread_create(&t1, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      @autoreleasepool {
        (void)objc_loadWeak(p);
      }
      barrier_wait(&barrier);
      return nullptr;
    }, (void *)&slot);
    pthread_create(&t2, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      barrier_wait(&barrier);
      objc_destroyWeak(p);
      return nullptr;
    }, (void *)&slot);
    pthread_join(t1, nullptr);
    pthread_join(t2, nullptr);
    fprintf(stderr, "Done.\n");
    return 0;
  } else if (strcmp(argv[1], "initWeak") == 0) {
    void *slot = nullptr;
    pthread_create(&t1, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      objc_initWeak(p, nil);
      barrier_wait(&barrier);
      return nullptr;
    }, (void *)&slot);
    pthread_create(&t2, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      barrier_wait(&barrier);
      objc_initWeak(p, nil);
      return nullptr;
    }, (void *)&slot);
    pthread_join(t1, nullptr);
    pthread_join(t2, nullptr);
    fprintf(stderr, "Done.\n");
    return 0;
  } else if (strcmp(argv[1], "destroyWeak") == 0) {
    void *slot = nullptr;
    objc_initWeak(&slot, v1);
    pthread_create(&t1, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      objc_destroyWeak(p);
      barrier_wait(&barrier);
      return nullptr;
    }, (void *)&slot);
    pthread_create(&t2, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      barrier_wait(&barrier);
      objc_destroyWeak(p);
      return nullptr;
    }, (void *)&slot);
    pthread_join(t1, nullptr);
    pthread_join(t2, nullptr);
    fprintf(stderr, "Done.\n");
    return 0;
  } else if (strcmp(argv[1], "copyWeak-src") == 0) {
    void *slots[2] = {nullptr, nullptr};
    objc_initWeak(&slots[0], v1);
    pthread_create(&t1, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      objc_copyWeak(&p[1], &p[0]);
      barrier_wait(&barrier);
      return nullptr;
    }, (void *)slots);
    pthread_create(&t2, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      barrier_wait(&barrier);
      objc_destroyWeak(&p[0]);
      return nullptr;
    }, (void *)slots);
    pthread_join(t1, nullptr);
    pthread_join(t2, nullptr);
    objc_destroyWeak(&slots[1]);
    fprintf(stderr, "Done.\n");
    return 0;
  } else if (strcmp(argv[1], "copyWeak-dst") == 0) {
    void *slots[3] = {nullptr, nullptr, nullptr};
    objc_initWeak(&slots[0], v1);
    objc_initWeak(&slots[1], v1);
    pthread_create(&t1, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      objc_copyWeak(&p[2], &p[0]);
      barrier_wait(&barrier);
      return nullptr;
    }, (void *)slots);
    pthread_create(&t2, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      barrier_wait(&barrier);
      objc_destroyWeak(&p[2]);
      return nullptr;
    }, (void *)slots);
    pthread_join(t1, nullptr);
    pthread_join(t2, nullptr);
    objc_destroyWeak(&slots[0]);
    objc_destroyWeak(&slots[1]);
    fprintf(stderr, "Done.\n");
    return 0;
  } else if (strcmp(argv[1], "moveWeak-src") == 0) {
    void *slots[2] = {nullptr, nullptr};
    objc_initWeak(&slots[0], v1);
    pthread_create(&t1, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      objc_moveWeak(&p[1], &p[0]);
      barrier_wait(&barrier);
      return nullptr;
    }, (void *)slots);
    pthread_create(&t2, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      barrier_wait(&barrier);
      objc_destroyWeak(&p[0]);
      return nullptr;
    }, (void *)slots);
    pthread_join(t1, nullptr);
    pthread_join(t2, nullptr);
    objc_destroyWeak(&slots[1]);
    fprintf(stderr, "Done.\n");
    return 0;
  } else if (strcmp(argv[1], "moveWeak-dst") == 0) {
    void *slots[2] = {nullptr, nullptr};
    objc_initWeak(&slots[0], v1);
    pthread_create(&t1, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      objc_moveWeak(&p[1], &p[0]);
      barrier_wait(&barrier);
      return nullptr;
    }, (void *)slots);
    pthread_create(&t2, nullptr, [](void *ctx) -> void * {
      void **p = (void **)ctx;
      barrier_wait(&barrier);
      objc_destroyWeak(&p[1]);
      return nullptr;
    }, (void *)slots);
    pthread_join(t1, nullptr);
    pthread_join(t2, nullptr);
    fprintf(stderr, "Done.\n");
    return 0;
  }

  pthread_join(t1, nullptr);
  pthread_join(t2, nullptr);
  fprintf(stderr, "Done.\n");
  return 0;
}

// CHECK-WRITE-WRITE: WARNING: ThreadSanitizer: data race
// CHECK-WRITE-WRITE:   Write of size 8
// CHECK-WRITE-WRITE:   Previous write of size 8
// CHECK-WRITE-WRITE: Done.

// CHECK-WRITE-READ: WARNING: ThreadSanitizer: data race
// CHECK-WRITE-READ:   Write of size 8
// CHECK-WRITE-READ:   Previous read of size 8
// CHECK-WRITE-READ: Done.
