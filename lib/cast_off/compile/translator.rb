# coding=utf-8

module CastOff
  module Compiler
  class Translator
    include CastOff::Util
    include CastOff::Compiler::Instruction
    include Converter

    Template = ERB.new(<<-'end', 0, '%-', 'io')
%case RUBY_VERSION
%when "1.9.3"
#define RUBY_1_9_3 1
%when "1.9.2"
#define RUBY_1_9_2 1
%else
%  raise(UnsupportedError.new("Unsupported ruby version #{RUBY_VERSION}"))
%end

#include <ruby.h>
#include <ruby/encoding.h>

#include "vm_opts.h"

#include "vm_core.h"
#include "eval_intern.h"
#include "iseq.h"
#include "gc.h"
#include <ruby/vm.h>

/* need for CHECK_STACK_OVERFLOW and vm_push_frame */
#undef GET_VM
#define GET_VM() th->vm
 
#include "vm_insnhelper.h"
#include "vm_insnhelper.c"
#define USE_INSN_STACK_INCREASE 1
#include "insns_info.inc"

#include "manual_update.h"

static VALUE rb_mCastOff;
static VALUE rb_eCastOffExecutionError;
static VALUE rb_mCastOffCompiler;
static VALUE rb_cCastOffSingletonClass;
static VALUE rb_cCastOffConfiguration;
static VALUE rb_cCastOffClassWrapper;
static VALUE rb_cCastOffMethodWrapper;

#include "vm_api.h"
#include "iter_api.h"
#include "unbox_api.h"
%if @configuration.inject_guard?
#define INJECT_GUARD         1
%end
%if @configuration.array_conservative?
#define ARRAY_CONSERVATIVE   1
%end
#include "inline_api.h"

/* FIXME */
#undef RUBY_VM_CHECK_INTS
#define RUBY_VM_CHECK_INTS(th) 

/* Odd, This macro is not in any header files above... */
/* #define hide_obj(obj) do {OBJ_FREEZE(obj); RBASIC(obj)->klass = 0;} while (0) */
#define hide_obj(obj)

static VALUE sampling_table_val = Qnil;
static st_table *sampling_table = NULL;

static void register_sampling_table(VALUE hash)
{
  sampling_table_val = hash;
  rb_gc_register_mark_object(hash);
  sampling_table = RHASH_TBL(hash);
}

static VALUE cast_off_register_sampling_table_<%= signiture() %>(VALUE dummy, VALUE hash)
{
  register_sampling_table(hash);
  return Qnil;
}

static void sampling_variable(VALUE val, VALUE sym)
{
  /* :variable => [klass0, klass1, ...] */
  VALUE klass = rb_class_of(val);
  VALUE hashval;
  VALUE singleton_class_or_module_obj_p = Qfalse;
  st_table *hash;

  if (!st_lookup(sampling_table, (st_data_t)sym, (st_data_t*)&hashval)) {
    hashval = rb_hash_new();
    st_insert(sampling_table, (st_data_t)sym, (st_data_t)hashval);
  }
  hash = RHASH_TBL(hashval);

  if (FL_TEST(klass, FL_SINGLETON)) {
    if (rb_obj_class(val) == rb_cClass || rb_obj_class(val) == rb_cModule) {
      klass = val;
      singleton_class_or_module_obj_p = Qtrue;
    } else {
      klass = rb_cCastOffSingletonClass;
    }
  }

  if (!st_lookup(hash, (st_data_t)klass, 0)) {
    st_insert(hash, (st_data_t)klass, (st_data_t)singleton_class_or_module_obj_p);
  }

  return;
}

static void __sampling_poscall(VALUE val, VALUE method_klass, VALUE method_id)
{
  VALUE klass;
  VALUE mtblval, method_id_hashval, hashval;
  VALUE singleton_class_or_module_obj_p = Qfalse;
  VALUE class_method_or_module_function_p = Qfalse;
  st_table *mtbl, *method_id_hash, *hash;

  if (FL_TEST(method_klass, FL_SINGLETON)) {
    VALUE recv = rb_ivar_get(method_klass, rb_intern("__attached__"));
    if ((rb_obj_class(recv) == rb_cClass || rb_obj_class(recv) == rb_cModule) && rb_class_of(recv) == method_klass) {
      method_klass = recv;
      class_method_or_module_function_p = Qtrue;
    } else {
      method_klass = rb_cCastOffSingletonClass;
    }
  }

  if (!st_lookup(sampling_table, (st_data_t)class_method_or_module_function_p, (st_data_t*)&mtblval)) {
    mtblval = rb_hash_new();
    st_insert(sampling_table, (st_data_t)class_method_or_module_function_p, (st_data_t)mtblval);
  }
  mtbl = RHASH_TBL(mtblval);

  if (!st_lookup(mtbl, (st_data_t)method_klass, (st_data_t*)&method_id_hashval)) {
    method_id_hashval = rb_hash_new();
    st_insert(mtbl, (st_data_t)method_klass, (st_data_t)method_id_hashval);
  }
  method_id_hash = RHASH_TBL(method_id_hashval);
  if (!st_lookup(method_id_hash, (st_data_t)method_id, (st_data_t*)&hashval)) {
    hashval = rb_hash_new();
    st_insert(method_id_hash, (st_data_t)method_id, (st_data_t)hashval);
  }
  hash = RHASH_TBL(hashval);

  klass = rb_class_of(val);
  if (FL_TEST(klass, FL_SINGLETON)) {
    if (rb_obj_class(val) == rb_cClass || rb_obj_class(val) == rb_cModule) {
      klass = val;
      singleton_class_or_module_obj_p = Qtrue;
    } else {
      klass = rb_cCastOffSingletonClass;
    }
  }

  if (!st_lookup(hash, (st_data_t)klass, 0)) {
    st_insert(hash, (st_data_t)klass, (st_data_t)singleton_class_or_module_obj_p);
  }

  return;
}

static void sampling_poscall(VALUE val, VALUE recv, VALUE method_id)
{
  __sampling_poscall(val, rb_class_of(recv), method_id);
}

%@namespace.each_static_decls do |decl|
<%= decl %>
%end

%@fptr.each do |(k, fps)|
%  kids, mid, singleton, convention, argc = k
%  mid = allocate_id(mid)
%  fps.each do |fp|

static VALUE (*<%= fp %>)(ANYARGS);
static VALUE (*<%= function_pointer_wrapper_fptr(fp) %>)(ANYARGS);

%    case convention
%    when -3 # -1
%      args = Array.new(argc)
%      i = 0; args.map!{|a| a = "arg#{i}"; i += 1; a}
%      args_d = args.empty? ? '' : ", VALUE #{args.join(', VALUE ')}"
%      args_c = args.empty? ? '' : ", #{args.join(', ')}"
static VALUE <%= function_pointer_wrapper_func(fp) %>(VALUE recv, ID id, int argc<%= args_d %>)
{
  return <%= function_pointer_wrapper_fptr(fp) %>(recv<%= args_c %>);
}

