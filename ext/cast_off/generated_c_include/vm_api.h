static inline int empty_method_table_p(VALUE klass)
{
  st_table *mtbl = RCLASS_M_TBL(klass);

  if (!mtbl) rb_bug("empty_method_table_p: shoult not be reached");
  return mtbl->num_entries == 0;
}

static VALUE handle_blockarg(VALUE blockarg)
{
  VALUE thval = rb_thread_current();
  rb_thread_t *th = DATA_PTR(thval);
  rb_control_frame_t *cfp = th->cfp;
  rb_proc_t *po;
  rb_block_t *block;
  VALUE proc;

  proc = blockarg;
  if (proc != Qnil) {
    if (!rb_obj_is_proc(proc)) {
      VALUE b = rb_check_convert_type(proc, T_DATA, "Proc", "to_proc");
      if (NIL_P(b) || !rb_obj_is_proc(b)) {
        rb_raise(rb_eTypeError, "wrong argument type %s (expected Proc)", rb_obj_classname(proc));
      }
      proc = b;
    }
    po = DATA_PTR(proc);
    block = &po->block;
    th->passed_block = block;
  }
  return proc;
}
NOINLINE(static VALUE handle_blockarg(VALUE blockarg));

#define IN_HEAP_P(th, ptr)  \
  (!((th)->stack < (ptr) && (ptr) < ((th)->stack + (th)->stack_size)))

static VALUE cfp_env(rb_thread_t *th, rb_control_frame_t *cfp)
{
  VALUE *dfp = cfp->dfp;
  VALUE *envptr = GC_GUARDED_PTR_REF(dfp[0]);
  VALUE envval;

  if (!envptr) {
    rb_bug("cfp_env: should not be reached(0)");
  }

  if (IN_HEAP_P(th, envptr)) {
    envval = envptr[1];
    if (rb_class_of(envval) != rb_cEnv) {
      rb_bug("cfp_env: should not be reached(1)");
    }
  } else {
    envval = Qnil;
  }

  return envval;
}

/* ensure に対応すると大幅に書き直す必要がありそう */
static VALUE return_block(rb_num_t raw_state, VALUE throwobj, int lambda_p)
{
  int state = (int)(raw_state & 0xff);
  int flag = (int)(raw_state & 0x8000);
  /*rb_num_t level = raw_state >> 16;*/

  VALUE thval = rb_thread_current();
  rb_thread_t *th = DATA_PTR(thval);
  rb_control_frame_t *cfp = th->cfp;
  VALUE *dfp = cfp->dfp;
  VALUE *lfp = cfp->lfp;

  rb_thread_check_ints();

  if (state != TAG_RETURN || flag != 0) {
    rb_bug("return_block: should not be reached(0)");
  }

  if (VM_FRAME_TYPE(cfp) != VM_FRAME_MAGIC_IFUNC) {
    rb_bug("return_block: should not be reached(1)");
  }

  if (dfp == lfp) {
    rb_bug("return_block: should not be reached(2)");
  }

  if (lambda_p) {
    return throwobj;
  }

  /* check orphan and get dfp */
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  while ((VALUE *) cfp < th->stack + th->stack_size) {
    if (cfp->lfp == lfp) {
      VALUE env;

      switch(VM_FRAME_TYPE(cfp)) {
        case VM_FRAME_MAGIC_IFUNC:
          /* check lambda */
          env = cfp_env(th, cfp);
          if (env != Qnil) {
            rb_raise(rb_eCastOffExecutionError, "Currently, CastOff cannot handle this return statement");
          }
          break;
        case VM_FRAME_MAGIC_CFUNC:
          /* nothing to do */
          break;
        default:
          rb_bug("return_block: should not be reached(3)");
      }
    }

    if (cfp->dfp == lfp) {
      int ok;

      switch(VM_FRAME_TYPE(cfp)) {
      case VM_FRAME_MAGIC_METHOD:
        /* deoptimized frame */
        /* nothing to do */
      case VM_FRAME_MAGIC_CFUNC:
        ok = 1;
        break;
      default:
        ok = 0;
      }

      if (ok) {
        dfp = lfp;
        goto valid_return;
      }
    }
    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  }

  rb_vm_localjump_error("unexpected return", throwobj, TAG_RETURN);

valid_return:

  th->errinfo = (VALUE)NEW_THROW_OBJECT(throwobj, (VALUE) dfp, state);
  th->state = 0;

  TH_JUMP_TAG(th, TAG_RETURN);
}
NOINLINE(static VALUE return_block(rb_num_t raw_state, VALUE throwobj, int lambda_p));

