#if 1
#define __END__ /* void */
#else
ruby_srcdir = ARGV[0].dup;
generated_c_include = ARGV[1].dup;
srcdir = File.dirname(__FILE__)
require("erb");
require('rbconfig');
DATA.rewind();

ERB.new(DATA.read(), 0, "%-").run();
#endif
__END__

% case RUBY_VERSION
% when "1.9.2"
%   ruby_srcdir_prefix = "1.9.2"
% when "1.9.3"
%   ruby_srcdir_prefix = "1.9.3"
% else
%   raise("Unsupported ruby version #{RUBY_VERSION}")
% end
% ruby_srcdir.concat("/#{ruby_srcdir_prefix}")

#include <ruby.h>

#include "<%= ruby_srcdir_prefix %>/vm_core.h"
#include "<%= ruby_srcdir_prefix %>/eval_intern.h"
#include "<%= ruby_srcdir_prefix %>/iseq.h"
#include "<%= ruby_srcdir_prefix %>/gc.h"
#include <ruby/vm.h>
#include <ruby/encoding.h>
#include "<%= ruby_srcdir_prefix %>/vm_insnhelper.h"
#include "<%= ruby_srcdir_prefix %>/vm_insnhelper.c"
#include "<%= ruby_srcdir_prefix %>/vm_exec.h"

#ifdef  USE_INSN_STACK_INCREASE
#undef  USE_INSN_STACK_INCREASE
#endif
#define USE_INSN_STACK_INCREASE 1

#ifdef USE_INSN_RET_NUM
#undef USE_INSN_RET_NUM
#endif
#define USE_INSN_RET_NUM 1

#include "<%= ruby_srcdir_prefix %>/insns_info.inc"
#include "<%= ruby_srcdir_prefix %>/manual_update.h"

VALUE rb_eCastOffCompileError;
VALUE rb_eCastOffExecutionError;
VALUE rb_eCastOffLoadError;
VALUE rb_eCastOffUnsupportedError;
VALUE rb_mCastOff;
VALUE rb_mCastOffCompiler;
VALUE rb_mCastOffCompilerInstruction;
VALUE rb_cCastOffConfiguration;
VALUE rb_cCastOffDependency;
VALUE rb_cCastOffInsnInfo;
VALUE rb_cCastOffSingletonClass;
VALUE rb_cCastOffClassWrapper;
VALUE rb_cCastOffMethodWrapper;
VALUE rb_cCastOffModuleWrapper;

static VALUE
gen_headers(void)
{
% files = %w[
%  debug.h
%  eval_intern.h
%  gc.h
%  id.h
%  iseq.h
%  method.h
%  node.h
%  thread_pthread.h
%  thread_win32.h
%  vm_core.h
%  vm_exec.h
%  vm_insnhelper.h
%  vm_insnhelper.c
%  vm_opts.h
%  insns_info.inc
%  insns.inc
%  manual_update.h
% ].map{|f| [ruby_srcdir, f]} + %w[
%  iter_api.h
%  vm_api.h
%  inline_api.h
%  unbox_api.h
% ].map{|f| [generated_c_include, f]}
% case RUBY_VERSION
% when "1.9.2"
%   # nothing to do
% when "1.9.3"
%   files << [ruby_srcdir, "constant.h"]
%   files << [ruby_srcdir, "atomic.h"]
%   files << [ruby_srcdir, "internal.h"]
% else
%   raise("Unsupported ruby version #{RUBY_VERSION}")
% end
%data = Marshal.dump files.inject({}){|r, i|
%  dir, file = i
%  r[file] = File.read("#{srcdir}/#{dir}/#{file}")
%  r
%}

  rb_encoding* binary = rb_ascii8bit_encoding();
  VALUE str = rb_enc_str_new(NULL, 0, binary);
%   max = 0
%data.each_byte.each_slice(1024).each_with_index {|b, index|
  char data_<%= index %>[] = {
%   size = 0
%   b.each_slice(16).each {|bytes|
%       size += bytes.size
    <%= bytes.map {|i| "%#04x" % i }.join(", ") %>,
%   }
  };
  VALUE str_<%= index %> = rb_enc_str_new(data_<%= index %>, <%= size %>, binary);
%   max += 1
%}
%max.times do |i|
  rb_str_concat(str, str_<%= i %>);
%end
  return rb_marshal_load(str);
}

static VALUE
cast_off_get_child_iseq(VALUE self, VALUE iseqval, VALUE pcval)
{
  long pc;
  rb_iseq_t *parent_iseq, *child_iseq;
  VALUE insn, ret;
  
  if (rb_class_of(iseqval) != rb_cISeq || !FIXNUM_P(pcval)) {
    rb_bug("should not be reached (0)");
  }

  parent_iseq = DATA_PTR(iseqval);
  pc = FIX2LONG(pcval);
  insn = parent_iseq->iseq[pc];

  if (insn != BIN(send)) {
    rb_bug("should not be reached (1), pc = %ld", pc);
  }

  child_iseq = (rb_iseq_t*)parent_iseq->iseq[pc + 3];
  ret = child_iseq->self;

  if (rb_class_of(ret) == rb_cISeq) {
    return ret;
  } else {
    rb_bug("should not be reached (2)");
  }
}

static struct st_table *insn_table;
static VALUE *insn_syms;

static void
init_insn_table(void)
{
  int i;

  if (!insn_syms) {
    insn_table = st_init_numtable();
    insn_syms = malloc(sizeof(VALUE) * VM_INSTRUCTION_SIZE);
    for (i=0; i<VM_INSTRUCTION_SIZE; i++) {
      insn_syms[i] = ID2SYM(rb_intern(insn_name(i)));
      st_insert(insn_table, insn_syms[i], i);
    }
  }
}

static VALUE
cast_off_instruction_popnum(VALUE self, VALUE insns)
{
  VALUE *opes;
  VALUE insnsym;
  VALUE insn;
  int pop;

  if (TYPE(insns) != T_ARRAY) {
    rb_funcall(self, rb_intern("bug"), 1, rb_str_new2("instruction_stack_usage: invalid argument"));
    /* no return */
  }
  insnsym = RARRAY_PTR(insns)[0];
  if (!st_lookup(insn_table, insnsym, &insn)) {
    rb_raise(rb_eArgError, "unsupported instruction");
    /* no return */
  }

  opes = RARRAY_PTR(insns) + 1;
  pop = insn_ret_num(insn) - insn_stack_increase(0, insn, opes);

  return INT2FIX(pop);
}

static VALUE
cast_off_instruction_pushnum(VALUE self, VALUE insns)
{
  VALUE *opes;
  VALUE insnsym;
  VALUE insn;

  if (TYPE(insns) != T_ARRAY) {
    rb_funcall(self, rb_intern("bug"), 1, rb_str_new2("instruction_stack_usage: invalid argument"));
    /* no return */
  }
  insnsym = RARRAY_PTR(insns)[0];
  if (!st_lookup(insn_table, insnsym, &insn)) {
    rb_raise(rb_eArgError, "unsupported instruction");
    /* no return */
  }

  opes = RARRAY_PTR(insns) + 1;
  return INT2FIX(insn_ret_num(insn));
}

