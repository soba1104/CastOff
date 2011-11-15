static rb_iseq_t *construct_iter_api_iseq(VALUE (*fptr)(ANYARGS), ID mid)
{
  VALUE putnil = rb_ary_new();
  VALUE pop = rb_ary_new();
  VALUE send = rb_ary_new();
  VALUE getlocal0 = rb_ary_new();
  VALUE getlocal1 = rb_ary_new();
  VALUE getlocal2 = rb_ary_new();
  VALUE leave = rb_ary_new();
  VALUE val = rb_ary_new();
  VALUE misc = rb_hash_new();
  VALUE locals = rb_ary_new();
  VALUE exception = rb_ary_new();
  VALUE body = rb_ary_new();
  VALUE iseqval;
  rb_iseq_t *iseq;

  /* create putnil instruction */
  rb_ary_push(putnil, ID2SYM(rb_intern("putnil")));

  /* create pop instruction */
  rb_ary_push(pop, ID2SYM(rb_intern("pop")));

  /* create send instruction */
  rb_ary_push(send, ID2SYM(rb_intern("send")));
  rb_ary_push(send, ID2SYM(mid)); /* mid */
  rb_ary_push(send, INT2FIX(2)); /* argc */
  rb_ary_push(send, Qnil); /* blockiseq */
  rb_ary_push(send, LONG2FIX(0)); /* flag */
  rb_ary_push(send, LONG2FIX(0)); /* */

  /* create getlocal instruction */
  rb_ary_push(getlocal0, ID2SYM(rb_intern("getlocal")));
  rb_ary_push(getlocal0, INT2FIX(4));
  rb_ary_push(getlocal1, ID2SYM(rb_intern("getlocal")));
  rb_ary_push(getlocal1, INT2FIX(3));
  rb_ary_push(getlocal2, ID2SYM(rb_intern("getlocal")));
  rb_ary_push(getlocal2, INT2FIX(2));

  /* create leave instruction */
  rb_ary_push(leave, ID2SYM(rb_intern("leave")));

  /*
   * [:magic, :major_version, :minor_version, :format_type, :misc,
   *  :name, :filename, :filepath, :line_no, :type, :locals, :args,
   *  :catch_table, :bytecode]
   */
  
#define ISEQ_MAJOR_VERSION 1
#define ISEQ_MINOR_VERSION 2
  rb_ary_push(val, rb_str_new2("YARVInstructionSequence/SimpleDataFormat")); /* magic */
  rb_ary_push(val, INT2FIX(ISEQ_MAJOR_VERSION)); /* major version */
  rb_ary_push(val, INT2FIX(ISEQ_MINOR_VERSION)); /* minor version */
  rb_ary_push(val, INT2FIX(1)); /* format type */

  /* misc */
  rb_hash_aset(misc, ID2SYM(rb_intern("arg_size")), INT2FIX(0));
  rb_hash_aset(misc, ID2SYM(rb_intern("local_size")), INT2FIX(4));
  rb_hash_aset(misc, ID2SYM(rb_intern("stack_max")), INT2FIX(3));
  rb_ary_push(val, misc);

  rb_ary_push(val, rb_str_new2("<compiled>")); /* name */
  rb_ary_push(val, rb_str_new2("<compiled>")); /* filename */
  rb_ary_push(val, Qnil); /* filepath */
  rb_ary_push(val, INT2FIX(-1)); /* line_no */
  rb_ary_push(val, ID2SYM(rb_intern("method"))); /* type */

  /* locals */
  rb_ary_push(locals, ID2SYM(rb_intern("recv")));
  rb_ary_push(locals, ID2SYM(rb_intern("key")));
  rb_ary_push(locals, ID2SYM(rb_intern("blockptr")));
  rb_ary_push(val, locals);

  /* args */
  rb_ary_push(val, INT2FIX(0));

  /* catch_table */
  rb_ary_push(val, exception);

  /* bytecode */
  rb_ary_push(body, putnil);
  rb_ary_push(body, pop);
  rb_ary_push(body, getlocal0);
  rb_ary_push(body, getlocal1);
  rb_ary_push(body, getlocal2);
  rb_ary_push(body, send);
  rb_ary_push(body, leave);
  rb_ary_push(val, body);

  /* create iseq from ary */
  iseqval = rb_iseq_load(val, Qnil, Qnil);
  if (rb_class_of(iseqval) != rb_cISeq) {
    rb_bug("construct_inline_api_iseq: should not be reached(0)");
  }
  iseq = DATA_PTR(iseqval);

  rb_define_singleton_method(rb_mCastOff, rb_id2name(mid), fptr, 2);
  return iseq;
}
NOINLINE(static rb_iseq_t *construct_iter_api_iseq(VALUE (*fptr)(ANYARGS), ID mid));