static VALUE <%= function_pointer_wrapper_func_complex(fp) %>(VALUE recv, ID id, int argc<%= args_d %>)
{
  VALUE argv[<%= [argc, 1].max %>];

%      argc.times do |i|
  argv[<%= i %>] = arg<%= i %>;
%      end
  if (argc != <%= argc %>) {
    rb_bug("<%= function_pointer_wrapper_func(fp) %>: should not be reached");
  }

  return <%= function_pointer_wrapper_fptr(fp) %>(<%= argc %>, argv, recv);
}
%    when -2
static VALUE <%= function_pointer_wrapper_func(fp) %>(VALUE recv, VALUE ary)
{
  return <%= function_pointer_wrapper_fptr(fp) %>(recv, <%= mid %>, RARRAY_LEN(ary), RARRAY_PTR(ary));
}
%    when -1
static VALUE <%= function_pointer_wrapper_func(fp) %>(int argc, VALUE *argv, VALUE recv)
{
  return <%= function_pointer_wrapper_fptr(fp) %>(recv, <%= mid %>, argc, argv);
}
%    when 0..15
%      args = Array.new(convention)
%      i = 0; args.map!{|a| a = "arg#{i}"; i += 1; a}
%      args_d = args.empty? ? '' : ", VALUE #{args.join(', VALUE ')}"
%      args_c = args.empty? ? '' : ", #{args.join(', ')}"
static VALUE <%= function_pointer_wrapper_func(fp) %>(VALUE recv<%= args_d %>)
{
  return <%= function_pointer_wrapper_fptr(fp) %>(recv, <%= mid %>, <%= convention %><%= args_c %>);
}
%    else
%      bug()
%    end
%  end
%end

%@ic.each do |(k, v)|
static struct iseq_inline_cache_entry <%= v %>;
%end

%queue = [@root_iseq]
static rb_iseq_t *<%= @root_iseq %> = NULL;
%until queue.empty?
%  entry = queue.pop()
%  entry.children.each do |(pc, child)|
static rb_iseq_t *<%= child %> = NULL;
%  bug() if queue.include?(child)
%  queue << child
%  end
%end

static rb_iseq_t *cast_off_orig_iseq = NULL;
static VALUE cast_off_register_iseq_<%= signiture() %>(VALUE dummy, VALUE iseqval)
{
  rb_iseq_t *iseq = DATA_PTR(iseqval);
  VALUE insn;

  rb_gc_register_mark_object(iseqval);
  cast_off_orig_iseq = iseq;

%queue = [@root_iseq]
  <%= @root_iseq %> = cast_off_orig_iseq;
%until queue.empty?
%  entry = queue.pop()
%  entry.children.each do |(pc, child)|
  insn = <%= entry %>->iseq[<%= pc %>];
  if (insn != BIN(send)) {
    rb_bug("should not be reached (0), pc = %d", <%= pc %>);
  }
  <%= child %> = (rb_iseq_t*)<%= entry %>->iseq[<%= pc %> + 3];
  if (rb_class_of(<%= child %>->self) != rb_cISeq) {
    rb_bug("should not be reached (1)");
  }
%  bug() if queue.include?(child)
%  queue << child
%  end
%end
  return Qnil;
}

%@declare_constants.each do |(key, value)|
static VALUE <%= key %> = Qundef;
%end

static VALUE cast_off_prefetch_constants_<%= signiture() %>(VALUE self, VALUE binding)
{
%@prefetch_constants.each do |(key, value)|
%  path, singleton_p = value
  <%= key %> = rb_funcall(self, rb_intern("eval"), 2, rb_str_new2("<%= path %>"), binding);
%  if singleton_p
  <%= key %> = rb_class_of(<%= key %>);
%  end
%end

  return Qnil;
}

static void *fbind = NULL;
static void *feval = NULL;
static VALUE cast_off_initialize_fptr_<%= signiture() %>(VALUE dummy)
{
  rb_method_entry_t *me;
  VALUE klass;
  VALUE (*fptr)(ANYARGS);

  me = search_method(rb_mKernel, rb_intern("binding"));
  should_be_cfunc(me);
  fbind = me->def->body.cfunc.func;

  me = search_method(rb_mKernel, rb_intern("eval"));
  should_be_cfunc(me);
  feval = me->def->body.cfunc.func;

%@fptr.each do |(k, v)|
%  kids, mid, singleton, convention, argc = k
%  mid = allocate_id(mid)
%  fps = v
  klass = rb_cObject;
%  kids.each do |kid|
  klass = rb_const_get(klass, rb_intern("<%= kid %>"));
%  end
%  if singleton
  should_be_singleton(klass);
  me = search_method(rb_class_of(klass), <%= mid %>);
%  else
  me = search_method(klass, <%= mid %>);
%  end
  fptr = c_function_pointer(me);
  if (fptr && should_be_call_directly_p(fptr)) {
    int argc = c_function_argc(me);
    if (fptr == fbind) {
      rb_raise(rb_eCastOffExecutionError, "should not use binding in compilation target of CastOff");
    }
    if (fptr == feval) {
      rb_raise(rb_eCastOffExecutionError, "should not use eval in compilation target of CastOff");
    }
    if (argc == <%= convention %>) {
%  fps.each do |fp|
      <%= fp %> = fptr;
%  end
    } else {
%  case convention
%  when -3
      if (0 <= argc && argc <= 15) {
%    fps.each do |fp|
        <%= function_pointer_wrapper_fptr(fp) %> = fptr;
        <%= fp %> = <%= function_pointer_wrapper_func(fp) %>;
%    end
      } else if (argc == -1) {
%    fps.each do |fp|
        <%= function_pointer_wrapper_fptr(fp) %> = fptr;
        <%= fp %> = <%= function_pointer_wrapper_func_complex(fp) %>;
%    end
      } else if (argc == -2) {
%    fps.each do |fp|
        <%= function_pointer_wrapper_fptr(fp) %> = fptr;
        <%= fp %> = (void*)rb_funcall;
%    end
      } else {
        rb_raise(rb_eCastOffExecutionError, "unexpected method(0)");
      }
%  when -1, -2
%    fps.each do |fp|
      <%= function_pointer_wrapper_fptr(fp) %> = (void*)rb_funcall2;
      <%= fp %> = <%= function_pointer_wrapper_func(fp) %>;
%    end
%  when 0..15
%    fps.each do |fp|
      <%= function_pointer_wrapper_fptr(fp) %> = (void*)rb_funcall;
      <%= fp %> = <%= function_pointer_wrapper_func(fp) %>;
%    end
%  else
%      bug("convention = #{convention}")
%  end
    }
  } else {
%  case convention
%  when -3 # rb_funcall
%    fps.each do |fp|
    <%= fp %> = (void*)rb_funcall;
%    end
%  when -1, -2
%    fps.each do |fp|
    <%= function_pointer_wrapper_fptr(fp) %> = (void*)rb_funcall2;
    <%= fp %> = <%= function_pointer_wrapper_func(fp) %>;
%    end
%  when 0..15 # cfunc
%    fps.each do |fp|
    <%= function_pointer_wrapper_fptr(fp) %> = (void*)rb_funcall;
    <%= fp %> = <%= function_pointer_wrapper_func(fp) %>;
%    end
%  else
%      bug("convention = #{convention}")
%  end
  }
%end
  return Qnil;
}