static VALUE
cast_off_instruction_stack_usage(VALUE self, VALUE insns)
{
  VALUE *opes;
  VALUE insnsym;
  VALUE insn;

  if (TYPE(insns) != T_ARRAY) {
    rb_funcall(self, rb_intern("bug"), 1, rb_str_new2("instruction_stack_usage: invalid argument"));
    /* no return */
  }
  insnsym = RARRAY_PTR(insns)[0];
  if (!st_lookup(insn_table, insnsym, &insn)) {
    rb_raise(rb_eArgError, "unsupported instruction");
    /* no return */
  }

  opes = RARRAY_PTR(insns) + 1;
  return INT2FIX(insn_stack_increase(0, insn, opes));
}

static VALUE
cast_off_instruction_class_information_in_ic(VALUE self, VALUE iseqval)
{
  VALUE pc = rb_ivar_get(self, rb_intern("@pc"));
  VALUE klass = Qnil;
  VALUE *insn;
  rb_iseq_t *iseq;
  IC ic = NULL;

  if (rb_class_of(pc) != rb_cFixnum || rb_class_of(iseqval) != rb_cISeq) {
    rb_bug("cast_off_instruction_class_information_in_ic: should not be reached (0)");
  }

  if (FIX2INT(pc) < 0) {
    return Qnil;
  }

  iseq = DATA_PTR(iseqval);
  insn = &iseq->iseq[FIX2INT(pc)];

  switch(insn[0]) {
  case(BIN(send)):
    ic = (IC)insn[5];
    break;
  case(BIN(opt_plus)):
  case(BIN(opt_minus)):
  case(BIN(opt_mult)):
  case(BIN(opt_div)):
  case(BIN(opt_mod)):
  case(BIN(opt_eq)):
  case(BIN(opt_lt)):
  case(BIN(opt_le)):
  case(BIN(opt_gt)):
  case(BIN(opt_ge)):
  case(BIN(opt_ltlt)):
  case(BIN(opt_aref)):
  case(BIN(opt_aset)):
  case(BIN(opt_length)):
  case(BIN(opt_size)):
  case(BIN(opt_succ)):
  case(BIN(opt_not)):
    ic = (IC)insn[1];
    break;
  }

  if (!ic) {
    return Qnil;
  }

  klass = ic->ic_class;

  if (!klass || klass == Qnil) {
    return Qnil;
  }

  if (rb_obj_class(klass) != rb_cClass) {
    /* FIXME 普通のオブジェクトが来ることがある。何でだろう。要調査 */
    /* rb_bug("cast_off_instruction_class_information_in_ic: should not be reached (1)"); */
    return Qnil;
  }

  if (FL_TEST(klass, FL_SINGLETON)) {
    VALUE obj = rb_iv_get(klass, "__attached__");
    VALUE __klass = rb_obj_class(obj);
    if (__klass != rb_cClass && __klass != rb_cModule) {
      return Qnil;
    }
    return rb_funcall(rb_cCastOffClassWrapper, rb_intern("new"), 2, obj, Qfalse);
  } else {
    return rb_funcall(rb_cCastOffClassWrapper, rb_intern("new"), 2, klass, Qtrue);
  }
}

static void method_not_found(VALUE km, ID mid, int class_p)
{
  VALUE name;

  if (class_p) {
    name = rb_class_path(km);
  } else {
    name = rb_mod_name(km);
  }
  rb_raise(rb_eCastOffCompileError, "method not found (%s#%s)", RSTRING_PTR(name), rb_id2name(mid));
}

static VALUE cast_off_override_target(VALUE self, VALUE km, VALUE msym)
{
  ID mid;
  rb_method_entry_t *me;
  int class;
  VALUE c = rb_obj_class(km);
  VALUE target;

  if (c == rb_cClass) {
    class = 1;
  } else if (c == rb_cModule) {
    class = 0;
  } else {
    rb_bug("cast_off_override_target: should not be reached(0)");
  }

  if (rb_class_of(msym) != rb_cSymbol) {
    rb_bug("cast_off_override_target: should not be reached(1)");
  }

  mid = SYM2ID(msym);
  me = search_method(km, mid);

  if (!me) {
    method_not_found(km, mid, class);
  }

  target = me->klass;

  if (FL_TEST(target, FL_SINGLETON)) {
    rb_bug("cast_off_override_target: should not be reached(2)");
  }

  if (rb_obj_class(target) != rb_cClass && rb_obj_class(target) != rb_cModule) {
    rb_bug("cast_off_override_target: should not be reached(3)");
  }

  return target;
}

static VALUE cast_off_get_iseq(VALUE self, VALUE obj, VALUE mid, VALUE singleton_p)
{
  rb_iseq_t *iseq;
  rb_method_entry_t *me;
  rb_method_definition_t *def;
  VALUE km;
  int class;
  const char *msg = NULL;
  VALUE name;

  if (singleton_p == Qtrue) {
    class = 1;
    km = rb_class_of(obj);
  } else if (singleton_p == Qfalse) {
    VALUE c = rb_obj_class(obj);
    if (c == rb_cClass) {
      class = 1;
    } else if (c == rb_cModule) {
      class = 0;
    } else {
      rb_bug("cast_off_get_iseq: should not be reached(0)");
    }
    km = obj;
  } else {
    rb_bug("cast_off_get_iseq: should not be reached(1)");
  }

  me = search_method(km, SYM2ID(mid));
  if (!me) {
    if (class) {
      name = rb_class_path(km);
    } else {
      name = rb_mod_name(km);
    }
    rb_raise(rb_eCastOffCompileError, "method not found (%s#%s)", RSTRING_PTR(name), rb_id2name(SYM2ID(mid)));
  }

  def = me->def;
  switch (def->type) {
    case VM_METHOD_TYPE_ISEQ:
      return def->body.iseq->self;
    case VM_METHOD_TYPE_CFUNC:
      msg = "CastOff cannot compile C method";
      break;
    case VM_METHOD_TYPE_ATTRSET:
      msg = "CastOff cannot compile attr_writer";
      break;
    case VM_METHOD_TYPE_IVAR:
      msg = "CastOff cannot compile attr_reader";
      break;
    case VM_METHOD_TYPE_BMETHOD:
      msg = "Currently, CastOff cannot compile method defined by define_method";
      break;
    case VM_METHOD_TYPE_ZSUPER:
      msg = "Unsupported method type zsuper";
      break;
    case VM_METHOD_TYPE_UNDEF:
      msg = "Unsupported method type undef";
      break;
    case VM_METHOD_TYPE_NOTIMPLEMENTED:
      msg = "Unsupported method type notimplemented";
      break;
    case VM_METHOD_TYPE_OPTIMIZED:
      msg = "Unsupported method type optimized";
      break;
    case VM_METHOD_TYPE_MISSING:
      msg = "Unsupported method type missing";
      break;
    default:
      msg = NULL;
  }

  if (!msg) {
    rb_bug("cast_off_get_iseq: should not be reached(2)");
  }

  if (class) {
    name = rb_class_path(km);
  } else {
    name = rb_mod_name(km);
  }
  rb_raise(rb_eCastOffUnsupportedError, "%s (%s#%s)", msg, RSTRING_PTR(name), rb_id2name(SYM2ID(mid)));
}