static rb_iseq_t*
search_iter_api_iseq(VALUE (*fptr)(ANYARGS), ID mid)
{
  VALUE deoptimization_iseq_table, val;
  rb_iseq_t *iseq;

  deoptimization_iseq_table = rb_const_get(rb_mCastOffCompiler, rb_intern("DEOPTIMIZATION_ISEQ_TABLE"));
  val = rb_hash_aref(deoptimization_iseq_table, ID2SYM(mid));
  if (rb_class_of(val) == rb_cISeq) {
    iseq = DATA_PTR(val);
  } else {
    iseq = construct_iter_api_iseq(fptr, mid);
    if (rb_class_of(iseq->self) != rb_cISeq) {
      rb_bug("search_iter_api_iseq: should not be reached(0), mid = %s", rb_id2name(mid));
    }
    rb_hash_aset(deoptimization_iseq_table, ID2SYM(mid), iseq->self);
  }

  return iseq;
}
NOINLINE(static rb_iseq_t* search_iter_api_iseq(VALUE (*fptr)(ANYARGS), ID mid));

#define iter_namegen(klass, mid, suffix) cast_off_ ## klass ## _ ## mid ## _ ## suffix
#define _iter_strgen(str) #str
#define iter_strgen(str) _iter_strgen(str)

#define define_deoptimization_iseq_fetch_function(klass, mid) \
static rb_iseq_t* \
iter_namegen(klass, mid, deoptimization_iseq)(void) \
{ \
  ID mid = rb_intern(iter_strgen(iter_namegen(klass, mid, deoptimize))); \
  return search_iter_api_iseq(iter_namegen(klass, mid, deoptimize), mid); \
} \
NOINLINE(static rb_iseq_t* iter_namegen(klass, mid, deoptimization_iseq)(void));

#define define_frame_construction_function(klass, mid) \
static void \
iter_namegen(klass, mid, construct_frame)(void *key, VALUE blockptr) \
{ \
  VALUE thval = rb_thread_current(); \
  rb_thread_t *th = DATA_PTR(thval); \
  rb_control_frame_t *cfp = th->cfp; \
  rb_iseq_t *iseq = iter_namegen(klass, mid, deoptimization_iseq)(); \
  VALUE *sp = cfp->sp; \
\
  CHECK_STACK_OVERFLOW(cfp, 1); \
  *sp++ = rb_mCastOff; \
  *sp++ = GC_GUARDED_PTR(key); \
  *sp++ = GC_GUARDED_PTR(blockptr); \
  vm_push_frame(th, iseq, VM_FRAME_MAGIC_METHOD, rb_mCastOff, 0, iseq->iseq_encoded + 1, sp, 0, 1); \
} \
NOINLINE(static void iter_namegen(klass, mid, construct_frame)(void *key, VALUE blockptr));

#define deoptimization_function_begin(klass, mid) \
static VALUE \
iter_namegen(klass, mid, deoptimize)(VALUE recv, VALUE k, VALUE b) \
{ \
  VALUE thval = rb_thread_current(); \
  rb_thread_t *th = DATA_PTR(thval); \
  rb_control_frame_t *cfp = th->cfp; \
  iter_namegen(klass, mid, t) *key = GC_GUARDED_PTR_REF(k); \
  cfp->lfp[0] = b; /* blockptr */ \
  {

#define deoptimization_function_end(klass, mid) \
  } \
} \
NOINLINE(static VALUE iter_namegen(klass, mid, deoptimize)(VALUE recv, VALUE k, VALUE b));

