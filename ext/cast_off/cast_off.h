#include <ruby.h>

#include "vm_core.h"
#include "eval_intern.h"
#include "iseq.h"
#include "gc.h"
#include <ruby/vm.h>
#include <ruby/encoding.h>
#include "vm_insnhelper.h"
#include "vm_insnhelper.c"
#include "vm_exec.h"

#ifdef  USE_INSN_STACK_INCREASE
#undef  USE_INSN_STACK_INCREASE
#endif
#define USE_INSN_STACK_INCREASE 1

#ifdef USE_INSN_RET_NUM
#undef USE_INSN_RET_NUM
#endif
#define USE_INSN_RET_NUM 1

#include "insns_info.inc"
#include "manual_update.h"