static VALUE cast_off_get_iseq_from_block(VALUE self, VALUE block)
{
  rb_iseq_t *iseq;
  rb_proc_t *proc;

  if (rb_obj_class(block) != rb_cProc) {
    rb_raise(rb_eCastOffCompileError, "Invalid argument");
  }

  GetProcPtr(block, proc);
  iseq = proc->block.iseq;

  if (!iseq) {
    rb_raise(rb_eCastOffCompileError, "invalid block given");
  }

  return iseq->self;
}

static VALUE cast_off_get_caller(VALUE self)
{
  VALUE thval = rb_thread_current();
  rb_thread_t *th;
  rb_control_frame_t *cfp;

  th = DATA_PTR(thval);
  cfp = th->cfp;
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);

  return cfp->self;
}

RUBY_EXTERN void* dln_load(const char *file);
static VALUE cast_off_load_compiled_file(VALUE self, VALUE file)
{
  if (rb_obj_class(file) != rb_cString) {
    rb_funcall(self, rb_intern("bug"), 1, rb_str_new2("load_compiled_file: invalid argument"));
  }
  dln_load(RSTRING_PTR(file));

  return Qnil;
}

typedef struct class_wrapper_struct {
  VALUE klass;
  VALUE obj;
  int wrap;
} class_wrapper_t;

static void cast_off_class_wrapper_mark(void *ptr)
{
  class_wrapper_t *wrapper = ptr;
  if (!wrapper) return;
  rb_gc_mark(wrapper->klass);
  rb_gc_mark(wrapper->obj);
}

static void cast_off_class_wrapper_free(void *wrapper)
{
  if (wrapper) xfree(wrapper);
}

static size_t cast_off_class_wrapper_memsize(const void *wrapper)
{
    return wrapper ? sizeof(class_wrapper_t) : 0;
}

static const rb_data_type_t cast_off_class_wrapper_data_type = {
  "cast_off_class_wrapper",
  cast_off_class_wrapper_mark,
  cast_off_class_wrapper_free,
  cast_off_class_wrapper_memsize,
};

static VALUE cast_off_allocate_class_wrapper(VALUE klass)
{
  VALUE obj;
  class_wrapper_t *wrapper;

  obj = TypedData_Make_Struct(klass, class_wrapper_t, &cast_off_class_wrapper_data_type, wrapper);
  wrapper->klass = Qnil;
  wrapper->obj = Qnil;

  return obj;
}

static VALUE cast_off_initialize_class_wrapper(VALUE self, VALUE obj, VALUE is_wrap)
{
  int wrap;
  class_wrapper_t *wrapper = DATA_PTR(self);

  switch(is_wrap) {
  case Qtrue:
    wrap = 1;
    break;
  case Qfalse:
    wrap = 0;
    break;
  default:
    rb_bug("ClassWrapper#initialize: should not be reached");
  }

  if (wrap) {
    wrapper->klass = obj;
  } else {
    wrapper->klass = rb_class_of(obj);
    wrapper->obj   = obj;
  }
  wrapper->wrap = wrap;

  return self;
}

static VALUE cast_off_class_wrapper_eq(VALUE self, VALUE obj)
{
  if (rb_class_of(obj) == rb_cCastOffClassWrapper) {
    class_wrapper_t *wrapper0 = DATA_PTR(self);
    class_wrapper_t *wrapper1 = DATA_PTR(obj);
    if (wrapper0->klass == wrapper1->klass) {
      return Qtrue;
    } else {
      return Qfalse;
    }
  } else {
    if (rb_class_of(obj) == rb_cCastOffModuleWrapper) {
      return Qfalse;
    }
    rb_bug("ClassWrapper#eq: should not be reached");
  }
}

static class_wrapper_t *cast_off_class_wrapper_get_wrapper(VALUE self)
{
  class_wrapper_t *wrapper;
  VALUE klass;

  if (rb_class_of(self) != rb_cCastOffClassWrapper) {
    rb_bug("should not be reached");
  }
 
  wrapper = DATA_PTR(self);
  klass = wrapper->klass;
  if (klass == Qnil) {
    rb_bug("should not be reached");
  }

  return wrapper;
}

static VALUE cast_off_class_wrapper_get_class(VALUE self)
{
  class_wrapper_t *wrapper;
  VALUE klass;

  if (rb_class_of(self) != rb_cCastOffClassWrapper) {
    rb_bug("should not be reached");
  }
 
  wrapper = DATA_PTR(self);
  klass = wrapper->klass;
  if (klass == Qnil) {
    rb_bug("should not be reached");
  }

  return klass;
}

static VALUE cast_off_class_wrapper_hash(VALUE self)
{
  VALUE klass = cast_off_class_wrapper_get_class(self);
  return rb_funcall(klass, rb_intern("hash"), 0);
}

static VALUE cast_off_class_wrapper_singleton_p(VALUE self)
{
  class_wrapper_t *wrapper = cast_off_class_wrapper_get_wrapper(self);
  VALUE klass = wrapper->klass;
  VALUE obj = wrapper->obj;

  if (FL_TEST(klass, FL_SINGLETON)) {
    VALUE __klass = rb_obj_class(obj);
    if (__klass == rb_cClass) {
      return Qtrue;
    } else if (__klass == rb_cModule) {
      return Qtrue;
    } else {
      rb_raise(rb_eCastOffCompileError, "CastOff can't handle singleton object without Class and Module");
    }
  } else {
    return Qfalse;
  }
}

static VALUE cast_off_class_wrapper_to_s(VALUE self)
{
  class_wrapper_t *wrapper = cast_off_class_wrapper_get_wrapper(self);
  VALUE klass = wrapper->klass;
  VALUE obj = wrapper->obj;

  if (FL_TEST(klass, FL_SINGLETON)) {
    VALUE __klass = rb_obj_class(obj);
    if (__klass == rb_cClass) {
      return rb_class_path(obj);
    } else if (__klass == rb_cModule) {
      return rb_mod_name(obj);
    } else {
      rb_raise(rb_eCastOffCompileError, "CastOff can't handle singleton object without Class and Module");
    }
  } else {
    return rb_class_path(klass);
  }
}

static VALUE cast_off_class_wrapper_marshal_dump(VALUE self)
{
  class_wrapper_t *wrapper = cast_off_class_wrapper_get_wrapper(self);
  VALUE ary = rb_ary_new();

  if (wrapper->wrap) {
    rb_ary_push(ary, rb_class_path(wrapper->klass));
    rb_ary_push(ary, Qtrue);
  } else {
    rb_ary_push(ary, wrapper->obj);
    rb_ary_push(ary, Qfalse);
  }

  return ary;
}