#define ArgError(a, b) rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)", (a), (b))
static inline int
cast_off_prepare_iter_api_lambda_args(int use_c, VALUE *use_v, int given_c, VALUE *given_v, int simple, int must, int opt_len, int post_len, int post_start, int rest_index)
{
  int i, num = -1;
  int rest_c = given_c;

  if (simple) {
    if (UNLIKELY(use_c != given_c)) {
      ArgError(given_c, use_c);
    }
    for (i = 0; i < use_c; i++) {
      use_v[i] = given_v[i];
    }
    return num;
  }

  /* mandatory */
  if (given_c < (must + post_len)) { /* check with post arg */
    ArgError(given_c, must + post_len);
  }

  for (i = 0; i < must; i++) {
    use_v[i] = given_v[i];
  }
  rest_c -= must;

  /* post arguments */
  if (post_len) {
    for (i = post_start; i < post_start + post_len; i++) {
      use_v[i] = given_v[i];
    }
    rest_c -= post_len;
  }

  /* opt arguments */
  if (opt_len) {
    if (rest_index == -1 && rest_c > opt_len) {
      ArgError(given_c, must + opt_len + post_len);
    }

    if (rest_c >= opt_len) {
      for (i = must; i < must + opt_len; i++) {
        use_v[i] = given_v[i];
      }
      num = must + opt_len;
      rest_c -= opt_len;
    } else {
      for (i = must; i< must + rest_c; i++) {
        use_v[i] = given_v[i];
      }
      for (i = must + rest_c; i < must + opt_len; i++) {
        use_v[i] = Qundef;
      }
      num = must + rest_c;
      rest_c = 0;
    }
  }

  /* rest arguments */
  if (rest_index != -1) {
    if (rest_c) {
      use_v[rest_index] = rb_ary_new4(rest_c, &given_v[must + opt_len]);
    } else {
      use_v[rest_index] = rb_ary_new();
    }
    rest_c = 0;
  }

  if (rest_c) rb_bug("cast_off_prepare_iter_api_lambda_args: should not be reached(0)");

  return num;
}

static inline int
cast_off_prepare_iter_api_block_args(int use_c, VALUE *use_v, int given_c, VALUE *given_v, int splat, int must, int opt_len, int post_len, int post_start, int rest_index)
{
  int i, cpy;
  volatile VALUE mark;
  int num = -1;

  if (splat) {
    VALUE ary;

    if(given_c == 1 && !NIL_P(ary = rb_check_array_type(given_v[0]))) { /* rhs is only an array */
      cpy = given_c = RARRAY_LENINT(ary);
      if (cpy > must) cpy = must;
      MEMCPY(use_v, RARRAY_PTR(ary), VALUE, cpy);
      mark = ary;
      given_v = RARRAY_PTR(ary);
    } else {
      cpy = given_c;
      if (cpy > must) cpy = must;
      for (i = 0; i < cpy; i++) {
        use_v[i] = given_v[i];
      }
    }
  } else {
    cpy = given_c;
    if (cpy > must) cpy = must;
    for (i = 0; i < cpy; i++) {
      use_v[i] = given_v[i];
    }
  }
  for (i = cpy; i < must; i++) {
    use_v[i] = Qnil;
  }

  if (post_len || opt_len) {
    int rsize = given_c > must ? given_c - must : 0;    /* # of arguments which did not consumed yet */
    int psize = rsize > post_len ? post_len : rsize;  /* # of post arguments */
    int osize = 0;  /* # of opt arguments */
    VALUE ary;

    /* reserves arguments for post parameters */
    rsize -= psize;

    if (opt_len) {
      if (rsize >= opt_len) {
        osize = opt_len;
        num = must + opt_len;
        for (i = must; i < num; i++) {
          use_v[i] = given_v[i];
        }
      } else {
        osize = rsize;
        num = must + rsize;
        for (i = must; i < num; i++) {
          use_v[i] = given_v[i];
        }
        for (i = num; i < must + opt_len; i++) {
          use_v[i] = Qundef;
        }
      }
    }
    rsize -= osize;

    if (rest_index == -1) {
        /* copy post argument */
        MEMMOVE(&use_v[post_start], &given_v[must + osize], VALUE, psize);
    } else {
        ary = rb_ary_new4(rsize, &given_v[rest_index]);

        /* copy post argument */
        MEMMOVE(&use_v[post_start], &given_v[must + rsize + osize], VALUE, psize);
        use_v[rest_index] = ary;
    }

    for (i = psize; i < post_len; i++) {
        use_v[post_start + i] = Qnil;
    }
  } else {
    /* not opts and post_index */
    if (rest_index != -1) {
      if (given_c < rest_index) {
        for (i = given_c; i < rest_index; i++) {
          use_v[i] = Qnil;
        }
        use_v[rest_index] = rb_ary_new();
      } else {
        use_v[rest_index] = rb_ary_new4(given_c - rest_index, &given_v[rest_index]);
      }
    }
  }

#if 0
  if (block_index != -1) {
    VALUE procval;

    if (rb_block_given_p()) {
      procval = rb_block_proc();
    } else {
      procval = Qnil;
    }
    use_v[block_index] = procval;
  }
#endif

  return num;
}

