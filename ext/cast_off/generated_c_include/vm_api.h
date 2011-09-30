extern VALUE rb_mCastOffCompiler;
extern VALUE rb_cCastOffConfiguration;
extern VALUE rb_cCastOffClassWrapper;
extern VALUE rb_cCastOffMethodWrapper;

static VALUE
rb_vm_set_finish_env(rb_thread_t * th)
{
  rb_control_frame_t *cfp = th->cfp;
  VALUE *finish_insn_seq;

  while(VM_FRAME_TYPE(cfp) != VM_FRAME_MAGIC_FINISH) {
    /* FIXME */
    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
  }
  finish_insn_seq = cfp->pc;

  vm_push_frame(th, 0, VM_FRAME_MAGIC_FINISH, Qnil, th->cfp->lfp[0], 0, th->cfp->sp, 0, 1);
  th->cfp->pc = (VALUE *)&finish_insn_seq[0];
  return Qtrue;
}

static void construct_method_frame(VALUE self, rb_thread_t *th, rb_iseq_t *iseq, long pc, int local_c, VALUE *local_v, int stack_c, VALUE *stack_v)
{
  rb_control_frame_t *cfp;
  VALUE *sp;
  int i;

  rb_vm_set_finish_env(th);
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
  *sp++ = Qnil;
  vm_push_frame(th, iseq, VM_FRAME_MAGIC_METHOD, self, 0 /* blockptr */, iseq->iseq_encoded + pc, sp, 0, 0);
  sp = th->cfp->sp;
  for(i = 0; i < stack_c; i++, sp++) {
    *sp = stack_v[i];
  }
  th->cfp->sp = sp;
}

static VALUE cast_off_deoptimize_simple(VALUE self, rb_iseq_t *iseq, long pc, int local_c, VALUE *local_v, int stack_c, VALUE *stack_v)
{
  VALUE val;
  VALUE thval = rb_thread_current();
  rb_thread_t *th = DATA_PTR(thval);
  rb_control_frame_t *rcfp = th->cfp;
  VALUE *rsp = rcfp->sp;

  construct_method_frame(self, th, iseq, pc, local_c, local_v, stack_c, stack_v);
  val = rb_funcall(rb_mCastOffCompiler, rb_intern("vm_exec"), 0);
  //val = vm_exec(th);

  if (th->cfp != rcfp || th->cfp->sp != rsp) {
    rb_bug("should not be reached (2)");
  }

  return val;
}
NOINLINE(static VALUE cast_off_deoptimize_simple(VALUE self, rb_iseq_t *iseq, long pc, int local_c, VALUE *local_v, int stack_c, VALUE *stack_v));

static void cast_off_deoptimize_not_implemented(VALUE self, rb_iseq_t *iseq, long pc, int local_c, VALUE *local_v, int stack_c, VALUE *stack_v)
{
  rb_raise(rb_eCastOffExecutionError, "type mismatch: sorry, deoptimization is not implemented yet");
}
NOINLINE(NORETURN(static void cast_off_deoptimize_not_implemented(VALUE self, rb_iseq_t *iseq, long pc, int local_c, VALUE *local_v, int stack_c, VALUE *stack_v)));

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

extern int cast_off_method_wrapper_fptr_eq(VALUE self, VALUE (*fptr)(ANYARGS));
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
    if (cast_off_method_wrapper_fptr_eq(m, fptr)) {
      return 1;
    }
  }

  return 0;
}
NOINLINE(static int should_be_call_directly_p(VALUE (*fptr)(ANYARGS)));

#define cast_off_get_constant(klass, id)  cast_off_get_ev_const(self, cast_off_orig_iseq->cref_stack, (klass), (id))
#define cast_off_get_cvar_base()          vm_get_cvar_base(cast_off_orig_iseq->cref_stack)

static VALUE
cast_off_get_ev_const(VALUE self, NODE *root_cref, VALUE orig_klass, ID id)
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
	    rb_autoload_load(klass, id);
	    goto search_continue;
	  } else {
	    return val;
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
    return rb_const_get(klass, id);
  } else {
    vm_check_if_namespace(orig_klass);
    return rb_const_get(orig_klass, id); /* FIXME */
    /* return rb_public_const_get_from(orig_klass, id); */
  }
}
NOINLINE(static VALUE cast_off_get_ev_const(VALUE self, NODE *root_cref, VALUE orig_klass, ID id));

#if 0
/* obj が gc されて、同じアドレスにオブジェクトが割り当てられた場合、キャッシュヒットしてしまうので、マークする必要がある */

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