static VALUE cast_off_class_wrapper_marshal_load(VALUE self, VALUE ary)
{
  VALUE obj = rb_ary_shift(ary);
  VALUE is_wrap = rb_ary_shift(ary);

  if (is_wrap == Qtrue) {
    obj = rb_path_to_class(obj);
  }

  return cast_off_initialize_class_wrapper(self, obj, is_wrap);
}

static VALUE cast_off_class_wrapper_get_cfunc_argc(VALUE self, VALUE mid)
{
  VALUE klass = cast_off_class_wrapper_get_class(self);
  rb_method_entry_t *me = search_method(klass, SYM2ID(mid));
  rb_method_definition_t *def;

  if (!me) {
    return Qfalse;
  }
  def = me->def;
  switch (def->type) {
    case VM_METHOD_TYPE_CFUNC:
      return INT2FIX(def->body.cfunc.argc);
    default:
      /* nothing to do */
      return Qfalse;
  }
}

static VALUE cast_off_class_wrapper_get_method_type(VALUE self, VALUE mid)
{
  VALUE klass = cast_off_class_wrapper_get_class(self);
  rb_method_entry_t *me = search_method(klass, SYM2ID(mid));
  rb_method_definition_t *def;
 
  if (!me) {
    return Qfalse;
  }
  def = me->def;
  switch (def->type) {
    case VM_METHOD_TYPE_CFUNC:
      return ID2SYM(rb_intern("cfunc"));
    case VM_METHOD_TYPE_ATTRSET:
      return ID2SYM(rb_intern("attrset"));
    case VM_METHOD_TYPE_IVAR:
      return ID2SYM(rb_intern("ivar"));
    default:
      /* nothing to do */
      return Qfalse;
  }
}

static VALUE cast_off_class_wrapper_get_attr_id(VALUE self, VALUE mid)
{
  VALUE klass = cast_off_class_wrapper_get_class(self);
  rb_method_entry_t *me = search_method(klass, SYM2ID(mid));
  rb_method_definition_t *def;
 
  if (!me) {
    return Qfalse;
  }
  def = me->def;
  switch (def->type) {
    case VM_METHOD_TYPE_IVAR:
    case VM_METHOD_TYPE_ATTRSET:
      return ID2SYM(me->def->body.attr.id);
    default:
      /* nothing to do */
      return Qfalse;
  }
}

static VALUE cast_off_class_wrapper_instance_method_exist_p(VALUE self, VALUE mid)
{
  VALUE klass = cast_off_class_wrapper_get_class(self);
  rb_method_entry_t *me = search_method(klass, SYM2ID(mid));

  if (me) {
    return Qtrue;
  } else {
    return Qfalse;
  }
}

static VALUE cast_off_class_wrapper_contain_class(VALUE self)
{
  class_wrapper_t *wrapper = cast_off_class_wrapper_get_wrapper(self);
  VALUE klass = wrapper->klass;

  if (FL_TEST(klass, FL_SINGLETON)) {
    rb_bug("should not be reached");
  } else {
    return klass;
  }
}

static VALUE cast_off_class_wrapper_contain_object(VALUE self)
{
  class_wrapper_t *wrapper = cast_off_class_wrapper_get_wrapper(self);
  VALUE klass = wrapper->klass;

  if (FL_TEST(klass, FL_SINGLETON)) {
    return wrapper->obj;
  } else {
    rb_bug("should not be reached");
  }
}

static VALUE cast_off_class_wrapper_each_method_search_target(VALUE self, VALUE midsym)
{
  class_wrapper_t *wrapper = cast_off_class_wrapper_get_wrapper(self);
  VALUE klass = wrapper->klass;
  ID mid = SYM2ID(midsym);

  if (rb_obj_class(midsym) != rb_cSymbol || rb_obj_class(klass) != rb_cClass) {
    rb_bug("cast_off_class_wrapper_each_method_search_target: should not be reached(0)");
  }

  while (1) {
    st_data_t body;

    if (!klass) {
      method_not_found(wrapper->klass, mid, 1);
    }
    if (TYPE(klass) == T_ICLASS) {
      VALUE module = RBASIC(klass)->klass;
      if (TYPE(module) != T_MODULE) {
        rb_bug("cast_off_class_wrapper_each_method_search_target: should not be reached(1)");
      }
      rb_yield(module);
    } else if (TYPE(klass) == T_CLASS) {
      if (FL_TEST(klass, FL_SINGLETON)) {
        VALUE __klass = rb_iv_get(klass, "__attached__");
        if (rb_class_of(__klass) != klass) {
          rb_bug("cast_off_class_wrapper_each_method_search_target: should not be reached(2)");
        }
        rb_yield(rb_funcall(rb_cCastOffClassWrapper, rb_intern("new"), 2, __klass, Qfalse));
      } else {
        rb_yield(klass);
      }
    } else {
      rb_bug("cast_off_class_wrapper_each_method_search_target: should not be reached(3)");
    }
    if(st_lookup(RCLASS_M_TBL(klass), mid, &body)) {
      break;
    }
    klass = RCLASS_SUPER(klass);
  }

  return Qtrue;
}

#define define_type_checker(klass) \
static VALUE cast_off_class_wrapper_##klass##_p(VALUE self) \
{ \
  VALUE klass = cast_off_class_wrapper_get_class(self); \
  if (klass == rb_c##klass) { \
    return Qtrue; \
  } else { \
    return Qfalse; \
  } \
}

define_type_checker(String)
define_type_checker(Array)
define_type_checker(Fixnum)
define_type_checker(Float)

typedef struct module_wrapper_struct {
  VALUE module;
} module_wrapper_t;

static void cast_off_module_wrapper_mark(void *ptr)
{
  module_wrapper_t *wrapper = ptr;
  if (!wrapper) return;
  rb_gc_mark(wrapper->module);
}

static void cast_off_module_wrapper_free(void *wrapper)
{
  if (wrapper) xfree(wrapper);
}

static size_t cast_off_module_wrapper_memsize(const void *wrapper)
{
    return wrapper ? sizeof(module_wrapper_t) : 0;
}

static const rb_data_type_t cast_off_module_wrapper_data_type = {
  "cast_off_module_wrapper",
  cast_off_module_wrapper_mark,
  cast_off_module_wrapper_free,
  cast_off_module_wrapper_memsize,
};

static VALUE cast_off_allocate_module_wrapper(VALUE klass)
{
  VALUE obj;
  module_wrapper_t *wrapper;

  obj = TypedData_Make_Struct(klass, module_wrapper_t, &cast_off_module_wrapper_data_type, wrapper);
  wrapper->module = Qnil;

  return obj;
}

static VALUE cast_off_initialize_module_wrapper(VALUE self, VALUE module)
{
  module_wrapper_t *wrapper = DATA_PTR(self);

  if (rb_obj_class(module) != rb_cModule) {
    rb_bug("should not be reached");
  }

  wrapper->module = module;

  return self;
}

static VALUE cast_off_module_wrapper_get_module(VALUE self)
{
  module_wrapper_t *wrapper;
  VALUE module;

  if (rb_class_of(self) != rb_cCastOffModuleWrapper) {
    rb_bug("cast_off_module_wrapper_get_module: should not be reached(0)");
  }
 
  wrapper = DATA_PTR(self);
  module = wrapper->module;
  if (module == Qnil) {
    rb_bug("cast_off_module_wrapper_get_module: should not be reached(1)");
  }

  return module;
}