/* Fixnum#times */
typedef struct cast_off_Fixnum_times_struct {
  long fin;
  long index;
} cast_off_Fixnum_times_t;

static inline VALUE
cast_off_Fixnum_times_prep(cast_off_Fixnum_times_t *key, VALUE recv, int prep_argc, ...)
{
  int i;
  VALUE ret;

  if (prep_argc != 0) {
    rb_raise(rb_eArgError, "invalid argument");
  }

  key->fin = FIX2LONG(recv);
  key->index = 0;

  return recv;
}

static inline VALUE
cast_off_Fixnum_times_loop(cast_off_Fixnum_times_t *key, VALUE val, int argc, VALUE *argv, int splat, int must, int post_len, int post_start, int rest_index)
{
  int i;
  long fin = key->fin;
  long index = key->index;

  if (index < fin) {
    for (i = 0; i < argc; i++) {
      if (i == 0) {
        argv[0] = LONG2FIX(index);
      } else {
        argv[i] = Qnil;
      }
    }
    key->index = index + 1;
    return Qtrue;
  } else {
    return Qfalse;
  }
}

static inline VALUE
cast_off_Fixnum_times_finl(cast_off_Fixnum_times_t *key)
{
  return LONG2FIX(key->fin);
}
 
deoptimization_function_begin(Fixnum, times) {
  while(key->index < key->fin) {
    rb_yield(LONG2FIX(key->index));
    key->index++;
  }
  return LONG2FIX(key->fin);
};
deoptimization_function_end(Fixnum, times);
define_deoptimization_iseq_fetch_function(Fixnum, times);
define_frame_construction_function(Fixnum, times);

/* Array#map */
typedef struct cast_off_Array_map_struct {
  VALUE recv;
  long index;
  VALUE ret;
} cast_off_Array_map_t;

static inline VALUE
cast_off_Array_map_prep(cast_off_Array_map_t *key, VALUE recv, int prep_argc, ...)
{
  VALUE ret;

  if (prep_argc != 0) {
    rb_raise(rb_eArgError, "invalid argument");
  }

  ret = rb_ary_new2(RARRAY_LEN(recv));

  key->recv = recv;
  key->index = 0;
  key->ret = ret;

  return ret;
}

static inline VALUE
cast_off_Array_map_loop(cast_off_Array_map_t *key, VALUE val, int argc, VALUE *argv, int splat, int must, int post_len, int post_start, int rest_index)
{
  int i;
  VALUE recv = key->recv;
  long index = key->index;

  if (index > 0) {
    rb_ary_push(key->ret, val);
  }

  if (index < RARRAY_LEN(recv)) {
    VALUE v[1];

    v[0] = RARRAY_PTR(recv)[index];
    cast_off_prepare_iter_api_block_args(argc, argv, 1, v, splat, must, 0, post_len, post_start, rest_index);
    key->index = index + 1;
    return Qtrue;
  } else {
    return Qfalse;
  }
}