static inline VALUE catch_return(rb_thread_t *th)
{
  VALUE err = th->errinfo;
  VALUE *escape_dfp = GET_THROWOBJ_CATCH_POINT(err);

  if (th->cfp->dfp == escape_dfp) {
    th->errinfo = Qnil;
    return GET_THROWOBJ_VAL(err);
  }
  return Qundef;
}

static void return_from_execute(rb_num_t raw_state, VALUE val)
{
  VALUE thval = rb_thread_current();
  rb_num_t state;
  rb_thread_t *th;
  rb_control_frame_t *cfp;

  th = DATA_PTR(thval);
  cfp = th->cfp; /* current cfp */
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp); /* CastOff.execute cfp */
  cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  rb_thread_check_ints();
  th->errinfo = vm_throw(th, cfp, raw_state, val);
  state = th->state;
  th->state = 0;
  TH_JUMP_TAG(th, state);
}
NOINLINE(static void return_from_execute(rb_num_t raw_state, VALUE val));

static rb_iseq_t *iseq_from_cfp(rb_control_frame_t *cfp) 
{
  rb_iseq_t *iseq;
  if (SPECIAL_CONST_P(cfp->iseq)) {
    /* when finish frame, cfp->self = 4 (Qnil), cfp->flag = 0x51 (VM_FRAME_MAGIC_FINISH) */
    rb_bug("iseq_from_cfp: should not be reached(0): self = %lx, flag = %lx", cfp-> self, cfp->flag);
  } else if (BUILTIN_TYPE(cfp->iseq) != T_NODE) {
    iseq = cfp->iseq;
  } else {
    /* NODE *ifunc = (NODE *)cfp->iseq; */
    /* VALUE iseqval = ifunc->nd_tval; */
    /* iseq = DATA_PTR(iseqval); */
    rb_bug("iseq_from_cfp: should not be reached(1)");
  }
  if (rb_class_of(iseq->self) != rb_cISeq) {
    rb_bug("iseq_from_cfp: should not be reached(2)");
  }
  return iseq;
}

static void break_block(rb_num_t raw_state, VALUE epc, VALUE throwobj)
{
  int state = (int)(raw_state & 0xff);
  int flag = (int)(raw_state & 0x8000);
  /*rb_num_t level = raw_state >> 16;*/
  int is_orphan = 1;

  VALUE thval = rb_thread_current();
  rb_thread_t *th = DATA_PTR(thval);
  rb_control_frame_t *cfp = th->cfp;
  VALUE *dfp = cfp->dfp;

  rb_thread_check_ints();

  if (state != TAG_BREAK || flag != 0) {
    /* 
     * flag != 0 のときは dfp の値が変わるので、vm_exec を見て
     * state == TAG_BREAK && ((VALUE)escape_dfp & ~0x03) == 0 のくだりを実装する必要がある。
     */
    rb_bug("break_block: should not be reached(0)");
  }
  if (VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_LAMBDA) {
    rb_raise(rb_eCastOffExecutionError, "Currently, CastOff doesn't support break statement in lambda");
  }

  dfp = GC_GUARDED_PTR_REF((VALUE *) *dfp);
  while ((VALUE *)cfp < th->stack + th->stack_size) {
    if (cfp->dfp == dfp) {
      rb_iseq_t *iseq = iseq_from_cfp(cfp);
      int i;

      for (i=0; i<iseq->catch_table_size; i++) {
        struct iseq_catch_table_entry *entry = &iseq->catch_table[i];
        if (entry->type == CATCH_TYPE_BREAK && entry->start < epc && entry->end >= epc) {
          if (entry->cont == epc) {
            goto found;
          } else {
            break;
          }
        }
      }
      break;

found:
      is_orphan = 0;
      break;
    }
    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  }

  if (is_orphan) {
    rb_vm_localjump_error("break from proc-closure", throwobj, TAG_BREAK);
  }

  switch(VM_FRAME_TYPE(cfp)) {
  case VM_FRAME_MAGIC_CFUNC:
  case VM_FRAME_MAGIC_IFUNC:
    cfp->pc = cfp->iseq->iseq_encoded + epc;
    break;
  case VM_FRAME_MAGIC_BLOCK:
  case VM_FRAME_MAGIC_LAMBDA:
  case VM_FRAME_MAGIC_METHOD:
    /* deoptimized frame */
    /* nothing to do */
    break;
  default:
    rb_bug("break_block: should not be reached(1)");
  }
  th->errinfo = (VALUE)NEW_THROW_OBJECT(throwobj, (VALUE) dfp, state);
  th->state = 0;

  TH_JUMP_TAG(th, TAG_BREAK);
}
NOINLINE(static void break_block(rb_num_t raw_state, VALUE epc, VALUE throwobj));