static VALUE cast_off_module_wrapper_marshal_dump(VALUE self)
{
  VALUE module = cast_off_module_wrapper_get_module(self);
  VALUE name = rb_mod_name(module);

  /* TODO error handling */
  return name;
}

static VALUE cast_off_module_wrapper_marshal_load(VALUE self, VALUE name)
{
  VALUE module = rb_path_to_class(name);

  if (rb_obj_class(module) != rb_cModule) {
    rb_raise(rb_eCastOffCompileError, "failed to load module");
  }

  return cast_off_initialize_module_wrapper(self, module);
}

static VALUE cast_off_module_wrapper_hash(VALUE self)
{
  VALUE module = cast_off_module_wrapper_get_module(self);
  return rb_funcall(module, rb_intern("hash"), 0);
}

static VALUE cast_off_module_wrapper_eq(VALUE self, VALUE obj)
{
  if (rb_class_of(obj) == rb_cCastOffModuleWrapper) {
    VALUE m0 = cast_off_module_wrapper_get_module(self);
    VALUE m1 = cast_off_module_wrapper_get_module(obj);

    return (m0 == m1) ? Qtrue : Qfalse;
  } else {
    if (rb_class_of(obj) == rb_cCastOffClassWrapper) {
      return Qfalse;
    }
    rb_bug("ModuleWrapper#eq: should not be reached");
  }
}

static VALUE cast_off_module_wrapper_to_s(VALUE self)
{
  VALUE module = cast_off_module_wrapper_get_module(self);
  return rb_mod_name(module);
}

static VALUE cast_off_module_wrapper_contain_module(VALUE self)
{
  return cast_off_module_wrapper_get_module(self);
}

typedef struct method_wrapper_struct {
  VALUE class_or_module;
  VALUE class_or_module_wrapper;
  ID mid;
} method_wrapper_t;

static void cast_off_method_wrapper_mark(void *ptr)
{
  method_wrapper_t *wrapper = ptr;
  if (!wrapper) return;
  rb_gc_mark(wrapper->class_or_module);
  rb_gc_mark(wrapper->class_or_module_wrapper);

  return;
}

static void cast_off_method_wrapper_free(void *wrapper)
{
  if (wrapper) xfree(wrapper);
}

static size_t cast_off_method_wrapper_memsize(const void *wrapper)
{
    return wrapper ? sizeof(method_wrapper_t) : 0;
}

static const rb_data_type_t cast_off_method_wrapper_data_type = {
  "cast_off_method_wrapper",
  cast_off_method_wrapper_mark,
  cast_off_method_wrapper_free,
  cast_off_method_wrapper_memsize,
};

static VALUE cast_off_allocate_method_wrapper(VALUE klass)
{
  VALUE obj;
  method_wrapper_t *wrapper;

  obj = TypedData_Make_Struct(klass, method_wrapper_t, &cast_off_method_wrapper_data_type, wrapper);
  wrapper->class_or_module = Qnil;
  wrapper->mid = 0;

  return obj;
}

static VALUE cast_off_initialize_method_wrapper(VALUE self, VALUE cm, VALUE mid_sym)
{
  method_wrapper_t *wrapper = DATA_PTR(self);
  VALUE klass, class_or_module;
  ID mid;
  rb_method_entry_t *me;

  if (rb_class_of(mid_sym) != rb_cSymbol) {
    rb_bug("cast_off_initialize_method_wrapper: should not be reached(0)");
  }
  klass = rb_class_of(cm);
  if (klass == rb_cCastOffClassWrapper) {
    class_or_module = cast_off_class_wrapper_get_class(cm);
  } else if (klass == rb_cCastOffModuleWrapper) {
    class_or_module = cast_off_module_wrapper_get_module(cm);
  } else {
    rb_bug("cast_off_initialize_method_wrapper: should not be reached(1)");
  }

  mid = SYM2ID(mid_sym);
  me = search_method(class_or_module, mid);
  if (!me) {
    /* FIXME consider method missing */
    VALUE path = rb_class_path(class_or_module);
    rb_raise(rb_eCastOffCompileError, "No such method (%s#%s)", RSTRING_PTR(path), rb_id2name(mid));
  }
  wrapper->class_or_module = class_or_module;
  wrapper->class_or_module_wrapper = cm;
  wrapper->mid = mid;

  return self;
}

static VALUE cast_off_method_wrapper_eq(VALUE self, VALUE obj)
{
  rb_method_entry_t *me0, *me1;
  if (rb_class_of(obj) == rb_cCastOffMethodWrapper) {
    method_wrapper_t *wrapper0 = DATA_PTR(self);
    method_wrapper_t *wrapper1 = DATA_PTR(obj);
    me0 = search_method(wrapper0->class_or_module, wrapper0->mid);
    me1 = search_method(wrapper1->class_or_module, wrapper1->mid);
    if (!me0 || !me1) {
      rb_raise(rb_eCastOffCompileError, "Failed to find method definition");
    }
    if (rb_method_entry_eq(me0, me1)) {
      return Qtrue;
    } else {
      return Qfalse;
    }
  } else {
    rb_bug("should not be reached");
  }
}

static VALUE cast_off_method_wrapper_hash(VALUE self)
{
  /* always collision between MethodWrapper instance */
  return INT2FIX(0);
}

static VALUE cast_off_method_wrapper_marshal_dump(VALUE self)
{
  method_wrapper_t *wrapper = DATA_PTR(self);
  VALUE ary = rb_ary_new();

  rb_ary_push(ary, wrapper->class_or_module_wrapper);
  rb_ary_push(ary, ID2SYM(wrapper->mid));

  return ary;
}

static VALUE cast_off_method_wrapper_marshal_load(VALUE self, VALUE ary)
{
  VALUE cm = rb_ary_shift(ary);
  VALUE mid = rb_ary_shift(ary);
  VALUE k = rb_class_of(cm);

  if (k != rb_cCastOffClassWrapper && k != rb_cCastOffModuleWrapper) {
    VALUE nam = rb_class_path(k);
    rb_bug("cast_off_method_wrapper_marshal_load: should not be reached(0)");
  }

  if(TYPE(mid) != T_SYMBOL) {
    rb_bug("cast_off_method_wrapper_marshal_load: should not be reached(1)");
  }

  return cast_off_initialize_method_wrapper(self, cm, mid);
}

