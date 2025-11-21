//===--- SanitizerHWCompatCheck.cpp ---------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Hardware compatibility checks for sanitizers that require specific CPU
// features (e.g., MTE for memtag-stack).
//
//===----------------------------------------------------------------------===//

#include "SanitizerHWCompatCheck.h"
#include "CodeGenFunction.h"
#include "CodeGenModule.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalIFunc.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Module.h"

using namespace clang;
using namespace CodeGen;

SanitizerHWCompatCheck::SanitizerHWCompatCheck(CodeGenModule &CGM) : CGM(CGM) {}

void SanitizerHWCompatCheck::emitRuntimeCheck() {
  // Only emit if IFuncs are supported
  if (!CGM.getTarget().supportsIFunc())
    return;

  llvm::LLVMContext &Ctx = CGM.getLLVMContext();
  llvm::FunctionType *FnTy = llvm::FunctionType::get(CGM.VoidTy, false);

  // No-op for memtag version
  llvm::Function *MemtagVersion = llvm::Function::Create(
      FnTy, llvm::GlobalValue::InternalLinkage,
      "__memtag_hw_compat_check._Mmemtag", &CGM.getModule());
  llvm::BasicBlock *MemtagBB = llvm::BasicBlock::Create(Ctx, "", MemtagVersion);
  llvm::IRBuilder<> MemtagBuilder(MemtagBB);
  MemtagBuilder.CreateRetVoid();

  // Default version prints an error and aborts
  llvm::Function *DefaultVersion = llvm::Function::Create(
      FnTy, llvm::GlobalValue::InternalLinkage,
      "__memtag_hw_compat_check.default", &CGM.getModule());
  llvm::BasicBlock *DefaultBB =
      llvm::BasicBlock::Create(Ctx, "", DefaultVersion);
  llvm::IRBuilder<> DefaultBuilder(DefaultBB);

  llvm::StringRef ErrorMsg =
      "This executable was compiled with -fsanitize=memtag* and can only be "
      "run on MTE enabled hardware\n";
  llvm::Constant *ErrorMsgGlobal =
      llvm::ConstantDataArray::getString(Ctx, ErrorMsg, false);
  llvm::GlobalVariable *ErrorMsgVar = new llvm::GlobalVariable(
      CGM.getModule(), ErrorMsgGlobal->getType(), true,
      llvm::GlobalValue::PrivateLinkage, ErrorMsgGlobal, ".str");
  ErrorMsgVar->setUnnamedAddr(llvm::GlobalValue::UnnamedAddr::Global);

  // write() error message
  llvm::FunctionType *WriteFnTy = llvm::FunctionType::get(
      CGM.IntTy, {CGM.IntTy, CGM.VoidPtrTy, CGM.IntPtrTy}, false);
  llvm::FunctionCallee WriteFn = CGM.CreateRuntimeFunction(WriteFnTy, "write");
  DefaultBuilder.CreateCall(
      WriteFn,
      {llvm::ConstantInt::get(CGM.IntTy, 2), // stderr
       ErrorMsgVar, llvm::ConstantInt::get(CGM.IntPtrTy, ErrorMsg.size())});

  // abort()
  llvm::FunctionType *AbortFnTy = llvm::FunctionType::get(CGM.VoidTy, false);
  llvm::FunctionCallee AbortFn = CGM.CreateRuntimeFunction(AbortFnTy, "abort");
  llvm::CallInst *AbortCall = DefaultBuilder.CreateCall(AbortFn);
  AbortCall->setDoesNotReturn();
  DefaultBuilder.CreateUnreachable();

  // Create resolver function using the function-multiversioning infrastructure
  llvm::FunctionType *ResolverFnTy =
      llvm::FunctionType::get(CGM.VoidPtrTy, false);
  llvm::Function *Resolver = llvm::Function::Create(
      ResolverFnTy, llvm::GlobalValue::InternalLinkage,
      "__memtag_hw_compat_check.resolver", &CGM.getModule());
  Resolver->addFnAttr(llvm::Attribute::DisableSanitizerInstrumentation);

  CodeGenFunction CGF(CGM);
  SmallVector<CodeGenFunction::FMVResolverOption, 2> Options;
  Options.emplace_back(CodeGenFunction::FMVResolverOption{
      MemtagVersion, llvm::SmallVector<StringRef, 1>{"memtag"}, std::nullopt});
  Options.emplace_back(CodeGenFunction::FMVResolverOption{
      DefaultVersion, llvm::SmallVector<StringRef, 0>{}, std::nullopt});

  CGF.EmitAArch64MultiVersionResolver(Resolver, Options);

  llvm::GlobalIFunc *IFunc = llvm::GlobalIFunc::create(
      FnTy, 0, llvm::GlobalValue::InternalLinkage, "__memtag_hw_compat_check",
      Resolver, &CGM.getModule());

  // Create a global constructor that calls the check
  llvm::Function *Ctor =
      llvm::Function::Create(FnTy, llvm::GlobalValue::InternalLinkage,
                             "__memtag_hw_compat_check_ctor", &CGM.getModule());

  llvm::BasicBlock *CtorBB = llvm::BasicBlock::Create(Ctx, "", Ctor);
  llvm::IRBuilder<> CtorBuilder(CtorBB);
  CtorBuilder.CreateCall(FnTy, IFunc);
  CtorBuilder.CreateRetVoid();

  // Register as a global constructor
  CGM.AddGlobalCtor(Ctor, 0);
}