static inline int empty_method_table_p(VALUE klass)
{
  st_table *mtbl = RCLASS_M_TBL(klass);

  if (!mtbl) rb_bug("empty_method_table_p: shoult not be reached");
  return mtbl->num_entries == 0;
}

%@throw_exception_functions.each do |(func, name)|
<%= func.gsub(/<THROW_EXCEPTION_FUNCTION_NAME>/, name) %>
%end

%@class_check_functions.each do |(func, name)|
<%= func.gsub(/<CLASS_CHECK_FUNCTION_NAME>/, name) %>
%end

%@recompilation_functions.each do |(func, name)|
<%= func.gsub(/<RECOMPILATION_FUNCTION_NAME>/, name) %>
%end

%if !inline_block?
static inline void expand_dframe(rb_thread_t *th, long size, rb_iseq_t *iseq, int root_p)
{
  rb_control_frame_t *cfp = th->cfp;
  VALUE *sp = cfp->sp;
  VALUE *dfp = cfp->dfp;
  int i;

  if ((void *)(sp + size + 2) >= (void *)cfp) {
    rb_exc_raise(sysstack_error);
  }

  for (i = 0; i < size; i++) {
    *sp++ = Qnil;
  }
  *sp++ = dfp[-1]; /* cref */
  *sp   = dfp[0];  /* specval */

  if (root_p) {
    cfp->lfp = sp;
  }

  cfp->dfp = sp;
  cfp->sp  = sp + 1;
  cfp->bp  = sp + 1;
  cfp->iseq = iseq;
}

static rb_thread_t *current_thread()
{
  VALUE thval = rb_thread_current();
  rb_thread_t * th = DATA_PTR(thval);

  return th;
}

static VALUE get_self(rb_thread_t *th)
{
  return th->cfp->self;
}

static inline VALUE* fetch_dfp(rb_thread_t *th, int level)
{
  VALUE *dfp;
  int i;

  dfp = th->cfp->dfp;
  for (i = 0; i < level; i++) {
    dfp = GET_PREV_DFP(dfp);
  }
  return dfp;
}

static inline int cast_off_lambda_p(VALUE arg, int argc, VALUE *argv)
{
  VALUE *ptr;
  int i;

  if (rb_class_of(arg) != rb_cArray) {
    return 0;
  }

  ptr = RARRAY_PTR(arg);
  for (i = 0; i < argc; i++) {
    if (ptr[i] != argv[i]) {
      return 0;
    }
  }

  return 1;
}

%if false # for instance_exec, instance_eval, ...
static inline void check_cref(rb_thread_t *th)
{
  rb_control_frame_t *cfp = th->cfp;
  rb_iseq_t *iseq = cfp->iseq;
  VALUE *lfp = cfp->lfp;
  VALUE *dfp = cfp->dfp;
  NODE *cref;

  while (1) {
    if (lfp == dfp) {
      if (!RUBY_VM_NORMAL_ISEQ_P(iseq)) {
        cref = NULL;
        break;
      } else {
        cref = iseq->cref_stack;
        break;
      }
    } else if (dfp[-1] != Qnil) {
      cref = (NODE *)dfp[-1];
      break;
    }
    dfp = GET_PREV_DFP(dfp);
  }

  if (cref && cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL) {
    rb_raise(rb_eCastOffExecutionError, "Currently, CastOff cannot handle constant reference with object(e.g. reciever of BasicObject#instance_exec) context.");
  }
}
%end

static void cast_off_set_block(rb_block_t *block)
{
  VALUE thval = rb_thread_current();
  rb_thread_t * th = DATA_PTR(thval);

  th->passed_block = block;
}

%  @root_iseq.iterate_all_iseq do |iseq|
%    next if iseq.root?
<%= iseq.declare_ifunc_node() %>;
<%= iseq.declare_block_generator() %>;
<%= iseq.declare_ifunc() %>;
%  end

%  @root_iseq.iterate_all_iseq do |iseq|
/* iseq is <%= iseq %> */
%    next if iseq.root?
<%= iseq.define_ifunc_node_generator() %>
<%= iseq.define_block_generator() %>
<%= iseq.define_ifunc() %>
%  end
%end

static VALUE cast_off_register_ifunc_<%= signiture() %>(VALUE dummy)
{
%if !inline_block?
%  @root_iseq.iterate_all_iseq do |iseq|
%  next if iseq.root?
  <%= iseq.ifunc_node_generator() %>();
%  end
%end
  return Qnil;
}

