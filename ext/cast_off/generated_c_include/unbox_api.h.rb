#if 1
#define __END__ /* void */
#else
require("erb");
require('rbconfig');
DATA.rewind();

ERB.new(DATA.read(), 0, '%-').run();
#endif
__END__
#define CBOOL2RBOOL(b) ((b) ? Qtrue : Qfalse)
static inline VALUE CDOUBLE2RINT(double f)
{
  if (f > 0.0) f = floor(f);
  if (f < 0.0) f = ceil(f);
  return FIXABLE(f) ? LONG2FIX((double)f) : rb_dbl2big(f);
}
static inline VALUE PLUS(long a, long b)
{
  long c = a + b;
  if (FIXABLE(c)) {
    return LONG2FIX(c);
  } else {
    return rb_big_plus(rb_int2big(a), rb_int2big(b));
  }
}
static inline VALUE MINUS(long a, long b)
{
  long c = a - b;
  if (FIXABLE(c)) {
    return LONG2FIX(c);
  } else {
    return rb_big_minus(rb_int2big(a), rb_int2big(b));
  }
}
static inline VALUE MULT(long a, long b)
{
  if (a == 0) {
    return LONG2FIX(0);
  } else {
    volatile long c = a * b;
    if (FIXABLE(c) && c / a == b) {
      return LONG2FIX(c);
    } else {
      return rb_big_mul(rb_int2big(a), rb_int2big(b));
    }
  }
}

%# arg size, [type0, type1, ...]
%[['float',
%  {'-' => 'uminus'},
%  0,
%  :unary_operator,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {},
%  {'VALUE' => 'DBL2NUM', 'double' => ''}],
% ['float',
%  {'' => 'to_f'},
%  0,
%  :unary_operator,
%  {'VALUE' => ''},
%  {},
%  {'VALUE' => '', 'double' => 'RFLOAT_VALUE'}],
% ['float',
%  {'' => 'to_i'},
%  0,
%  :unary_operator,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {},
%  {'VALUE' => 'CDOUBLE2RINT'}],
% ['fixnum',
%  {'-' => 'uminus'},
%  0,
%  :unary_operator,
%  {'VALUE' => 'FIX2LONG', 'long' => ''},
%  {},
%  {'VALUE' => 'LONG2NUM'}],
% ['fixnum',
%  {'(double)' => 'to_f'},
%  0,
%  :unary_operator,
%  {'VALUE' => 'FIX2LONG', 'long' => ''},
%  {},
%  {'VALUE' => 'DBL2NUM', 'double' => ''}],
% ['float_float',
%  {'+' => 'plus', '-' => 'minus', '*' => 'mult', '/' => 'div'},
%  1,
%  :binary_operator,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'DBL2NUM', 'double' => ''}],
% ['float_float',
%  {'>' => 'gt', '>=' => 'ge', '<' => 'lt', '<=' => 'le', '==' => 'eq', '==' => 'eqq'},
%  1,
%  :binary_operator,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'CBOOL2RBOOL'}],
% ['fixnum_fixnum',
%  {'PLUS' => 'plus', 'MINUS' => 'minus', 'MULT' => 'mult'},
%  1,
%  :function,
%  {'VALUE' => 'FIX2LONG', 'long' => ''},
%  {'VALUE' => 'FIX2LONG', 'long' => ''},
%  {'VALUE' => ''}],
% ['fixnum_float',
%  {'+' => 'plus', '-' => 'minus', '*' => 'mult'},
%  1,
%  :binary_operator,
%  {'VALUE' => '(double)FIX2LONG', 'long' => ''},
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'DBL2NUM', 'double' => ''}],
% ['fixnum_float',
%  {'>' => 'gt', '>=' => 'ge', '<' => 'lt', '<=' => 'le', '==' => 'eq', '==' => 'eqq'},
%  1,
%  :binary_operator,
%  {'VALUE' => '(double)FIX2LONG', 'long' => ''},
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'CBOOL2RBOOL'}],
% ['float_fixnum',
%  {'+' => 'plus', '-' => 'minus', '*' => 'mult', '/' => 'div'},
%  1,
%  :binary_operator,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => '(double)FIX2LONG', 'long' => ''},
%  {'VALUE' => 'DBL2NUM', 'double' => ''}],
% ['float_fixnum',
%  {'>' => 'gt', '>=' => 'ge', '<' => 'lt', '<=' => 'le', '==' => 'eq', '==' => 'eqq'},
%  1,
%  :binary_operator,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => '(double)FIX2LONG', 'long' => ''},
%  {'VALUE' => 'CBOOL2RBOOL'}]].each do |(function_name, h, argc, operation, reciever_converter, arguments_converter, return_value_converter)|
%  arguments_decls = arguments_converter.keys
%  reciever_decls  = reciever_converter.keys
%  return_value_decls  = return_value_converter.keys
%  reciever_permutation  = reciever_decls.map{|r| [r]}
%  arguments_permutation = Array.new(argc){arguments_decls}.flatten.permutation(argc).to_a.uniq
%  return_value_permutation  = return_value_decls.map{|r| [r]}
%  h.each do |(operator, name)|
%    ary = reciever_permutation.zip(Array.new(reciever_permutation.size){arguments_permutation}).map{|(_r, _a)| _a.map{|__a| _r + __a}}.inject(:+)
%    Array.new(return_value_permutation.size){ary}.zip(return_value_permutation).map{|(_a, _r)| _a.map{|__a| __a + _r}}.inject(:+).each do |ds|
%      raise unless ds.size >= 2
%      suffix       = ds.join('_')
%      reciever     = ds.shift
%      return_value = ds.pop
%      arguments    = ds
%      parameter = []
%      parameter << "#{reciever} v0"
%      arguments.each_with_index{|a, idx| parameter << "#{a} v#{idx + 1}"}
%      statement = []
%      statement << "#{reciever_converter[reciever]}(v0)"
%      arguments.each_with_index{|a, idx| statement << "#{arguments_converter[a]}(v#{idx + 1})"}
static inline <%= return_value %>
cast_off_inline_<%= function_name %>_<%= name %>_<%= suffix %>(<%= parameter.join(', ') %>)
{
%      case operation
%      when :unary_operator
%        raise unless argc == 0 && statement.size == 1
  return <%= return_value_converter[return_value] %>(<%= operator %>(<%= statement.first %>));
%      when :binary_operator
%        raise unless argc == 1 && statement.size == 2
  return <%= return_value_converter[return_value] %>(<%= statement.join(" #{operator} ") %>);
%      when :function
  return <%= return_value_converter[return_value] %>(<%= operator %>(<%= statement.join(", ") %>));
%      else
%        raise
%      end
}
%    end
%  end
%end

