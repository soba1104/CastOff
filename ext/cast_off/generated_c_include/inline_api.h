#define TYPE_ERROR_MESSAGE() "type mismatch"

static inline VALUE
cast_off_inline_fixnum_and(VALUE recv, VALUE obj)
{
  long val;

#if 0
#ifdef INJECT_GUARD
  if (UNLIKELY(!FIXNUM_2_P(recv, obj))) {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
#endif

  val = FIX2LONG(recv) & FIX2LONG(obj);
#ifdef INJECT_GUARD
  if (LIKELY(FIXABLE(val))) {
#endif
    return LONG2FIX(val);
#ifdef INJECT_GUARD
  } else {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
}

static inline VALUE
cast_off_inline_array_entry(VALUE ary, VALUE index)
{
  long offset;

#if 0
#ifdef INJECT_GUARD
  if (UNLIKELY(rb_class_of(ary) != rb_cArray || !FIXNUM_P(index))) {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
#endif
  offset = FIX2LONG(index);

#ifdef ARRAY_CONSERVATIVE
  return rb_ary_entry(ary, offset);
#else
  return RARRAY_PTR(ary)[offset];
#endif
}

static inline VALUE
cast_off_inline_array_store(VALUE ary, VALUE index, VALUE val)
{
#if 0
#ifdef INJECT_GUARD
  if (UNLIKELY(rb_class_of(ary) != rb_cArray || !FIXNUM_P(index))) {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
#endif

#ifdef ARRAY_CONSERVATIVE
  rb_ary_store(ary, FIX2LONG(index), val);
#else
  RARRAY_PTR(ary)[FIX2LONG(index)] = val;
#endif
  return val;
}

static inline VALUE
cast_off_inline_array_length(VALUE ary)
{
  long len;

#if 0
#ifdef INJECT_GUARD
  if (UNLIKELY(rb_class_of(ary) != rb_cArray)) {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
#endif

  len = RARRAY_LEN(ary);

#ifdef INJECT_GUARD
  if (LIKELY(FIXABLE(len))) {
#endif
    return LONG2FIX(len);
#ifdef INJECT_GUARD
  } else {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
}
#define cast_off_inline_array_size(ary) cast_off_inline_array_length((ary))

static inline VALUE
cast_off_inline_array_empty_p(VALUE ary)
{
#if 0
#ifdef INJECT_GUARD
  if (UNLIKELY(rb_class_of(ary) != rb_cArray)) {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
#endif

  if (RARRAY_LEN(ary) == 0) {
    return Qtrue;
  } else {
    return Qfalse;
  }
}

static inline VALUE
cast_off_inline_array_first(VALUE ary)
{
#if 0
#ifdef INJECT_GUARD
  if (UNLIKELY(rb_class_of(ary) != rb_cArray)) {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
#endif

#ifdef ARRAY_CONSERVATIVE
  if (RARRAY_LEN(ary) == 0) return Qnil;
#endif
  return RARRAY_PTR(ary)[0];
}

static inline VALUE
cast_off_inline_array_last(VALUE ary)
{
#if 0
#ifdef INJECT_GUARD
  if (UNLIKELY(rb_class_of(ary) != rb_cArray)) {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
#endif

#ifdef ARRAY_CONSERVATIVE
  if (RARRAY_LEN(ary) == 0) return Qnil;
#endif
  return RARRAY_PTR(ary)[RARRAY_LEN(ary)-1];
}

static inline VALUE
cast_off_inline_string_eq(VALUE str1, VALUE str2)
{
#if 0
#ifdef INJECT_GUARD
  if (UNLIKELY(rb_class_of(str1) != rb_cString || rb_class_of(str2) != rb_cString)) {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
#endif

  if (str1 == str2) return Qtrue;
  if (RSTRING_LEN(str1) != RSTRING_LEN(str2)) return Qfalse;
  return rb_str_equal(str1, str2);
}
#define cast_off_inline_string_eqq(str1, str2) cast_off_inline_string_eq((str1), (str2))

static inline VALUE
cast_off_inline_string_neq(VALUE str1, VALUE str2)
{
#if 0
#ifdef INJECT_GUARD
  if (UNLIKELY(rb_class_of(str1) != rb_cString || rb_class_of(str2) != rb_cString)) {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
#endif

  if (str1 == str2) return Qfalse;
  if (RSTRING_LEN(str1) != RSTRING_LEN(str2)) return Qtrue;
  if (rb_str_equal(str1, str2) == Qtrue) {
    return Qfalse;
  } else {
    return Qtrue;
  }
}

static inline VALUE
cast_off_inline_string_empty_p(VALUE str)
{
#if 0
#ifdef INJECT_GUARD
  if (UNLIKELY(rb_class_of(str) != rb_cString)) {
    rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE());
  }
#endif
#endif

  if (RSTRING_LEN(str) == 0) {
    return Qtrue;
  } else {
    return Qfalse;
  }
}

static inline VALUE
cast_off_inline_string_plus(VALUE str1, VALUE str2)
{
    VALUE str3;
    rb_encoding *enc;

    /* StringValue(str2); */ /* str2 is always String */
    enc = rb_enc_check(str1, str2);
    str3 = rb_str_new(0, RSTRING_LEN(str1)+RSTRING_LEN(str2));
    memcpy(RSTRING_PTR(str3), RSTRING_PTR(str1), RSTRING_LEN(str1));
    memcpy(RSTRING_PTR(str3) + RSTRING_LEN(str1),
           RSTRING_PTR(str2), RSTRING_LEN(str2));
    RSTRING_PTR(str3)[RSTRING_LEN(str3)] = '\0';

    if (OBJ_TAINTED(str1) || OBJ_TAINTED(str2))
        OBJ_TAINT(str3);
    ENCODING_CODERANGE_SET(str3, rb_enc_to_index(enc),
                           ENC_CODERANGE_AND(ENC_CODERANGE(str1), ENC_CODERANGE(str2)));
    return str3;
}

static inline VALUE
cast_off_inline_string_concat(VALUE str1, VALUE str2)
{
  /* StringValue(str2); */ /* str2 is always String */
  if (RSTRING_LEN(str2) > 0 && STR_ASSOC_P(str1)) {
    return rb_str_append(str1, str2);
  } else {
    return rb_str_buf_append(str1, str2);
  }
}