%if @mid
%  if @complex_call
static VALUE <%= this_function_name() %>(int argc, VALUE *argv, VALUE self)
%  else
static VALUE <%= this_function_name() %>(VALUE self<%= @arg_size > 0 ? ", #{arguments.join(", ")}" : "" %>)
%  end
%else
static VALUE <%= this_function_name() %>(VALUE dummy, VALUE self)
%end
{
%if @configuration.enable_trace?
#ifdef CAST_OFF_ENABLE_TRACE
/*  VALUE thval = rb_thread_current(); */
/*  rb_thread_t *th = DATA_PTR(thval); */
/*  VALUE trace_recv, trace_klass;     */
#endif
%end
  /* decl variables */
  VALUE cast_off_argv[<%= @root_iseq.all_argv_size() %>];
  VALUE cast_off_tmp;
  VALUE sampling_tmp;
  rb_thread_t *th;
%if inline_block?
  VALUE thval;
  VALUE specval;
  VALUE *lfp, *dfp;
%else
<%= @root_iseq.declare_dfp %>
%end
%if use_fast_ivar?
  static VALUE __klass = Qundef;
  VALUE *iv_table_ptr = NULL;
%end
%@ivar_index.each do |(iv_id, iv_var)|
  static int <%= iv_var %>_cache;
  int <%= iv_var %>;
%end
%if inline_block?
<%= @loopkey.map{|(k, v)| v.decl? ? "  #{v.decl};" : nil}.compact.join("\n") %>
<%= (@root_iseq.all_local_variable_declarations - arguments).map{|v| "  #{v};"}.join("\n") %>
%else
<%= (@root_iseq.own_local_variable_declarations - arguments).map{|v| "  #{v};"}.join("\n") %>
%end
%if @complex_call
%  arguments.each do |arg|
  <%= arg %> = Qnil;
%  end
%end

%if !inline_block?
  th = current_thread();
  expand_dframe(th, <%= @root_iseq.lvars.size %>, <%= @root_iseq %>, 1);
<%= @root_iseq.update_dfp() %>
%end

%if inline_block?
%  inits = @root_iseq.all_initializations_for_guards()
%else
%  inits = @root_iseq.own_initializations_for_guards()
%end
%bug() if inits.uniq!
<%= inits.join("\n") %>

%if use_fast_ivar?
  if (UNLIKELY(TYPE(self) !=  T_OBJECT)) rb_bug("should not be reached"); /* FIXME should be check compile time */
  if (UNLIKELY((RBASIC(self)->klass) != __klass)) {
    /* iv index cache miss */
    struct st_table *iv_index_tbl = cast_off_get_iv_index_tbl(self);
%  @ivar_index.each do |(iv_id, iv_var)|
    <%= iv_var %>_cache = cast_off_get_iv_index(iv_index_tbl, <%= iv_id %>);
%  end
    __klass = RBASIC(self)->klass;
  }
%  @ivar_index.each do |(iv_id, iv_var)|
  <%= iv_var %> = <%= iv_var %>_cache;
%  end
  iv_table_ptr = cast_off_get_iv_table_ptr(self);
%end

<%= @root_iseq.enclose_begin %>

  /* body */
%if  inline_block?
<%= @root_iseq.all_c_function_body() %>
%else
<%= @root_iseq.own_c_function_body() %>
%end

%iterator = inline_block? ? :iterate_all_guards : :iterate_own_guards
%@root_iseq.__send__(iterator) do |code, insns|
{
  long pc;
  <%= @root_iseq.enclose_end_deoptimize %>
%code_label = "deoptimize_#{code.hash.to_s.gsub(/-/, "_")}"
%  insns.uniq.each do |insn|
<%= insn.guard_label %>:
  pc = <%= insn.pc %>;
  goto <%= code_label %>;
%  end
<%= code_label %>:
%if @mid
  /* override this method (if this method has not redefined yet) */
  /* rb_define_method(...); */
%end
<%= code %>
}
%end
<%= @root_iseq.enclose_end %>
}

%['', '_singleton'].each do |str|
static VALUE cast_off_register<%= str %>_method_<%= signiture() %>(VALUE dummy, VALUE self)
{
%  if @complex_call
  rb_define<%= str %>_method(self, "<%= @mid %>", <%= this_function_name() %>, -1);
%  else
  rb_define<%= str %>_method(self, "<%= @mid %>", <%= this_function_name() %>, <%= @arg_size %>);
%  end
  return Qnil;
}
%end

static VALUE cast_off_generate_proc_<%= signiture() %>(VALUE self, VALUE source_procval)
{
  rb_proc_t *source_procptr = DATA_PTR(source_procval);
  return rb_proc_new(<%= this_function_name() %>, source_procptr->block.self);
}

void Init_<%= signiture() %>(void)
{
%@namespace.each_nonstatic_decls do |decl|
  <%= decl %>
%end
%@namespace.each do |nam|
%  if /\Astatic VALUE\b/.match nam.declaration
  rb_gc_register_address(&<%= nam.name %>);
%  end
%end
%@namespace.each_initializers do |init|
  <%= init %>
%end
  /* finish up */
#define reg(n)                     \
  rb_gc_register_mark_object(n); \
  switch(BUILTIN_TYPE(n)) {      \
  case T_STRING:                 \
  case T_ARRAY:                  \
    hide_obj(n);               \
    break;                     \
  }
#define bye(n)                     \
  n = Qundef

%@namespace.each do |i|
%  if /\bVALUE\b/.match i.declaration
%    if /\Astatic\b/.match i.declaration
  reg(<%= i.name %>);
%    else
  bye(<%= i.name %>);
%    end
%  end
%end
#undef reg

%@ic.each do |(k, v)|
  MEMZERO(&<%= v %>, struct iseq_inline_cache_entry, 1);
%end

  rb_mCastOff = rb_const_get(rb_cObject, rb_intern("CastOff"));
  rb_eCastOffExecutionError = rb_const_get(rb_mCastOff, rb_intern("ExecutionError"));
  rb_mCastOffCompiler = rb_const_get(rb_mCastOff, rb_intern("Compiler"));
  rb_cCastOffSingletonClass = rb_const_get(rb_mCastOffCompiler, rb_intern("SingletonClass"));
  rb_cCastOffConfiguration = rb_const_get(rb_mCastOffCompiler, rb_intern("Configuration"));
  rb_cCastOffClassWrapper = rb_const_get(rb_mCastOffCompiler, rb_intern("ClassWrapper"));
  rb_cCastOffMethodWrapper = rb_const_get(rb_mCastOffCompiler, rb_intern("MethodWrapper"));

%if !@mid
  rb_define_method(rb_mCastOffCompiler, "<%= signiture() %>", <%= this_function_name() %>, 1);
%end
%  ['', '_singleton'].each do |str|
  rb_define_method(rb_mCastOffCompiler, "register<%= str %>_method_<%= signiture() %>", cast_off_register<%= str %>_method_<%= signiture() %>, 1);
%  end
  rb_define_method(rb_mCastOffCompiler, "register_iseq_<%= signiture() %>",   cast_off_register_iseq_<%= signiture() %>, 1);
  rb_define_method(rb_mCastOffCompiler, "register_ifunc_<%= signiture() %>",   cast_off_register_ifunc_<%= signiture() %>, 0);
  rb_define_method(rb_mCastOffCompiler, "register_sampling_table_<%= signiture() %>",   cast_off_register_sampling_table_<%= signiture() %>, 1);
  rb_define_method(rb_mCastOffCompiler, "initialize_fptr_<%= signiture() %>", cast_off_initialize_fptr_<%= signiture() %>, 0);
  rb_define_method(rb_mCastOffCompiler, "prefetch_constants_<%= signiture() %>", cast_off_prefetch_constants_<%= signiture() %>, 1);
}
    end

    attr_reader :reciever_class, :loopkey, :mid, :configuration, :dependency, :root_iseq

    def initialize(root, config, mid, is_proc, block_inlining, suggestion, dependency, manager)
      ary = root.to_a
      @configuration = config
      @suggestion = suggestion
      @dependency = dependency
      @manager = manager
      @block_inlining = block_inlining
      format_check(ary)
      @root_iseq = Iseq.new(root, nil, 0, nil)
      @mid = mid
      if execute?
        # CastOff.execute
        bug() unless @root_iseq.itype == :block
        bug() if @mid
      else
        # CastOff.compile, CastOff.compile_singleton_method
        bug() unless @root_iseq.itype == :method
        bug() unless @mid
      end
      @arg_size = @root_iseq.args.arg_size
      raise(UnsupportedError.new("Currently, CastOff.execute cannot handle arguments")) if execute? && @arg_size > 0
      raise(UnsupportedError.new("Currently, CastOff.execute does not support deoptimization")) if execute? && @configuration.deoptimize?
      bug() if is_proc
      @reciever_class = @configuration.class_of_variable(:self)
      @lvars, @ivars, args, body = prepare(ary, @configuration)
      bug() unless @lvars.empty? || @lvars[0].is_a?(Array)

      initialize_ivar_for_code_generation()
      initialize_ivar_for_suggestion()
      @cfg = CFG.new(body)
      @cfg.gen_ir(self)
    end

    def signiture()
      @manager.signiture
    end

    def target_name()
      @root_iseq.to_name()
    end

    def to_c()
      @cfg.to_c()
      arguments = @lvars.slice(0, @arg_size).map{|l| "VALUE local#{l[1]}_#{l[0]}"} # FIXME
      Template.trigger(binding)
    end

    # for code generation
    def initialize_ivar_for_code_generation()
      @namespace = Namespace.new()
      @fptr = {}
      @ic = {}
      @declare_constants = {}
      @class_check_functions = {}
      @throw_exception_functions = {}
      @recompilation_functions = {}
      @prefetch_constants = {}
      @ivar_index = {}
      @loopkey = {}
    end

    def return_value_class(c, m)
      @configuration.return_value_class(c, m)
    end

    def this_function_name()
      bug() unless signiture()
      "cast_off_#{signiture()}"
    end

    def re_compilation()
      if @configuration.force_inline_block?
        raise(UnsupportedError.new(<<-EOS))