static VALUE cast_off_destroy_last_finish(VALUE self)
{
  VALUE thval = rb_thread_current();
  rb_thread_t *th = DATA_PTR(thval);
  rb_control_frame_t *cfp = th->cfp;
  VALUE *leave_ptr = NULL;
  unsigned long idx;

  while(VM_FRAME_TYPE(cfp) != VM_FRAME_MAGIC_METHOD) {
    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  }
  /* cfp = CastOff::Compiler.vm_exec frame */
  idx = 0;
  while(idx < cfp->iseq->iseq_size) {
    if (cfp->iseq->iseq[idx] == BIN(leave)) {
      leave_ptr = cfp->iseq->iseq_encoded + idx;
      break;
    } else {
      idx++;
    }
  }
  if (!leave_ptr) rb_bug("should not be reached (0)");
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  if (VM_FRAME_TYPE(cfp) != VM_FRAME_MAGIC_FINISH) {
    rb_bug("should not be reached (1)");
  }
  cfp->pc = leave_ptr;
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  /* cfp = deoptimization target frame */
  cfp->sp--;
  return cfp->sp[0];
}

static VALUE cast_off_should_not_be_reached(VALUE self)
{
  rb_bug("should not be reached");
}

static void cast_off_class_definition_end_handler(rb_event_flag_t event, VALUE proc, VALUE self, ID id, VALUE klass)
{
  /* self = target class */
  /* id = klass = 0 */

  static VALUE args = Qnil;

  if (args == Qnil) {
    args = rb_ary_new();
    rb_gc_register_mark_object(args);
  }

  rb_proc_call(proc, args);
}

static VALUE cast_off_hook_class_definition_end(VALUE self, VALUE proc)
{
  static int hook = 0;

  if (proc == Qnil) {
    if (!hook) {
      return Qfalse;
    }
    hook = 0;
    rb_remove_event_hook(&cast_off_class_definition_end_handler);
    return Qtrue;
  }

  if (hook) {
    return Qfalse;
  }

  if (rb_class_of(proc) != rb_cProc) {
    rb_bug("cast_off_hook_class_definition_end: should not be reached(0)");
  }

  rb_add_event_hook(&cast_off_class_definition_end_handler, RUBY_EVENT_END, proc);
  hook = 1;

  return Qtrue;
}

#define IN_HEAP_P(th, ptr)  \
  (!((th)->stack < (ptr) && (ptr) < ((th)->stack + (th)->stack_size)))

static VALUE caller_info(rb_thread_t *th)
{
  rb_control_frame_t *cfp;
  VALUE *lfp = NULL;
  VALUE recv, name;
  VALUE klass;
  ID mid;
  rb_method_entry_t *me;

  cfp = th->cfp; /* this method frame */
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  while (1) {
    if ((VALUE *) cfp >= th->stack + th->stack_size) {
      if (lfp && IN_HEAP_P(th, lfp)) {
        return Qnil;
      }
      rb_bug("caller_info: should not be reached (0) %p", cfp->lfp);
    }
    if (lfp && cfp->dfp != lfp) {
      cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
      continue;
    }
    lfp = NULL;
    switch(VM_FRAME_TYPE(cfp)) {
    case VM_FRAME_MAGIC_METHOD:
      recv = cfp->self;
      name = cfp->iseq->name;
      klass = rb_class_of(recv);
      mid = rb_intern(RSTRING_PTR(name));
      me = search_method(klass, mid);
      if (!me) {
        rb_bug("caller_info: should not be reached (1)");
      }
      klass = me->klass;
      return rb_ary_new3(2, klass, ID2SYM(mid));
    case VM_FRAME_MAGIC_BLOCK:
    case VM_FRAME_MAGIC_PROC:
    case VM_FRAME_MAGIC_LAMBDA:
      lfp = cfp->lfp;
      cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
      continue;
    case VM_FRAME_MAGIC_FINISH:
      cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
      continue;
    case VM_FRAME_MAGIC_CLASS:
    case VM_FRAME_MAGIC_TOP:
    case VM_FRAME_MAGIC_CFUNC:
    case VM_FRAME_MAGIC_IFUNC:
    case VM_FRAME_MAGIC_EVAL:
      return Qnil;
    default:
      rb_bug("caller_info: should not be reached (2)");
    }
  }
}

static void cast_off_method_invocation_handler(rb_event_flag_t event, VALUE proc, VALUE self, ID id, VALUE klass)
{
  const char *srcfile;
  VALUE filename, need_binding;
  VALUE argv[6];
  int line;

  if (klass == 0) {
    rb_frame_method_id_and_class(&id, &klass);
  }
  if (klass) {
    if (TYPE(klass) == T_ICLASS) {
      klass = RBASIC(klass)->klass;
    } else if (FL_TEST(klass, FL_SINGLETON)) {
      klass = rb_iv_get(klass, "__attached__");
    }
  }
  if (!klass) return;

  if (id == ID_ALLOCATOR) {
    return;
  }
  if (!id) return;

  srcfile = rb_sourcefile();
  if (!srcfile) return;
  filename = rb_str_new2(srcfile);

  line = rb_sourceline();
  if (line < 0) return;

  argv[0] = filename;
  argv[1] = INT2FIX(line);
  argv[2] = ID2SYM(id);
  argv[3] = Qnil;
  argv[4] = klass;
  /* argv[5] = caller_info(th); */

  /* rb_proc_call_with_block(proc, 6, argv, Qnil); */
  need_binding = rb_proc_call_with_block(proc, 5, argv, Qnil);
  if (RTEST(need_binding)) {
    argv[3] = (self && srcfile) ? rb_binding_new() : Qnil;
    need_binding = rb_proc_call_with_block(proc, 5, argv, Qnil);
  }
  if (RTEST(need_binding)) {
    rb_bug("cast_off_method_invocation_handler: should not be reached");
  }

  return;
}

static VALUE cast_off_hook_method_invocation(VALUE self, VALUE proc)
{
  static int hook = 0;

  if (proc == Qnil) {
    if (!hook) {
      return Qfalse;
    }
    hook = 0;
    rb_remove_event_hook(&cast_off_method_invocation_handler);
    return Qtrue;
  }

  if (hook) {
    return Qfalse;
  }

  if (rb_class_of(proc) != rb_cProc) {
    rb_bug("cast_off_hook_method_invocation: should not be reached(0)");
  }

  rb_add_event_hook(&cast_off_method_invocation_handler, RUBY_EVENT_CALL, proc);
  hook = 1;

  return Qtrue;
}

static ID id_method_added, id_singleton_method_added, id_initialize_copy, id_clone;
VALUE cast_off_ignore_overridden_p(VALUE dummy, VALUE target, VALUE midsym)
{
  VALUE thval = rb_thread_current();
  rb_thread_t *th = DATA_PTR(thval);
  rb_control_frame_t *cfp;
  ID mid;

  cfp = th->cfp; /* this method frame */
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp); /* method_added or singleton_method_added frame */
  if (!cfp->me) {
    rb_bug("cast_off_ignore_overridden_p: should not be reached(0)");
  }
  mid = cfp->me->called_id;
  if (mid != id_method_added && mid != id_singleton_method_added) {
    rb_bug("cast_off_ignore_overridden_p: should not be reached(1)");
  }
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  if (VM_FRAME_TYPE(cfp) != VM_FRAME_MAGIC_FINISH) {
    return Qfalse;
  }
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  if (VM_FRAME_TYPE(cfp) != VM_FRAME_MAGIC_CFUNC || !cfp->me) {
    return Qfalse;
  }
  mid = cfp->me->called_id;
  if (mid != id_initialize_copy && mid != id_clone) {
    return Qfalse;
  }
  /* ignore when initialize_copy and clone */
  return Qtrue;
}