static inline VALUE catch_break(rb_thread_t *th)
{
  VALUE err = th->errinfo;
  VALUE *escape_dfp = GET_THROWOBJ_CATCH_POINT(err);

  if (th->cfp->dfp == escape_dfp) {
    th->errinfo = Qnil;
    return GET_THROWOBJ_VAL(err);
  }
  return Qundef;
}

static VALUE
rb_vm_set_finish_env(rb_thread_t * th, VALUE *sp)
{
  rb_control_frame_t *cfp = th->cfp;
  VALUE *finish_insn_seq;

  while(VM_FRAME_TYPE(cfp) != VM_FRAME_MAGIC_FINISH) {
    /* FIXME */
    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  }
  finish_insn_seq = cfp->pc;

  vm_push_frame(th, 0, VM_FRAME_MAGIC_FINISH, Qnil, th->cfp->lfp[0], 0, sp, 0, 1);
  th->cfp->pc = (VALUE *)&finish_insn_seq[0];
  return Qtrue;
}

static void construct_frame_inline(VALUE self, rb_thread_t *th, rb_iseq_t *iseq, long pc, int local_c, VALUE *local_v, int stack_c, VALUE *stack_v, int method_p, VALUE *lfp, VALUE *dfp)
{
  rb_control_frame_t *cfp;
  VALUE *sp;
  int i;

  cfp = th->cfp;
  sp = cfp->sp;
  CHECK_STACK_OVERFLOW(cfp, local_c);
  /* restore local variables */
  for(i = 0; i < local_c; i++, sp++) {
    *sp = local_v[i];
  }
  if (local_c + 1 != iseq->local_size) {
    rb_bug("should not be reached (3)");
  }
  vm_push_frame(th, iseq, method_p ? VM_FRAME_MAGIC_METHOD : VM_FRAME_MAGIC_BLOCK, self, (VALUE)dfp, iseq->iseq_encoded + pc, sp, lfp, 1);
  sp = th->cfp->sp;
  for(i = 0; i < stack_c; i++, sp++) {
    *sp = stack_v[i];
  }
  th->cfp->sp = sp;
}

static VALUE cast_off_deoptimize_inline(VALUE self, rb_iseq_t *iseq, rb_iseq_t *biseq, long pc, int local_c, VALUE *local_v, int stack_c, VALUE *stack_v, int top_p, int bottom_p, int method_p, VALUE *lfp, VALUE *dfp)
{
  VALUE val = Qundef;
  VALUE thval = rb_thread_current();
  rb_thread_t *th = DATA_PTR(thval);
  rb_control_frame_t *rcfp;
  VALUE *rsp;

  if (bottom_p) {
    if (top_p) {
      rcfp = th->cfp;
      rsp = rcfp->sp;
    }
    rb_vm_set_finish_env(th, th->cfp->sp);
  }
  construct_frame_inline(self, th, iseq, pc, local_c, local_v, stack_c, stack_v, method_p, lfp, dfp);
  if (top_p) {
    val = rb_funcall(rb_mCastOffCompiler, rb_intern("vm_exec"), 0);
    if (bottom_p) {
      if (th->cfp != rcfp || th->cfp->sp != rsp) {
        rb_bug("cast_off_deoptimize_inline: should not be reached(0)");
      }
    }
    return val;
  } else {
    rb_block_t *blockptr = (rb_block_t *)(&(th->cfp->self));
    blockptr->iseq = biseq;
    return (VALUE)blockptr;
  }
}
NOINLINE(static VALUE cast_off_deoptimize_inline(VALUE self, rb_iseq_t *iseq, rb_iseq_t *biseq, long pc, int local_c, VALUE *local_v, int stack_c, VALUE *stack_v, int top_p, int bottom_p, int method_p, VALUE *lfp, VALUE *dfp));

