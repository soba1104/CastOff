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
#ifdef INJECT_GUARD
#define CFIX2RFIX(b) (FIXABLE?((b)) ? LONG2FIX((b)) : rb_raise(rb_eCastOffExecutionError, TYPE_ERROR_MESSAGE()))
#else
#define CFIX2RFIX(b) LONG2FIX((b))
#endif
static inline VALUE CDOUBLE2RINT(double f)
{
  if (f > 0.0) f = floor(f);
  if (f < 0.0) f = ceil(f);
  return FIXABLE(f) ? LONG2FIX((double)f) : rb_dbl2big(f);
}

%# arg size, [type0, type1, ...]
%[['float',
%  {'-' => 'uminus'},
%  0,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {},
%  {'VALUE' => 'DBL2NUM', 'double' => ''}],
% ['float',
%  {'' => 'to_f'},
%  0,
%  {'VALUE' => ''},
%  {},
%  {'VALUE' => '', 'double' => 'RFLOAT_VALUE'}],
% ['float',
%  {'' => 'to_i'},
%  0,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {},
%  {'VALUE' => 'CDOUBLE2RINT'}],
% ['fixnum',
%  {'-' => 'uminus'},
%  0,
%  {'VALUE' => 'FIX2LONG', 'long' => ''},
%  {},
%  {'VALUE' => 'CFIX2RFIX', 'long' => ''}],
% ['fixnum',
%  {'(double)' => 'to_f'},
%  0,
%  {'VALUE' => 'FIX2LONG', 'long' => ''},
%  {},
%  {'VALUE' => 'DBL2NUM', 'double' => ''}],
% ['float_float',
%  {'+' => 'plus', '-' => 'minus', '*' => 'mult', '/' => 'div'},
%  1,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'DBL2NUM', 'double' => ''}],
% ['float_float',
%  {'>' => 'gt', '>=' => 'ge', '<' => 'lt', '<=' => 'le', '==' => 'eq', '==' => 'eqq'},
%  1,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'CBOOL2RBOOL'}],
% ['fixnum_fixnum',
%  {'+' => 'plus', '-' => 'minus', '*' => 'mult', '/' => 'div'},
%  1,
%  {'VALUE' => 'FIX2LONG', 'long' => ''},
%  {'VALUE' => 'FIX2LONG', 'long' => ''},
%  {'VALUE' => 'CFIX2RFIX', 'long' => ''}],
% ['fixnum_float',
%  {'+' => 'plus', '-' => 'minus', '*' => 'mult', '/' => 'div'},
%  1,
%  {'VALUE' => '(double)FIX2LONG', 'long' => ''},
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'DBL2NUM', 'double' => ''}],
% ['fixnum_float',
%  {'>' => 'gt', '>=' => 'ge', '<' => 'lt', '<=' => 'le', '==' => 'eq', '==' => 'eqq'},
%  1,
%  {'VALUE' => '(double)FIX2LONG', 'long' => ''},
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => 'CBOOL2RBOOL'}],
% ['float_fixnum',
%  {'+' => 'plus', '-' => 'minus', '*' => 'mult', '/' => 'div'},
%  1,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => '(double)FIX2LONG', 'long' => ''},
%  {'VALUE' => 'DBL2NUM', 'double' => ''}],
% ['float_fixnum',
%  {'>' => 'gt', '>=' => 'ge', '<' => 'lt', '<=' => 'le', '==' => 'eq', '==' => 'eqq'},
%  1,
%  {'VALUE' => 'RFLOAT_VALUE', 'double' => ''},
%  {'VALUE' => '(double)FIX2LONG', 'long' => ''},
%  {'VALUE' => 'CBOOL2RBOOL'}]].each do |(function_name, h, argc, reciever_converter, arguments_converter, return_value_converter)|
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
%      if argc > 0
  return <%= return_value_converter[return_value] %>(<%= statement.join(" #{operator} ") %>);
%      else
%        raise unless statement.size == 1
  return <%= return_value_converter[return_value] %>(<%= operator %>(<%= statement.first %>));
%      end
}
%    end
%  end
%end