Currently, CastOff cannot inline block in #{@root_iseq.name}.
Source file is #{@root_iseq.source_file}.
Source line is #{@root_iseq.source_line}.
        EOS
      end
      if inline_block?
        raise(ReCompilation.new(''))
      else
        bug()
      end
    end

    def unsupported_or_re_compilation(msg)
      if inline_block?
        re_compilation()
      else
        raise(UnsupportedError.new(msg))
      end
    end

    def allocate_name(name)
      @namespace.new(name).to_s
    end

    STRMAX = 509
    def allocate_id(val)
      case val
      when Symbol
        robject2csource(val, @namespace, STRMAX).name
      when String
        robject2csource(val.intern, @namespace, STRMAX).name
      when Class
        robject2csource(val.to_s.intern, @namespace, STRMAX).name
      else
        bug()
      end
    end

    def allocate_object(val)
      case val
      when Fixnum
          "LONG2FIX(#{val})"
      when Symbol
        name = robject2csource(val, @namespace, STRMAX) # generate ID
        newname = @namespace.new('symop_' + val.to_s)
        newname.depends(name)
        newname.declaration = 'static VALUE'
        newname.definition = "#{newname.declaration} #{newname.name} = Qundef;"
        newname.initialization = "#{newname.name} = #{name.expression};" # get Symbol from ID
        newname.expression = nil
        newname.to_s
      else
        robject2csource(val, @namespace, STRMAX).to_s
      end
    end

    def function_pointer_wrapper_func(fp)
      "#{fp}_funcall_wrapper"
    end

    def function_pointer_wrapper_func_complex(fp)
      "#{fp}_funcall_wrapper_complex"
    end

    def function_pointer_wrapper_fptr(fp)
      "#{fp}_funcall_wrapper_fptr"
    end

    def allocate_function_pointer(klass, mid, convention, argc)
      bug() unless klass.is_a?(ClassWrapper)
      fptr = "fptr_#{klass}_#{@namespace.new(mid).name}"
      fptr.gsub!(/:/, '_')
      ids = klass.to_s.split("::")
      ids.each{|k| bug() if k == ''}
      key = [ids, mid, klass.singleton?, convention, argc]
      entry = @fptr[key] || []
      fptr.concat("_#{argc}_#{entry.size}")
      entry << fptr
      @fptr[key] = entry
      fptr
    end

    def inline_block?
      @block_inlining
    end

    def complex_call?
      @complex_call
    end

    def use_fast_ivar?
      return false # FIXME T_OBJECT であるという指定があったときのみ true にする
      @ivars.size > ROBJECT_EMBED_LEN_MAX
    end

    def get_ivar_index(iv_id, iv_var)
      @ivar_index[iv_id] ||= "iv_index_#{iv_var}"
    end

    def get_ic(name)
      @ic[name] ||= "ic_#{name}"
    end

    def declare_constant(var)
      @declare_constants[var] = true
    end

    def declare_class_check_function(func)
      unless name = @class_check_functions[func]
        idx = @class_check_functions.size()
        name = "class_check_#{idx}"
        @class_check_functions[func] = name
      end
      name
    end

    def declare_throw_exception_function(func)
      unless name = @throw_exception_functions[func]
        idx = @throw_exception_functions.size()
        name = "throw_exception_#{idx}"
        @throw_exception_functions[func] = name
      end
      name
    end

    def declare_recompilation_function(func)
      unless name = @recompilation_functions[func]
        idx = @recompilation_functions.size()
        name = "recompilation_#{idx}"
        @recompilation_functions[func] = name
      end
      name
    end

    def prefetch_constant(var, path, singleton_p)
      if @prefetch_constants[var]
        bug() unless @prefetch_constants[var] == [path, singleton_p]
      else
        @prefetch_constants[var] = [path, singleton_p]
      end
      declare_constant(var)
    end

    C_CLASS_MAP = {
      ClassWrapper.new(Fixnum, true)         => :rb_cFixnum,
      ClassWrapper.new(Bignum, true)         => :rb_cBignum,
      ClassWrapper.new(String, true)         => :rb_cString,
      ClassWrapper.new(Array, true)          => :rb_cArray,
      ClassWrapper.new(Hash, true)           => :rb_cHash,
      ClassWrapper.new(Float, true)          => :rb_cFloat,
      ClassWrapper.new(Object, true)         => :rb_cObject,
      ClassWrapper.new(IO, true)             => :rb_cIO,
      ClassWrapper.new(Module, true)         => :rb_cModule,
      ClassWrapper.new(Proc, true)           => :rb_cProc,
      ClassWrapper.new(RubyVM, true)         => :rb_cRubyVM,
      #ClassWrapper.new(Env, true)            => :rb_cEnv,
      ClassWrapper.new(Time, true)           => :rb_cTime,
      ClassWrapper.new(Symbol, true)         => :rb_cSymbol,
      ClassWrapper.new(Mutex, true)          => :rb_cMutex,
      ClassWrapper.new(Thread, true)         => :rb_cThread,
      ClassWrapper.new(Struct, true)         => :rb_cStruct,
      #ClassWrapper.new(Match, true)          => :rb_cMatch,
      ClassWrapper.new(Regexp, true)         => :rb_cRegexp,
      ClassWrapper.new(Rational, true)       => :rb_cRational,
      ClassWrapper.new(Range, true)          => :rb_cRange,
      ClassWrapper.new(NilClass, true)       => :rb_cNilClass,
      ClassWrapper.new(Random, true)         => :rb_cRandom,
      ClassWrapper.new(Numeric, true)        => :rb_cNumeric,
      ClassWrapper.new(Integer, true)        => :rb_cInteger,
      ClassWrapper.new(Binding, true)        => :rb_cBinding,
      ClassWrapper.new(Method, true)         => :rb_cMethod,
      ClassWrapper.new(File, true)           => :rb_cFile,
      ClassWrapper.new(FalseClass, true)     => :rb_cFalseClass,
      ClassWrapper.new(TrueClass, true)      => :rb_cTrueClass,
      ClassWrapper.new(Class, true)          => :rb_cClass,
      ClassWrapper.new(Encoding, true)       => :rb_cEncoding,
      ClassWrapper.new(Complex, true)        => :rb_cComplex,
      ClassWrapper.new(Dir, true)            => :rb_cDir,
      #ClassWrapper.new(Stat, true)           => :rb_cStat,
      ClassWrapper.new(Enumerator, true)     => :rb_cEnumerator,
      ClassWrapper.new(Fiber, true)          => :rb_cFiber,
      ClassWrapper.new(Data, true)           => :rb_cData,
      #ClassWrapper.new(Generator, true)     => :rb_cGenerator,
      #ClassWrapper.new(Continuation, true)  => :rb_cContinuation,
      #ClassWrapper.new(ISeq, true)          => :rb_cISeq,
      #ClassWrapper.new(UnboundMethod, true) => :rb_cUnboundMethod,
      #ClassWrapper.new(BasicObject, true)   => :rb_cBasicObject,
      #ClassWrapper.new(ARGF, true)          => :rb_cARGF,
      #ClassWrapper.new(Yielder, true)       => :rb_cYielder,
      #ClassWrapper.new(NameErrorMesg, true) => :rb_cNameErrorMesg,
      #ClassWrapper.new(Barrier, true)       => :rb_cBarrier,
    }

    def get_c_classname(klass)
      bug() unless klass.is_a?(ClassWrapper)
      name = C_CLASS_MAP[klass]
      if name
        return name
      else
        if @configuration.has_binding?
          begin
            path = "::#{klass.to_s}"
          rescue CompileError
            return nil
          end
          return nil unless /^[\w:]+$/.match(path)
          if klass.singleton?
            name = allocate_name("singleton_class_#{path}")
            singleton_p = true
          else
            name = allocate_name("class_#{path}")
            singleton_p = false
          end
          prefetch_constant(name, path, singleton_p)
          return name
        else
          return nil
        end
      end
      bug()
    end

    # for suggestion
    MSG_TYPE_NOT_RESOLVED  = "Reciever not resolved."
    COL_TYPE_NOT_RESOLVED  = ["<Reciever>", "<Method>", "<Line>", "<Source>"]
    MSG_LITERAL_DUPLICATED = "These literals have duplicated."
    COL_LITERAL_DUPLICATED = ["<Literal>", "<Reason>", "<Line>", "<Source>"]
    MSG_INLINEAPI_NOT_USED = "Some inline apis have not used."
    COL_INLINEAPI_NOT_USED = ["<Method>", "<Reason>", "<Line>", "<Source>"]

    SUGGESTION_TABLE = [
      [MSG_TYPE_NOT_RESOLVED,  COL_TYPE_NOT_RESOLVED,  :@type_suggestion],
      [MSG_LITERAL_DUPLICATED, COL_LITERAL_DUPLICATED, :@literal_suggestion],
      [MSG_INLINEAPI_NOT_USED, COL_INLINEAPI_NOT_USED, :@inlineapi_suggestion],
    ]

    SUGGESTION_TABLE.each do |(msg, col, ivar)|
      name = ivar.slice(1, ivar.size - 1)
      eval(<<-EOS, binding)
        def add_#{name}(msg)
          #{ivar} << msg
        end
      EOS
    end

    def initialize_ivar_for_suggestion()
      SUGGESTION_TABLE.each{|(msg, col, ivar)| instance_variable_set(ivar, [])}
    end

    def suggest()
      return unless @configuration.development?
      SUGGESTION_TABLE.each do |(msg, col, ivar)|
        val = instance_variable_get(ivar)
        bug() unless val.instance_of?(Array)
        next if val.empty?
        @suggestion.add_suggestion(msg, col, val)
      end
    end

    private

    def execute?
      !@mid
    end

    def gen_embed_label(label, loop_id)
      (label.to_s + "_#{loop_id}").intern
    end

    def embed(p_lvars, p_args, p_excs, p_body, index, iseq_ary, loop_id)
      ary = iseq_ary[10..13]
      c_lvars, c_args, c_excs, c_body = *ary

      # iseq
      c_iseq = nil
      c_depth = nil
      c_body.each do |v|
        case v when InsnInfo
          c_iseq = v.iseq
          c_depth = v.depth
          break
        end
      end
      bug() unless c_iseq && c_depth

      # lvars
      bug() unless (p_lvars & c_lvars).empty?
      lvars = p_lvars + c_lvars

      # args
      re_compilation() if c_iseq.args.block? && inline_block?
      re_compilation() if c_iseq.args.opt? && inline_block?
      c_args = c_lvars.slice(0, c_iseq.args.arg_size)

      # excs
      excs = p_excs + c_excs.map do |(t, i, s, e, c, sp)|
        # type, iseq, start, end, cont, sp
        # rename labels(start, end, cont)
        s = gen_embed_label(s, loop_id)
        e = gen_embed_label(e, loop_id)
        c = gen_embed_label(c, loop_id)
        [t, i, s, e, c, sp]
      end

      # body
      bug() unless p_body[index].get_iseq() == iseq_ary
      b = []
      insn = p_body[index]
      # CastOff supports send instruction only
      # CastOff doesn't support :defineclass, :invokesuper, :putiseq
      bug() unless insn.op == :send
      loop_label = gen_embed_label(:loop, loop_id)
      cont_label = gen_embed_label(:cont, loop_id)
      bug() unless insn.depth
      prep = InsnInfo.new([:cast_off_prep, loop_id, c_args, insn], insn.iseq, insn.pc, insn.line, false, insn.depth)
      b << prep
      b << InsnInfo.new([:cast_off_enter_block, loop_label], insn.iseq, -1, -1, true, prep.depth + prep.stack_usage())
      b << cont_label
      bug() unless c_depth + 1 == prep.depth + prep.stack_usage()
      b << InsnInfo.new([:cast_off_cont, loop_id, c_args, insn], c_iseq, -1, -1, true, c_depth)
      if c_iseq.args.opt?
        bug() if inline_block?
        c_args_opts = c_iseq.args.opts.map{|l| gen_embed_label(l, loop_id) }
        b << InsnInfo.new([:cast_off_fetch_args, nil], c_iseq, -1, -1, true, c_depth)
        b << InsnInfo.new([:cast_off_handle_optional_args, c_args_opts, c_iseq.args.argc, false], c_iseq, -1, -1, true, c_depth + 1)
      end

      is_break = false
      break_label = gen_embed_label(:break, loop_id)
      c_body.each do |v|
        case v
        when InsnInfo
          bug() unless v.support?
          if label = v.get_label()
            v = v.dup()
            v.set_label(gen_embed_label(label, loop_id))
          end
          case v.op
          when :leave
            # leave => jump
            b << InsnInfo.new([:cast_off_leave_block, loop_label], c_iseq, -1, -1, true, v.depth)
          when :throw
            type, state, flag, level = v.get_throw_info()
            bug() unless flag == 0
            case type
            when :return
              # nothing to do
              b << v
              if !inline_block?
                if @mid
                  @root_iseq.catch_exception(:return, nil, nil, nil)
                else
                  raise(UnsupportedError, "Currently, CastOff.execute doesn't support return statement when block inlining is disabled") 
                end
              end
            when :break
              is_break = true
              cfg = CFG.new(c_body)
              stack_depth = cfg.find_insn_stack_depth(v)
              bug() unless stack_depth
              bug() unless stack_depth > 0
              num = stack_depth - 1
              if num > 0
                b << InsnInfo.new([:setn, num], c_iseq, -1, -1, true, v.depth)
                num.times do |i|
                  b << InsnInfo.new([:pop], c_iseq, -1, -1, true, v.depth - i)
                end
              end
              bug() unless c_iseq.parent_pc == insn.pc + insn.size
              b << InsnInfo.new([:cast_off_break_block, break_label, v.argv[0], c_iseq.parent_pc], c_iseq, -1, -1, true, c_depth + 1)
              insn.iseq.catch_exception(:break, c_iseq.parent_pc, break_label, insn.depth + insn.stack_usage()) if !inline_block?
            else
              bug()
            end
          else
            b << v
          end
        when Symbol
          b << gen_embed_label(v, loop_id)
        else
          bug()
        end
      end
      b << loop_label
      b << InsnInfo.new([:cast_off_loop, loop_id, c_args, insn], insn.iseq, -1, -1, true, c_depth + 1)
      b << InsnInfo.new([:cast_off_continue_loop, cont_label], insn.iseq, -1, -1, true, c_depth + 1)
      b << InsnInfo.new([:cast_off_finl, loop_id, c_args, insn], insn.iseq, -1, -1, true, c_depth)
      b << break_label if is_break
      body = p_body.slice(0, index) + b + p_body.slice(index + 1, p_body.size - (index + 1))

      [lvars, p_args, excs, body]
    end

    def get_var_index(locals, index)
      locals.size - (index - 2) - 1
    end

    def prepare_local_variable(ary, configuration, lvars_table, depth, varid, current_iseq)
      misc = ary[4]
      lvars_size = misc[:local_size] - 1
      bug() unless lvars_size.is_a?(Integer)
      ary = ary[10..13]
      lvars, args, dummy, body = *ary
      op_idx = -(lvars_size + 1) # lvar を参照するための get/setlocal, get/setdynamic オペランド, dfp/lfp からの index
      lvars.map! do |l|
        var = [l, varid, op_idx, depth, configuration.class_of_variable(l)]
        varid += 1
        op_idx += 1
        var
      end
      if lvars.size < lvars_size
        #bug() unless depth > 0
        #def pma1((a), &b) end <= depth == 0 but lvars_size == 4, lvars = [:a, :b]

        # for block
        (lvars_size - lvars.size).times do
          lvars << [:__lvar, varid, op_idx, depth, nil]
          varid += 1
          op_idx += 1
        end
      end
      bug() unless op_idx == -1
      current_iseq.set_local_variables(lvars)
      lvars_table << lvars
      body.each do |v|
        case v when InsnInfo
          bug() unless v.support?
          if iseq_ary = v.get_iseq()
            child_iseq = current_iseq.children[v.pc]
            bug() unless child_iseq.is_a?(Iseq)
            varid = prepare_local_variable(iseq_ary, configuration, lvars_table.dup, depth + 1, varid, child_iseq)
          end
          case v.op
          when :getdynamic, :setdynamic, :getlocal, :setlocal
            case v.op
            when :getdynamic
              idx, lv = *v.argv
              if inline_block?
                insn = [:cast_off_getlvar]
              else
                insn = [:cast_off_getdvar]
              end
            when :setdynamic
              idx, lv = *v.argv
              if inline_block?
                insn = [:cast_off_setlvar]
              else
                insn = [:cast_off_setdvar]
              end
            when :getlocal
              idx = v.argv[0]
              lv = depth # set/getlocal uses lfp
              if inline_block?
                insn = [:cast_off_getlvar]
              else
                insn = [:cast_off_getdvar]
              end
            when :setlocal
              idx = v.argv[0]
              lv = depth # set/getlocal uses lfp
              if inline_block?
                insn = [:cast_off_setlvar]
              else
                insn = [:cast_off_setdvar]
              end
            else
              bug()
            end
            raise(UnsupportedError.new(<<-EOS)) if 0 > depth - lv
