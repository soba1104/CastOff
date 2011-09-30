/* ----- string.c ----- */
#define STR_TMPLOCK FL_USER7
#define STR_NOEMBED FL_USER1
#define STR_SHARED  FL_USER2 /* = ELTS_SHARED */
#define STR_ASSOC   FL_USER3
#define STR_SHARED_P(s) FL_ALL((s), STR_NOEMBED|ELTS_SHARED)
#define STR_ASSOC_P(s)  FL_ALL((s), STR_NOEMBED|STR_ASSOC)
#define STR_NOCAPA  (STR_NOEMBED|ELTS_SHARED|STR_ASSOC)
#define STR_NOCAPA_P(s) (FL_TEST((s),STR_NOEMBED) && FL_ANY((s),ELTS_SHARED|STR_ASSOC))

/* ----- vm.c ----- */
static rb_control_frame_t *
vm_get_ruby_level_caller_cfp(rb_thread_t *th, rb_control_frame_t *cfp)
{
    if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	return cfp;
    }

    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);

    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	    return cfp;
	}

	if ((cfp->flag & VM_FRAME_FLAG_PASSED) == 0) {
	    break;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

static VALUE
make_localjump_error(const char *mesg, VALUE value, int reason)
{
    extern VALUE rb_eLocalJumpError;
    VALUE exc = rb_exc_new2(rb_eLocalJumpError, mesg);
    ID id;

    switch (reason) {
      case TAG_BREAK:
	CONST_ID(id, "break");
	break;
      case TAG_REDO:
	CONST_ID(id, "redo");
	break;
      case TAG_RETRY:
	CONST_ID(id, "retry");
	break;
      case TAG_NEXT:
	CONST_ID(id, "next");
	break;
      case TAG_RETURN:
	CONST_ID(id, "return");
	break;
      default:
	CONST_ID(id, "noreason");
	break;
    }
    rb_iv_set(exc, "@exit_value", value);
    rb_iv_set(exc, "@reason", ID2SYM(id));
    return exc;
}

void
rb_vm_localjump_error(const char *mesg, VALUE value, int reason)
{
    VALUE exc = make_localjump_error(mesg, value, reason);
    rb_exc_raise(exc);
}

/* ----- vm_method.c ----- */
static rb_method_entry_t*
search_method(VALUE klass, ID id)
{
    st_data_t body;
    if (!klass) {
	return 0;
    }

    while (!st_lookup(RCLASS_M_TBL(klass), id, &body)) {
	klass = RCLASS_SUPER(klass);
	if (!klass) {
	    return 0;
	}
    }

    return (rb_method_entry_t *)body;
}

static int
rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2)
{
    if (d1 == d2) return 1;
    if (!d1 || !d2) return 0;
    if (d1->type != d2->type) {
	return 0;
    }
    switch (d1->type) {
      case VM_METHOD_TYPE_ISEQ:
	return d1->body.iseq == d2->body.iseq;
      case VM_METHOD_TYPE_CFUNC:
	return
	  d1->body.cfunc.func == d2->body.cfunc.func &&
	  d1->body.cfunc.argc == d2->body.cfunc.argc;
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
	return d1->body.attr.id == d2->body.attr.id;
      case VM_METHOD_TYPE_BMETHOD:
	return RTEST(rb_equal(d1->body.proc, d2->body.proc));
      case VM_METHOD_TYPE_MISSING:
	return d1->original_id == d2->original_id;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_UNDEF:
	return 1;
      case VM_METHOD_TYPE_OPTIMIZED:
	return d1->body.optimize_type == d2->body.optimize_type;
      default:
	rb_bug("rb_method_entry_eq: unsupported method type (%d)\n", d1->type);
	return 0;
    }
}

int
rb_method_entry_eq(const rb_method_entry_t *m1, const rb_method_entry_t *m2)
{
    return rb_method_definition_eq(m1->def, m2->def);
}

/* ----- set noinline ----- */
NOINLINE(static rb_control_frame_t *vm_get_ruby_level_caller_cfp(rb_thread_t *th, rb_control_frame_t *cfp));
NOINLINE(static rb_method_entry_t* search_method(VALUE klass, ID id));