static void construct_frame_noinline(rb_thread_t *th, rb_iseq_t *iseq, long pc, int stack_c, VALUE *stack_v, int method_p, int lambda_p, rb_control_frame_t *buf)
{
  rb_control_frame_t *cfp = th->cfp;
  VALUE *sp;
  VALUE frame = method_p ? VM_FRAME_MAGIC_METHOD : (lambda_p ? VM_FRAME_MAGIC_LAMBDA : VM_FRAME_MAGIC_BLOCK);
  int i;

  /* insert finish frame */
  MEMCPY(buf, cfp, rb_control_frame_t, 1); /* backup current frame */
  vm_pop_frame(th); /* pop current frame */
  rb_vm_set_finish_env(th, buf->sp); /* push finish frame to use vm_exec */
  sp = th->cfp->sp;
  cfp = th->cfp = RUBY_VM_NEXT_CONTROL_FRAME(th->cfp);
  MEMCPY(cfp, buf, rb_control_frame_t, 1); /* restore current frame */
  cfp->flag = cfp->flag - VM_FRAME_TYPE(cfp) + frame; /* modify frame type */
  cfp->pc = iseq->iseq_encoded + pc;
  cfp->iseq = iseq;
  cfp->bp = sp;
  for(i = 0; i < stack_c; i++, sp++) {
    *sp = stack_v[i];
  }
  cfp->sp = sp;
}

static void instrument_parent_frame(rb_thread_t *th, int parent_pc)
{
  rb_control_frame_t *cfp = th->cfp;
  VALUE *dfp = GC_GUARDED_PTR_REF(cfp->dfp[0]);

  if (parent_pc < 0) {
    if (th->cfp->lfp != th->cfp->dfp) {
      rb_bug("instrument_parent_frame: should not be reached(0)");
    }
    return;
  }
  if (th->cfp->lfp == th->cfp->dfp) {
    rb_bug("instrument_parent_frame: should not be reached(1)");
  }

  while ((VALUE *) cfp < th->stack + th->stack_size) {
    if (cfp->dfp == dfp) {
      rb_iseq_t *piseq = cfp->iseq;
      if (rb_class_of(piseq->self) != rb_cISeq) {
        rb_bug("instrument_parent_frame: should not be reached(2)");
      }
      cfp->pc = piseq->iseq_encoded + parent_pc;
      return;
    }
    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  }
}

static VALUE cast_off_deoptimize_noinline(VALUE self, rb_iseq_t *iseq, unsigned long pc, int stack_c, VALUE *stack_v, int method_p, int lambda_p, int parent_pc)
{
  VALUE val;
  VALUE thval = rb_thread_current();
  rb_thread_t *th = DATA_PTR(thval);
  rb_control_frame_t *rcfp = th->cfp;
  VALUE *rsp = rcfp->sp;
  rb_control_frame_t buf;

  construct_frame_noinline(th, iseq, pc, stack_c, stack_v, method_p, lambda_p, &buf);
  instrument_parent_frame(th, parent_pc);
  val = rb_funcall(rb_mCastOffCompiler, rb_intern("vm_exec"), 0);
  th->cfp = RUBY_VM_NEXT_CONTROL_FRAME(th->cfp);
  MEMCPY(th->cfp, &buf, rb_control_frame_t, 1); /* restore frame */
  if (th->cfp != rcfp || th->cfp->sp != rsp) {
    rb_bug("cast_off_deoptimize_ifunc: should not be reached (2)");
  }

  return val;
}
NOINLINE(static VALUE cast_off_deoptimize_noinline(VALUE self, rb_iseq_t *iseq, unsigned long pc, int stack_c, VALUE *stack_v, int method_p, int lambda_p, int parent_pc));