VALUE cast_off_singleton_method_added_p(VALUE dummy)
{
  VALUE thval = rb_thread_current();
  rb_thread_t *th = DATA_PTR(thval);
  rb_control_frame_t *cfp;
  ID mid;

  cfp = th->cfp; /* this method frame */
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp); /* method_added or singleton_method_added frame */
  if (!cfp->me) {
    rb_bug("cast_off_singleton_method_added_p: should not be reached(0)");
  }
  mid = cfp->me->called_id;
  if (mid == id_method_added) {
    return Qfalse;
  }
  if (mid == id_singleton_method_added) {
    return Qtrue;
  }
  rb_bug("cast_off_singleton_method_added_p: should not be reached(1)");
}

static ID id_include, id_extend;
VALUE cast_off_extend_p(VALUE dummy)
{
  VALUE thval = rb_thread_current();
  rb_thread_t *th = DATA_PTR(thval);
  rb_control_frame_t *cfp;
  ID mid;

  cfp = th->cfp; /* this method frame */
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp); /* method_added or singleton_method_added frame */
  if (!cfp->me) {
    rb_bug("cast_off_extend_p: should not be reached(0)");
  }
  mid = cfp->me->called_id;
  if (mid == id_include) {
    return Qfalse;
  }
  if (mid == id_extend) {
    return Qtrue;
  }
  /* TODO 別名に対応 */
  rb_bug("cast_off_extend_p: should not be reached(1)");
}

/* for deoptimization */
rb_iseq_t *cast_off_Fixnum_times_iseq;
rb_iseq_t *cast_off_Array_each_iseq;
rb_iseq_t *cast_off_Array_map_iseq;
rb_iseq_t *cast_off_Array_map_bang_iseq;