static inline VALUE
cast_off_Array_map_finl(cast_off_Array_map_t *key)
{
  return key->ret;
}

deoptimization_function_begin(Array, map) {
  while (key->index < RARRAY_LEN(key->recv)) {
    rb_ary_push(key->ret, rb_yield(RARRAY_PTR(key->recv)[key->index]));
    key->index++;
  }
  return key->ret;
};
deoptimization_function_end(Array, map);
define_deoptimization_iseq_fetch_function(Array, map);
define_frame_construction_function(Array, map);

/* Array#map! */
typedef struct cast_off_Array_map_bang_struct {
  VALUE recv;
  long index;
} cast_off_Array_map_bang_t;

static inline VALUE
cast_off_Array_map_bang_prep(cast_off_Array_map_bang_t *key, VALUE recv, int prep_argc, ...)
{
  if (prep_argc != 0) {
    rb_raise(rb_eArgError, "invalid argument");
  }

  rb_ary_modify(recv);

  key->recv = recv;
  key->index = 0;

  return recv;
}

static inline VALUE
cast_off_Array_map_bang_loop(cast_off_Array_map_bang_t *key, VALUE val, int argc, VALUE *argv, int splat, int must, int post_len, int post_start, int rest_index)
{
  int i;
  VALUE recv = key->recv;
  long index = key->index;

  if (index > 0) {
    rb_ary_store(recv, index - 1, val);
  }

  if (index < RARRAY_LEN(recv)) {
    VALUE v[1];

    v[0] = RARRAY_PTR(recv)[index];
    cast_off_prepare_iter_api_block_args(argc, argv, 1, v, splat, must, 0, post_len, post_start, rest_index);
    key->index = index + 1;
    return Qtrue;
  } else {
    return Qfalse;
  }
}

static inline VALUE
cast_off_Array_map_bang_finl(cast_off_Array_map_bang_t *key)
{
  return key->recv;
}

deoptimization_function_begin(Array, map_bang) {
  while (key->index < RARRAY_LEN(key->recv)) {
    rb_ary_store(key->recv, key->index, rb_yield(RARRAY_PTR(key->recv)[key->index]));
    key->index++;
  }
  return key->recv;
};
deoptimization_function_end(Array, map_bang);
define_deoptimization_iseq_fetch_function(Array, map_bang);
define_frame_construction_function(Array, map_bang);

/* Array#each */
typedef struct cast_off_Array_each_struct {
  VALUE recv;
  long index;
} cast_off_Array_each_t;

static inline VALUE
cast_off_Array_each_prep(cast_off_Array_each_t *key, VALUE recv, int prep_argc, ...)
{
  int i;

  if (prep_argc != 0) {
    rb_raise(rb_eArgError, "invalid argument");
  }

  key->recv = recv;
  key->index = 0;

  return recv;
}
 
static inline VALUE
cast_off_Array_each_loop(cast_off_Array_each_t *key, VALUE val, int argc, VALUE *argv, int splat, int must, int post_len, int post_start, int rest_index)
{
  int i;
  VALUE recv = key->recv;
  long index = key->index;

  if (index < RARRAY_LEN(recv)) {
    VALUE v[1];

    v[0] = RARRAY_PTR(recv)[index];
    cast_off_prepare_iter_api_block_args(argc, argv, 1, v, splat, must, 0, post_len, post_start, rest_index);
    key->index = index + 1;
    return Qtrue;
  } else {
    return Qfalse;
  }
}

static inline VALUE
cast_off_Array_each_finl(cast_off_Array_each_t *key)
{
  return key->recv;
}

deoptimization_function_begin(Array, each) {
  while (key->index < RARRAY_LEN(key->recv)) {
    rb_yield(RARRAY_PTR(key->recv)[key->index]);
    key->index++;
  }
  return key->recv;
};
deoptimization_function_end(Array, each);
define_deoptimization_iseq_fetch_function(Array, each);
define_frame_construction_function(Array, each);