static VALUE *cast_off_get_iv_table_ptr(VALUE self)
{
  VALUE *iv_table_ptr = ROBJECT(self)->as.heap.ivptr;

  if (!iv_table_ptr) {
    RBASIC(self)->flags |= ROBJECT_EMBED;
  }
  if (RBASIC(self)->flags & ROBJECT_EMBED) {
    int i;
    int len = ROBJECT_EMBED_LEN_MAX;
    VALUE parent = rb_obj_class(self);
    VALUE *ptr = ROBJECT_IVPTR(self);
    struct st_table *iv_index_tbl = RCLASS_IV_INDEX_TBL(parent);

    if (!iv_index_tbl) rb_bug("should not be reached");
    if (iv_index_tbl->num_entries <= len) rb_bug("should not be reached");
    iv_table_ptr = ALLOC_N(VALUE, iv_index_tbl->num_entries);
    MEMCPY(iv_table_ptr, ptr, VALUE, len);
    for (i = len; i < iv_index_tbl->num_entries; i++) {
      iv_table_ptr[i] = Qnil;
    }
    RBASIC(self)->flags &= ~ROBJECT_EMBED;
    ROBJECT(self)->as.heap.ivptr = iv_table_ptr;
  }

  return iv_table_ptr;
}
NOINLINE(static VALUE *cast_off_get_iv_table_ptr(VALUE self));

static long cast_off_get_iv_index(struct st_table  *iv_index_tbl, ID iv_id)
{
  st_data_t index;

  if (!st_lookup(iv_index_tbl, (st_data_t)iv_id, &index)) {
    index = iv_index_tbl->num_entries;
    st_add_direct(iv_index_tbl, (st_data_t)iv_id, index);
  }

  return (long)index;
}
NOINLINE(static long cast_off_get_iv_index(struct st_table  *iv_index_tbl, ID iv_id));

static struct st_table *cast_off_get_iv_index_tbl(VALUE self)
{
  struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL(self);

  if (!iv_index_tbl) {
    VALUE parent = rb_obj_class(self);
    iv_index_tbl = RCLASS_IV_INDEX_TBL(parent);
    if (!iv_index_tbl) iv_index_tbl = RCLASS_IV_INDEX_TBL(parent) = st_init_numtable();
  }

  return iv_index_tbl;
}
NOINLINE(static struct st_table *cast_off_get_iv_index_tbl(VALUE self));

static int cast_off_singleton_p(VALUE klass)
{
  VALUE k0 = rb_class_of(klass);

  if (FL_TEST(k0, FL_SINGLETON)) {
    VALUE k1 = rb_obj_class(klass);
    if (k1 == rb_cClass) {
      return 1;
    } else if (k1 == rb_cModule) {
      return 1;
    } else {
      rb_raise(rb_eCastOffExecutionError, "CastOff can't handle singleton object without Class and Module");
    }
  } else {
    return 0;
  }
}
NOINLINE(static int cast_off_singleton_p(VALUE klass));

static void should_be_singleton(VALUE klass)
{
  if (cast_off_singleton_p(klass)) {
    return;
  } else {
    rb_raise(rb_eCastOffExecutionError, "unexpected method(1)");
  }
}
NOINLINE(static void should_be_singleton(VALUE klass));

static void should_be_cfunc(rb_method_entry_t *me)
{
  if (!(me && me->def->type == VM_METHOD_TYPE_CFUNC)) {
    rb_raise(rb_eCastOffExecutionError, "unexpected method(0)");
  }

  return;
}
NOINLINE(static void should_be_cfunc(rb_method_entry_t *me));

static void* c_function_pointer(rb_method_entry_t *me)
{
  if (me && me->def->type == VM_METHOD_TYPE_CFUNC) {
    return me->def->body.cfunc.func;
  } else {
    return NULL;
  }
}
NOINLINE(static void* c_function_pointer(rb_method_entry_t *me));

static int c_function_argc(rb_method_entry_t *me)
{
  if (!(me && me->def->type == VM_METHOD_TYPE_CFUNC)) {
    rb_bug("c_function_argc: should not be reached");
  }

  return me->def->body.cfunc.argc;
}
NOINLINE(static int c_function_argc(rb_method_entry_t *me));

typedef struct method_wrapper_struct {
  VALUE class_or_module;
  VALUE class_or_module_wrapper;
  ID mid;
} method_wrapper_t; /* FIXME */

