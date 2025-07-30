//===-- sanitizer_mutex_mac.h ----------------------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file is a part of ThreadSanitizer/AddressSanitizer runtime.
//
//===----------------------------------------------------------------------===//

#ifndef SANITIZER_MUTEX_MAC_H
#define SANITIZER_MUTEX_MAC_H

#include "sanitizer_platform.h"
#if SANITIZER_APPLE

#  include <os/lock.h>

#  include "sanitizer_internal_defs.h"
#  include "sanitizer_libc.h"
#  include "sanitizer_thread_safety.h"

namespace __sanitizer {

// This does not need to be atomic nor volatile. It gets set in BeforeFork, and
// unset in AfterFork. For a race to occur, one thread would need to run
// AfterFork (and unset in_fork) in between BeforeFork being run and the actual
// fork occurring on another thread. This cannot occur, as after BeforeFork
// runs, it must have all locks - these must be held by the other thread as
// it has not yet called AfterFork.
//
// Note that this var is used to reinit locks if we are the child of a fork,
// this is also guarded on having a different PID (to the parent); thus other
// threads in the parent will not reinitialize locks even if a fork is in
// progress
extern u8 in_fork;
extern uptr forking_pid;

class SANITIZER_MUTEX StaticSpinMutex {
 public:
  void Init() { internal_lock_ = OS_UNFAIR_LOCK_INIT; }

  void Lock() SANITIZER_ACQUIRE() {
#  pragma clang diagnostic push
#  pragma clang diagnostic ignored "-Wunguarded-availability-new"
    if (&os_unfair_lock_lock_with_flags)
      os_unfair_lock_lock_with_flags(&internal_lock_,
                                     OS_UNFAIR_LOCK_FLAG_ADAPTIVE_SPIN);
    else
      os_unfair_lock_lock(&internal_lock_);
#  pragma clang diagnostic pop
  }

  bool TryLock() SANITIZER_TRY_ACQUIRE(true) {
    return os_unfair_lock_trylock(&internal_lock_);
  }

  void Unlock() SANITIZER_RELEASE() {
    if (UNLIKELY(in_fork && forking_pid != internal_getpid()))
      // If we're the child of a fork we need to reinit all locks
      Init();
    else
      os_unfair_lock_unlock(&internal_lock_);
  }

  void CheckLocked() const SANITIZER_CHECK_LOCKED() {
    os_unfair_lock_assert_owner(&internal_lock_);
  }

 private:
  os_unfair_lock_s internal_lock_;
};

}  // namespace __sanitizer

#endif  // SANITIZER_APPLE
#endif  // SANITIZER_MUTEX_MAC_H