Unsupported operation(#{v.source}).
Currently, CastOff doesn't support variables defined in an outer block.
            EOS
            var_index = get_var_index(lvars_table[depth - lv], idx)
            bug() unless 0 <= var_index && var_index <= lvars_table[depth - lv].size()
            lvar = lvars_table[depth - lv][var_index]
            bug() unless lvar
            bug() unless (depth - lv) == lvar[3] # name, id, op_idx, depth, types
            insn.concat(lvar)
            bug() unless insn.size() == 6
            v.update(insn)
          when :getinstancevariable, :setinstancevariable
            id, ic = *v.argv
            case v.op
            when :getinstancevariable
              insn = [:cast_off_getivar]
            when :setinstancevariable
              insn = [:cast_off_setivar]
            else
              bug()
            end
            ivar = [id, configuration.class_of_variable(id)]
            insn.concat(ivar)
            bug() if insn.size != 3
            v.update(insn)
          when :getclassvariable, :setclassvariable
            id = v.argv[0]
            case v.op
            when :getclassvariable
              insn = [:cast_off_getcvar]
            when :setclassvariable
              insn = [:cast_off_setcvar]
            else
              bug()
            end
            cvar = [id, configuration.class_of_variable(id)]
            insn.concat(cvar)
            bug() if insn.size != 3
            v.update(insn)
          when :getglobal, :setglobal
            gentry = v.argv[0]
            case v.op
            when :getglobal
              insn = [:cast_off_getgvar]
            when :setglobal
              insn = [:cast_off_setgvar]
            else
              bug()
            end
            gvar = [gentry, configuration.class_of_variable(gentry)]
            insn.concat(gvar)
            bug() if insn.size != 3
            v.update(insn)
          end
        end
      end
      varid
    end

    def prepare_constant(body)
      nb = []
      pre = nil
      buf = nil
      body.each do |v|
        case v
        when InsnInfo
          case v.op
          when :getconstant
            bug() unless pre
            preop = pre.op
            if buf
              bug() unless preop == :getconstant
            else
              case preop
              when :putobject
                bug() unless pre.argv[0] == Object
                flag = true
              when :putnil
                flag = false
              else
                raise(UnsupportedError.new(<<-EOS))

Currently, CastOff cannot handle this constant reference.
--- source code ---
#{v.source}
                EOS
              end
              nb << InsnInfo.new([:pop], v.iseq, -1, -1, true, v.depth) # pop Object or nil
              n_insn = InsnInfo.new([:cast_off_getconst, flag], v.iseq, -1, -1, true, v.depth - 1)
              nb << n_insn
              buf = n_insn.argv
            end
            buf.concat(v.argv) # append id
          else
            buf = nil
            nb << v
          end
          pre = v
        else
          pre = nil
          nb << v
        end
      end
      nb.each do |v|
        case v when InsnInfo
          bug() if v.op == :getconstant
        end
      end
      nb
    end

    def prepare_branch_instruction_and_line_no(ary)
      nb = []
      body = ary[13]
      body.each do |v|
        case v
        when InsnInfo # instruction
          bug() unless v.support?
          if iseq_ary = v.get_iseq()
            prepare_branch_instruction_and_line_no(iseq_ary)
          end
          if !v.ignore?
            case v.op
            when :getinlinecache
              nb << InsnInfo.new([:putnil], v.iseq, -1, -1, true, v.depth)
            when :opt_case_dispatch
              nb << InsnInfo.new([:pop], v.iseq, -1, -1, true, v.depth)
            else
              nb << v
            end
          end
        when Symbol  # label
          nb << v
        when Integer # line
          # ignore
        else
          raise(CompileError, 'wrong format iseq')
        end
      end
      ary[13] = nb
    end

    def prepare_throw_instruction(body)
      nb = body.map do |v|
        case v
        when InsnInfo
          case v.op
          when :throw
            type, state, flag, level = v.get_throw_info()
            bug() unless flag == 0
            case type
            when :return
              if execute?
                v
              else
                inline_block? ? InsnInfo.new([:leave], v.iseq, -1, -1, true, v.depth) : v
              end
            when :break
              bug() # should not be reached
            else
              bug()
            end
          else
            v
          end
        else
          v
        end
      end
      nb
    end

    def annotate_instruction(ary, current_iseq, current_depth)
      bug() unless current_iseq.is_a?(Iseq)
      excs = ary[12]
      body = ary[13]

      excs.each do |(t, i, s, e, c, sp)|
        # type, iseq, start, end, cont, sp
        case t when :rescue, :ensure
          # CastOff doesn't support rescue and ensure.
          raise(UnsupportedError, "Currently, CastOff cannot handle #{t}") 
        end
      end

      pc = 0
      line = -1
      body.map! do |v|
        case v
        when Array
          bug() if pc < 0
          insn = InsnInfo.new(v, current_iseq, pc, line)
          raise(UnsupportedError, insn.get_unsupport_message()) unless insn.support?
          pc += v.size()
          insn
        when Symbol
          pc = /label_/.match(v).post_match.to_i
          v
        when Integer
          line = v
          nil
        end
      end
      body.compact!()

      cfg = CFG.new(body)
      body.each do |v|
        next unless v.instance_of?(InsnInfo)
        d = cfg.find_insn_stack_depth(v)
        v.set_stack_depth(d + current_depth) if d
      end

      body.each do |v|
        next unless v.instance_of?(InsnInfo)
        if iseq_ary = v.get_iseq()
          bug() unless v.op == :send
          child_iseq = Iseq.new(get_child_iseq(current_iseq.iseq, v.pc), current_iseq, v.depth + v.stack_usage - 1, v.pc + v.size)
          current_iseq.add(child_iseq, v.pc)
          annotate_instruction(iseq_ary, child_iseq, v.depth + v.stack_usage - 1)
        end
      end
    end

    def prepare(ary, configuration)
      annotate_instruction(ary, @root_iseq, 0)
      prepare_local_variable(ary, configuration, [], 0, 0, @root_iseq)
      prepare_branch_instruction_and_line_no(ary)
      ary = ary[10..13]
      lvars, args, excs, body = *ary
      loop_id = 0
      continue = true
      while continue
        continue = false
        body.each_with_index do |v, index|
          case v when InsnInfo
            bug() unless v.support?
            if iseq_ary = v.get_iseq()
              lvars, args, excs, body = embed(lvars, args, excs, body, index, iseq_ary, loop_id)
              continue = true
              break
            end
          end
        end
        loop_id += 1
      end

      body = prepare_throw_instruction(body)
      body = prepare_constant(body)

      ivars = []
      body.each do |v|
        case v when InsnInfo
          case v.op
          when :cast_off_getivar, :cast_off_setivar
            ivars << v.argv[0]
          end
        end
      end
      ivars.uniq!

      opts = @root_iseq.args.opt? ? @root_iseq.args.opts : false
      rest_index = @root_iseq.args.rest? ? @root_iseq.args.rest_index : false
      block_argument_p = @root_iseq.args.block?
      post_len = @root_iseq.args.post? ? @root_iseq.args.post_len : false
      @complex_call = opts || rest_index || block_argument_p || post_len
      if @complex_call
        block = block_argument_p ? '&' : ''
        post = post_len ? post_len : 0
        rest = rest_index ? '*' : ''
        opt = opts ? opts.size() - 1 : 0
        must = @root_iseq.args.argc
        if opts
          body.unshift(InsnInfo.new([:cast_off_handle_optional_args, opts, must, rest_index], @root_iseq, -1, -1, true, 1))
        else
          body.unshift(InsnInfo.new([:pop], @root_iseq, -1, -1, true, 1))
        end
        body.unshift(InsnInfo.new([:cast_off_fetch_args, [must, opt, rest, post, block, lvars.slice(0, @arg_size)]], @root_iseq, -1, -1, true, 0))
      end

      decl = []
      lvars.each_with_index do |l, index|
        if index < @arg_size
          bug() if execute?
          op = :cast_off_decl_arg
        else
          op = :cast_off_decl_var
        end
        decl.push(InsnInfo.new([op] + l, @root_iseq, -1, -1, true, 0))
      end
      body = decl.reverse + body

      [lvars, ivars, args, body]
    end

    def format_check(ary)
      magic = ary[0]
      major = ary[1]
      minor = ary[2]
      ftype = ary[3] # format type
      itype = ary[9] # iseq type

      unless magic == 'YARVInstructionSequence/SimpleDataFormat' \
          && major == 1 \
          && minor == 2 \
          && ftype == 1 \
          && (itype == :block || itype == :method)
        raise(CompileError, <<-EOS)
wrong format iseq
magic: #{magic}
major: #{major}
minor: #{minor}
ftype: #{ftype}
itype: #{itype}
        EOS
      end

      itype
    end
  end
end
end