void Init_cast_off(void)
{
  rb_mCastOff = rb_define_module("CastOff");
  rb_mCastOffCompiler = rb_define_module_under(rb_mCastOff, "Compiler");
  rb_mCastOffCompilerInstruction = rb_define_module_under(rb_mCastOffCompiler, "Instruction");
  rb_cCastOffConfiguration = rb_define_class_under(rb_mCastOffCompiler, "Configuration", rb_cObject);
  rb_cCastOffDependency = rb_define_class_under(rb_mCastOffCompiler, "Dependency", rb_cObject);
  rb_cCastOffInsnInfo = rb_define_class_under(rb_mCastOffCompilerInstruction, "InsnInfo", rb_cObject);
  rb_cCastOffClassWrapper = rb_define_class_under(rb_mCastOffCompiler, "ClassWrapper", rb_cObject);
  rb_cCastOffModuleWrapper = rb_define_class_under(rb_mCastOffCompiler, "ModuleWrapper", rb_cObject);
  rb_cCastOffMethodWrapper = rb_define_class_under(rb_mCastOffCompiler, "MethodWrapper", rb_cObject);
  rb_cCastOffSingletonClass = rb_define_class_under(rb_mCastOffCompiler, "SingletonClass", rb_cObject);

  rb_eCastOffCompileError = rb_define_class_under(rb_mCastOff, "CompileError", rb_eStandardError);
  rb_eCastOffExecutionError = rb_define_class_under(rb_mCastOff, "ExecutionError", rb_eStandardError);
  rb_eCastOffLoadError = rb_define_class_under(rb_mCastOff, "LoadError", rb_eStandardError);
  rb_eCastOffUnsupportedError = rb_define_class_under(rb_mCastOff, "UnsupportedError", rb_eStandardError);
  rb_define_method(rb_mCastOffCompiler, "override_target", cast_off_override_target, 2);
  rb_define_method(rb_mCastOffCompiler, "get_iseq", cast_off_get_iseq, 3);
  rb_define_method(rb_mCastOffCompiler, "get_iseq_from_block", cast_off_get_iseq_from_block, 1);
  rb_define_method(rb_mCastOffCompiler, "load_compiled_file", cast_off_load_compiled_file, 1);
  rb_define_method(rb_mCastOffCompiler, "get_caller", cast_off_get_caller, 0);
  rb_define_method(rb_mCastOffCompiler, "hook_method_invocation", cast_off_hook_method_invocation, 1);
  rb_define_method(rb_mCastOffCompiler, "hook_class_definition_end", cast_off_hook_class_definition_end, 1);
  rb_define_method(rb_mCastOffCompilerInstruction, "get_child_iseq", cast_off_get_child_iseq, 2);
  rb_define_const(rb_mCastOffCompilerInstruction, "ROBJECT_EMBED_LEN_MAX", LONG2FIX(ROBJECT_EMBED_LEN_MAX));
  rb_define_const(rb_mCastOffCompilerInstruction, "THROW_TAG_RETURN", LONG2FIX(TAG_RETURN));
  rb_define_const(rb_mCastOffCompilerInstruction, "THROW_TAG_BREAK", LONG2FIX(TAG_BREAK));
  rb_define_const(rb_mCastOffCompilerInstruction, "THROW_TAG_NEXT", LONG2FIX(TAG_NEXT));
  rb_define_const(rb_mCastOffCompilerInstruction, "THROW_TAG_RETRY", LONG2FIX(TAG_RETRY));
  rb_define_const(rb_mCastOffCompilerInstruction, "THROW_TAG_REDO", LONG2FIX(TAG_REDO));
  rb_define_const(rb_mCastOffCompilerInstruction, "THROW_TAG_RAISE", LONG2FIX(TAG_RAISE));
  rb_define_const(rb_mCastOffCompilerInstruction, "THROW_TAG_THROW", LONG2FIX(TAG_THROW));
  rb_define_const(rb_mCastOffCompilerInstruction, "THROW_TAG_FATAL", LONG2FIX(TAG_FATAL));
  rb_define_const(rb_mCastOffCompilerInstruction, "DEFINED_IVAR",   LONG2FIX(DEFINED_IVAR));
  rb_define_const(rb_mCastOffCompilerInstruction, "DEFINED_IVAR2",  LONG2FIX(DEFINED_IVAR2));
  rb_define_const(rb_mCastOffCompilerInstruction, "DEFINED_GVAR",   LONG2FIX(DEFINED_GVAR));
  rb_define_const(rb_mCastOffCompilerInstruction, "DEFINED_CVAR",   LONG2FIX(DEFINED_CVAR));
  rb_define_const(rb_mCastOffCompilerInstruction, "DEFINED_CONST",  LONG2FIX(DEFINED_CONST));
  rb_define_const(rb_mCastOffCompilerInstruction, "DEFINED_METHOD", LONG2FIX(DEFINED_METHOD));
  rb_define_const(rb_mCastOffCompilerInstruction, "DEFINED_YIELD",  LONG2FIX(DEFINED_YIELD));
  rb_define_const(rb_mCastOffCompilerInstruction, "DEFINED_REF",    LONG2FIX(DEFINED_REF));
  rb_define_const(rb_mCastOffCompilerInstruction, "DEFINED_ZSUPER", LONG2FIX(DEFINED_ZSUPER));
  rb_define_const(rb_mCastOffCompilerInstruction, "DEFINED_FUNC",   LONG2FIX(DEFINED_FUNC));

  rb_define_method(rb_cCastOffInsnInfo, "instruction_pushnum", cast_off_instruction_pushnum, 1);
  rb_define_method(rb_cCastOffInsnInfo, "instruction_popnum", cast_off_instruction_popnum, 1);
  rb_define_method(rb_cCastOffInsnInfo, "instruction_stack_usage", cast_off_instruction_stack_usage, 1);
  rb_define_method(rb_cCastOffInsnInfo, "class_information_in_ic", cast_off_instruction_class_information_in_ic, 1);

  rb_define_alloc_func(rb_cCastOffClassWrapper, cast_off_allocate_class_wrapper);
  rb_define_method(rb_cCastOffClassWrapper, "initialize", cast_off_initialize_class_wrapper, 2);
  rb_define_method(rb_cCastOffClassWrapper, "===", cast_off_class_wrapper_eq, 1);
  rb_define_method(rb_cCastOffClassWrapper, "==", cast_off_class_wrapper_eq, 1);
  rb_define_method(rb_cCastOffClassWrapper, "eql?", cast_off_class_wrapper_eq, 1);
  rb_define_method(rb_cCastOffClassWrapper, "hash", cast_off_class_wrapper_hash, 0);
  rb_define_method(rb_cCastOffClassWrapper, "to_s", cast_off_class_wrapper_to_s, 0);
  rb_define_method(rb_cCastOffClassWrapper, "marshal_dump", cast_off_class_wrapper_marshal_dump, 0);
  rb_define_method(rb_cCastOffClassWrapper, "marshal_load", cast_off_class_wrapper_marshal_load, 1);
  rb_define_method(rb_cCastOffClassWrapper, "singleton?", cast_off_class_wrapper_singleton_p, 0);
  rb_define_method(rb_cCastOffClassWrapper, "get_cfunc_argc", cast_off_class_wrapper_get_cfunc_argc, 1);
  rb_define_method(rb_cCastOffClassWrapper, "get_method_type", cast_off_class_wrapper_get_method_type, 1);
  rb_define_method(rb_cCastOffClassWrapper, "get_attr_id", cast_off_class_wrapper_get_attr_id, 1);
  rb_define_method(rb_cCastOffClassWrapper, "instance_method_exist?", cast_off_class_wrapper_instance_method_exist_p, 1);
  rb_define_method(rb_cCastOffClassWrapper, "contain_class", cast_off_class_wrapper_contain_class, 0);
  rb_define_method(rb_cCastOffClassWrapper, "contain_object", cast_off_class_wrapper_contain_object, 0);
  rb_define_method(rb_cCastOffClassWrapper, "each_method_search_target", cast_off_class_wrapper_each_method_search_target, 1);
//#define register_type_checker(klass) rb_define_method(rb_cCastOffClassWrapper, "##klass##?", cast_off_class_wrapper_##klass##_p, 0)
//register_type_checker(String);
//register_type_checker(Array);
//register_type_checker(Fixnum);
  rb_define_method(rb_cCastOffClassWrapper, "String?", cast_off_class_wrapper_String_p, 0);
  rb_define_method(rb_cCastOffClassWrapper, "Array?", cast_off_class_wrapper_Array_p, 0);
  rb_define_method(rb_cCastOffClassWrapper, "Fixnum?", cast_off_class_wrapper_Fixnum_p, 0);
  rb_define_method(rb_cCastOffClassWrapper, "Float?", cast_off_class_wrapper_Float_p, 0);

  rb_define_alloc_func(rb_cCastOffModuleWrapper, cast_off_allocate_module_wrapper);
  rb_define_method(rb_cCastOffModuleWrapper, "initialize", cast_off_initialize_module_wrapper, 1);
  rb_define_method(rb_cCastOffModuleWrapper, "===", cast_off_module_wrapper_eq, 1);
  rb_define_method(rb_cCastOffModuleWrapper, "==", cast_off_module_wrapper_eq, 1);
  rb_define_method(rb_cCastOffModuleWrapper, "eql?", cast_off_module_wrapper_eq, 1);
  rb_define_method(rb_cCastOffModuleWrapper, "hash", cast_off_module_wrapper_hash, 0);
  rb_define_method(rb_cCastOffModuleWrapper, "contain_module", cast_off_module_wrapper_contain_module, 0);
  rb_define_method(rb_cCastOffModuleWrapper, "to_s", cast_off_module_wrapper_to_s, 0);
  rb_define_method(rb_cCastOffModuleWrapper, "marshal_dump", cast_off_module_wrapper_marshal_dump, 0);
  rb_define_method(rb_cCastOffModuleWrapper, "marshal_load", cast_off_module_wrapper_marshal_load, 1);

  rb_define_alloc_func(rb_cCastOffMethodWrapper, cast_off_allocate_method_wrapper);
  rb_define_method(rb_cCastOffMethodWrapper, "initialize", cast_off_initialize_method_wrapper, 2);
  rb_define_method(rb_cCastOffMethodWrapper, "===", cast_off_method_wrapper_eq, 1);
  rb_define_method(rb_cCastOffMethodWrapper, "==", cast_off_method_wrapper_eq, 1);
  rb_define_method(rb_cCastOffMethodWrapper, "eql?", cast_off_method_wrapper_eq, 1);
  rb_define_method(rb_cCastOffMethodWrapper, "hash", cast_off_method_wrapper_hash, 0);
  rb_define_method(rb_cCastOffMethodWrapper, "marshal_dump", cast_off_method_wrapper_marshal_dump, 0);
  rb_define_method(rb_cCastOffMethodWrapper, "marshal_load", cast_off_method_wrapper_marshal_load, 1);

  rb_define_const(rb_mCastOffCompiler, "Headers", gen_headers());
  rb_define_const(rb_mCastOffCompiler, "DEOPTIMIZATION_ISEQ_TABLE", rb_hash_new());

  id_method_added = rb_intern("method_added");
  id_singleton_method_added = rb_intern("singleton_method_added");
  id_include = rb_intern("include");
  id_extend = rb_intern("extend");
  id_initialize_copy = rb_intern("initialize_copy");
  id_clone = rb_intern("clone");
  rb_define_singleton_method(rb_cCastOffDependency, "ignore_overridden?", cast_off_ignore_overridden_p, 2);
  rb_define_singleton_method(rb_cCastOffDependency, "singleton_method_added?", cast_off_singleton_method_added_p, 0);
  rb_define_singleton_method(rb_cCastOffDependency, "extend?", cast_off_extend_p, 0);

  rb_define_singleton_method(rb_mCastOffCompiler, "destroy_last_finish", cast_off_destroy_last_finish, 0);
  rb_funcall(rb_mCastOffCompiler, rb_intern("module_eval"), 1, rb_str_new2("def self.vm_exec(); destroy_last_finish() end"));

  init_insn_table();
}

