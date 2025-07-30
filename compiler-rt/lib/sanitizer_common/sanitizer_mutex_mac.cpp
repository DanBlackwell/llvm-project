//===-- sanitizer_mutex_mac.cpp ---------------------------------*- C++ -*-===//
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

#include "sanitizer_platform.h"
#if SANITIZER_APPLE

#  include "sanitizer_internal_defs.h"
#  include "sanitizer_mutex_mac.h"

namespace __sanitizer {

// Used to reinitialize locks if we are the child of a fork
uptr forking_pid;
u8 in_fork;

}  // namespace __sanitizer

#endif  // SANITIZER_APPLE
