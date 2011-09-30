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