static inline int method_wrapper_fptr_eq(VALUE self, VALUE (*fptr)(ANYARGS))
{
  if (rb_class_of(self) == rb_cCastOffMethodWrapper) {
    method_wrapper_t *wrapper = DATA_PTR(self);
    rb_method_entry_t *me = search_method(wrapper->class_or_module, wrapper->mid);

    if (me && me->def->type == VM_METHOD_TYPE_CFUNC) {
      return me->def->body.cfunc.func == fptr;
    } else {
      return 0;
    }
  } else {
    rb_bug("method_wrapper_eq: should not be reached(0)");
  }
}

static int should_be_call_directly_p(VALUE (*fptr)(ANYARGS))
{
  static ID id_direct_call_targets;
  VALUE direct_call_targets;
  VALUE *mptrs;
  int i, len;

  if (!id_direct_call_targets) id_direct_call_targets = rb_intern("DIRECT_CALL_TARGETS");
  direct_call_targets = rb_const_get(rb_cCastOffConfiguration, id_direct_call_targets);
  mptrs = RARRAY_PTR(direct_call_targets);
  len = RARRAY_LEN(direct_call_targets);

  for (i = 0; i < len; i++) {
    VALUE m = mptrs[i];
    if (method_wrapper_fptr_eq(m, fptr)) {
      return 1;
    }
  }

  return 0;
}
NOINLINE(static int should_be_call_directly_p(VALUE (*fptr)(ANYARGS)));

#define cast_off_const_defined(klass, id) cast_off_get_ev_const(self, cast_off_orig_iseq->cref_stack, (klass), (id), 1)
#define cast_off_get_constant(klass, id)  cast_off_get_ev_const(self, cast_off_orig_iseq->cref_stack, (klass), (id), 0)
#define cast_off_get_cvar_base()          vm_get_cvar_base(cast_off_orig_iseq->cref_stack)

#if defined(RUBY_1_9_3)
static VALUE
cast_off_get_ev_const(VALUE self, NODE *root_cref, VALUE orig_klass, ID id, int is_defined)
{
  VALUE val;

  if (orig_klass == Qnil) {
    /* in current lexical scope */
    const NODE *cref;
    VALUE klass = orig_klass;

    while (root_cref && root_cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL) {
      root_cref = root_cref->nd_next;
    }
    cref = root_cref;
    while (cref && cref->nd_next) {
      if (cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL) {
        klass = Qnil;
      } else {
        klass = cref->nd_clss;
      }
      cref = cref->nd_next;

      if (!NIL_P(klass)) {
        VALUE am = 0;
        st_data_t data;
search_continue:
        if (RCLASS_CONST_TBL(klass) &&
          st_lookup(RCLASS_CONST_TBL(klass), id, &data)) {
          val = ((rb_const_entry_t*)data)->value;
          if (val == Qundef) {
            if (am == klass) break;
            am = klass;
            if (is_defined) return 1;
            rb_autoload_load(klass, id);
            goto search_continue;
          } else {
            if (is_defined) {
              return 1;
            } else {
              return val;
            }
          }
        }
      }
    }

    /* search self */
    if (root_cref && !NIL_P(root_cref->nd_clss)) {
        klass = root_cref->nd_clss;
    } else {
        klass = CLASS_OF(self);
    }
    if (is_defined) {
      return rb_const_defined(klass, id);
    } else {
      return rb_const_get(klass, id);
    }
  } else {
    vm_check_if_namespace(orig_klass);
    if (is_defined) {
      return rb_const_defined(orig_klass, id); /* FIXME */
      /* return rb_public_const_defined_from(orig_klass, id); */
    } else {
      return rb_const_get(orig_klass, id); /* FIXME */
      /* return rb_public_const_get_from(orig_klass, id); */
    }
  }
}
NOINLINE(static VALUE cast_off_get_ev_const(VALUE self, NODE *root_cref, VALUE orig_klass, ID id, int is_defined));
#elif defined(RUBY_1_9_2)
static VALUE
cast_off_get_ev_const(VALUE self, NODE *cref, VALUE orig_klass, ID id, int is_defined)
{
  VALUE val;

  if (orig_klass == Qnil) {
    /* in current lexical scope */
    const NODE *root_cref = NULL;
    VALUE klass = orig_klass;

    while (cref && cref->nd_next) {
      if (!(cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL)) {
        klass = cref->nd_clss;
        if (root_cref == NULL)
          root_cref = cref;
      }
      cref = cref->nd_next;

      if (!NIL_P(klass)) {
        VALUE am = 0;
search_continue:
        if (RCLASS_IV_TBL(klass) &&
            st_lookup(RCLASS_IV_TBL(klass), id, &val)) {
          if (val == Qundef) {
            if (am == klass) break;
            am = klass;
            rb_autoload_load(klass, id);
            goto search_continue;
          } else {
            if (is_defined) {
              return 1;
            } else {
              return val;
            }
          }
        }
      }
    }

    /* search self */
    if (root_cref && !NIL_P(root_cref->nd_clss)) {
      klass = root_cref->nd_clss;
    } else {
      VALUE thval = rb_thread_current();
      rb_thread_t *th = DATA_PTR(thval);
      klass = CLASS_OF(th->cfp->self);
    }
    if (is_defined) {
      return rb_const_defined(klass, id);
    } else {
      return rb_const_get(klass, id);
    }
  }
  else {
    vm_check_if_namespace(orig_klass);
    if (is_defined) {
      return rb_const_defined(orig_klass, id); /* FIXME */
      /* return rb_public_const_defined_from(orig_klass, id); */
    } else {
      return rb_const_get(orig_klass, id); /* FIXME */
      /* return rb_const_get_from(orig_klass, id); */
    }
  }
}
NOINLINE(static VALUE cast_off_get_ev_const(VALUE self, NODE *cref, VALUE orig_klass, ID id, int is_defined));
#endif

