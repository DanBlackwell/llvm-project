//===--- SanitizerHWCompatCheck.h - Sanitizer HW Compat Checks ------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CLANG_LIB_CODEGEN_SANITIZERHWCOMPATCHECK_H
#define LLVM_CLANG_LIB_CODEGEN_SANITIZERHWCOMPATCHECK_H

namespace clang {
namespace CodeGen {

class CodeGenModule;

class SanitizerHWCompatCheck {
  SanitizerHWCompatCheck(const SanitizerHWCompatCheck &) = delete;
  void operator=(const SanitizerHWCompatCheck &) = delete;

  CodeGenModule &CGM;

public:
  SanitizerHWCompatCheck(CodeGenModule &CGM);

  /// Emit runtime check for MTE support when memtagging is enabled.
  /// Creates an ifunc-based check that fails early if the binary is run
  /// on hardware without MTE support.
  void emitRuntimeCheck();
};

} // end namespace CodeGen
} // end namespace clang

#endif
