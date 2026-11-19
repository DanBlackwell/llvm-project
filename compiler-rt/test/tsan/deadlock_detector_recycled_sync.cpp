// Test that freeing a heap block containing a mutex without explicitly
// destroying the mutex removes its node from the deadlock detector graph
// when the SyncVar is reset and recycled. Otherwise, reusing the SyncVar for a
// new mutex leaves stale edges in the graph and causes two graph nodes in a
// cycle to share the same DDMutex, triggering a CHECK failure in PrintReport.

// RUN: %clangxx_tsan -O1 %s -o %t
// RUN: %run %t 2>&1 | FileCheck %s --implicit-check-not='ThreadSanitizer'

#include "test.h"
#include <sanitizer/tsan_interface.h>
#include <stdlib.h>

static void lock(void *m) {
  __tsan_mutex_pre_lock(m, 0);
  __tsan_mutex_post_lock(m, 0, 0);
}

static void unlock(void *m) {
  __tsan_mutex_pre_unlock(m, 0);
  __tsan_mutex_post_unlock(m, 0);
}

int main() {
  fprintf(stderr, "Starting.\n");

  char b = 0, c = 0, d = 0;
  void *a = malloc(64);

  // Record edges: B -> A and A -> C.
  lock(&b);
  lock(a);
  unlock(a);
  unlock(&b);

  lock(a);
  lock(&c);
  unlock(&c);
  unlock(a);

  // Free `a` without calling __tsan_mutex_destroy(a). This resets `a`'s
  // SyncVar in MetaMap::FreeRange and returns it to the processor's sync_cache.
  free(a);

  // Locking `d` allocates the recycled SyncVar from sync_cache.
  // Record edges: C -> D and D -> B. Because `a` was freed, B -> A -> C must
  // no longer exist in the deadlock detector graph.
  lock(&c);
  lock(&d);
  unlock(&d);
  unlock(&c);

  lock(&d);
  lock(&b);
  unlock(&b);
  unlock(&d);

  fprintf(stderr, "Done.\n");
  return 0;
}

// CHECK: Starting.
// CHECK: Done.