#if 0
/* should be mark cache->obj */
struct cast_off_ivar_cache_struct {
  VALUE obj;   /* FIXME should be gc mark ? */ 
  VALUE klass; /* FIXME should be gc mark ? */
  long  index;
  VALUE *ptr;
} cast_off_ivar_cache_t;

static inline VALUE
cast_off_getivar(VALUE self, ID id, cast_off_ivar_cache_t *cache)
{
  if (TYPE(self) == T_OBJECT) {
    VALUE val, klass;

    if (cache->obj == self) {
      return *ptr;
    }

    val = Qnil;
    klass = RBASIC(self)->klass;

    if (cache->klass == klass) {
      long index = cache->index;
      long len = ROBJECT_NUMIV(self);
      VALUE *ptr = ROBJECT_IVPTR(self);

      if (index < len) {
        val = ptr[index];
        cache->obj = self;
        cache->ptr = ptr + index;
      } else {
        cache->obj = Qundef;
      }
    } else {
      st_data_t index;
      long len = ROBJECT_NUMIV(self);
      VALUE *ptr = ROBJECT_IVPTR(self);
      struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL(self);

      if (iv_index_tbl && st_lookup(iv_index_tbl, id, &index)) {
        if ((long)index < len) {
          val = ptr[index];
          cache->obj = self;
          cache->ptr = ptr + index;
        } else {
          cache->obj = Qundef;
        }
        cache->klass = klass;
        cache->index = index;
      } else {
        cache->obj = Qundef;
        cache->klass = Qundef;
      }
    }
    return val;
  } else {
    return rb_ivar_get(self, id);
  }
}

static inline void
cast_off_setivar(VALUE self, ID id, VALUE val, cast_off_ivar_cache_t *cache)
{
  if (!OBJ_UNTRUSTED(self) && rb_safe_level() >= 4) {
    rb_raise(rb_eSecurityError, "Insecure: can't modify instance variable");
  }

  rb_check_frozen(self);

  if (TYPE(self) == T_OBJECT) {
    VALUE klass = RBASIC(self)->klass;
    st_data_t index;

    if (cache->obj == self) {
      *ptr = val;
      return;
    }

    if (cache->klass == klass) {
      long index = cache->index;
      long len = ROBJECT_NUMIV(self);
      VALUE *ptr = ROBJECT_IVPTR(self);

      if (index < len) {
        ptr[index] = val;
        cache->obj = self;
        cache->ptr = ptr + index;
        return; /* inline cache hit */
      } else {
        cache->obj = Qundef;
      }
    } else {
      struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL(self);

      if (iv_index_tbl && st_lookup(iv_index_tbl, (st_data_t)id, &index)) {
        cache->obj   = self;
        cache->ptr   = ROBJECT_IVPTR(self) + index;
        cache->klass = klass;
        cache->index = index;
      } else {
        cache->obj   = Qundef;
        cache->klass = Qundef;
      }
      /* fall through */
    }
  }
  rb_ivar_set(self, id, val);
}
#endif
