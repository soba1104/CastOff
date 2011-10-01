# coding=utf-8

module CastOff::Compiler
  module SimpleIR
    class GuardIR < IR
      attr_reader :guard_value, :variables_without_result, :variables, :result_variable, :values

      GUARD_DEOPTIMIZATION_TEMPLATE = ERB.new(<<-EOS, 0, '%-', 'g2')
  /* depth = <%= @insn.depth %> */
%  @information.undefined_variables.each do |var|
%    @insn.iseq.initialize_for_guards(var) if var.is_a?(LocalVariable)
%  end
%  s = @insn.iseq
%  d = @insn.depth
%  simple = s.root?
%  while s do
  {
%    local_c = s.lvars.size()
%    stack_c = d - s.depth
    rb_iseq_t *iseq = <%= s %>;
    int local_c = <%= local_c %>;
    VALUE local_v[<%= local_c %>];
    int stack_c = <%= stack_c %>;
    VALUE stack_v[<%= stack_c %>];
%    index = 0
%    s.lvars.each do |var_name, var_id, var_annotation|
%      if @translator.inline_block?
    local_v[<%= index %>] = local<%= var_id %>_<%= var_name %>; /* FIXME */
%      else
    local_v[<%= index %>] = lvp[<%= var_id %>]; /* FIXME */
%      end
%      index += 1
%    end
%    index = stack_c - 1
%    while d > s.depth do
%      d -= 1
    stack_v[<%= index %>] = tmp<%= d %>;
%      index -= 1
%    end
%  if simple
    return cast_off_deoptimize_simple(self, iseq, pc, local_c, local_v, stack_c, stack_v);
%  else
    cast_off_deoptimize_not_implemented(self, iseq, pc, local_c, local_v, stack_c, stack_v);
%  end
  }
%    break if !@translator.inline_block?
%    s = s.parent
%  end
  rb_bug("should not be reached");
      EOS

      GUARD_EXCEPTION_FUNCTION_TEMPLATE = ERB.new(<<-EOS, 0, '%-', 'g1')
NORETURN(static inline int throw_exception_<%= @label %>(VALUE obj));
static inline int throw_exception_<%= @label %>(VALUE obj)
{
  VALUE path0 = rb_class_path(rb_class_of(obj));
  VALUE path1 = rb_class_path(rb_obj_class(obj));
  rb_raise(rb_eCastOffExecutionError, "\\
type mismatch: guard(<%= @guard_value %>:<%= "\#{@insn.pc}: \#{@insn.op}, depth = \#{@insn.depth}" %>)\\n\\
name = <%= @insn.iseq.name %>, line = <%= @source_line %>: source = %s\\n\\
expected <%= @guard_value.types %> but %s, %s\\n\\
<%= @translator.target_name() %>", <%= @source.to_s.inspect %>, RSTRING_PTR(path0), RSTRING_PTR(path1));
}
      EOS

      GUARD_TEMPLATE = ERB.new(<<-EOS, 0, '%-', 'g0')
%bug() if @guard_value.undefined? || @guard_value.dynamic?
<%= guard_begin() %>
%if @configuration.deoptimize?
    goto <%= @insn.guard_label %>;
%  @insn.iseq.inject_guard(@insn, GUARD_DEOPTIMIZATION_TEMPLATE.trigger(binding))
%else
%@translator.declare_throw_exception_function(GUARD_EXCEPTION_FUNCTION_TEMPLATE.trigger(binding))
    throw_exception_<%= @label %>(<%= guard_value %>);
%end
<%= guard_end() %>
      EOS

      GUARD_CHECK_TEMPLATE = ERB.new(<<-EOS, 0, '%-', 'g3')
%if @guard_value.is_just?(NilClass)
  if (!NIL_P(<%= @guard_value %>)) {
%elsif @guard_value.is_just?(TrueClass)
  if (<%= @guard_value %> != Qtrue) {
%elsif @guard_value.is_just?(FalseClass)
  if (<%= @guard_value %> != Qfalse) {
%elsif @guard_value.is_just?(Symbol)
  if (!SYMBOL_P(<%= @guard_value %>)) {
%elsif @guard_value.is_just?(Fixnum)
  if (!FIXNUM_P(<%= @guard_value %>)) {
%else
%  if simple?
%    @translator.declare_class_check_function(CLASS_CHECK_FUNCTION_TEMPLATE_SIMPLE.trigger(binding))
  if (!class_check_<%= @label %>(<%= @guard_value %>)) {
%  else
%    @translator.declare_class_check_function(CLASS_CHECK_FUNCTION_TEMPLATE_COMPLEX.trigger(binding))
  if (!class_check_<%= @label %>(<%= @guard_value %>, rb_class_of(<%= @guard_value %>))) {
%  end
%end

      EOS

      CLASS_CHECK_FUNCTION_TEMPLATE_SIMPLE = ERB.new(<<-EOS, 0, '%-', 'g4')
static inline int class_check_<%= @label %>(VALUE obj)
{
  if (0) {
%if @guard_value.is_also?(NilClass)
  } else if (NIL_P(obj)) {
    return 1;
%end
%if @guard_value.is_also?(TrueClass)
  } else if (obj == Qtrue) {
    return 1;
%end
%if @guard_value.is_also?(FalseClass)
  } else if (obj == Qfalse) {
    return 1;
%end
%if @guard_value.is_also?(Symbol)
  } else if (SYMBOL_P(obj)) {
    return 1;
%end
%if @guard_value.is_also?(Fixnum)
  } else if (FIXNUM_P(obj)) {
    return 1;
%end
  } else {
    return 0;
  }
}
      EOS

      CLASS_CHECK_FUNCTION_TEMPLATE_COMPLEX = ERB.new(<<-EOS, 0, '%-', 'g4')
NOINLINE(static int class_check_failed_<%= @label %>(VALUE obj, VALUE klass));

static inline int class_check_<%= @label %>(VALUE obj, VALUE klass)
{
  if (0) {
%  @guard_value.types.each do |klass|
%    name = @translator.get_c_classname(klass)
%    raise(CompileError.new("can't generate guard for \#{klass}, you should pass binding to CastOff (\#{klass.singleton? ? 1 : 0})")) unless name
  } else if (LIKELY(klass == <%= name %>)) {
    return 1;
%  end
  } else {
    if (LIKELY(class_check_failed_<%= @label %>(obj, klass))) {
      return 1;
    } else {
      return 0;
    }
  }
}

static int class_check_failed_<%= @label %>(VALUE obj, VALUE klass)
{
  if (UNLIKELY(FL_TEST(klass, FL_SINGLETON) && empty_method_table_p(klass))) {
    return class_check_<%= @label %>(obj, rb_obj_class(obj));
  }
  return 0;
}
      EOS

      def initialize(val, vars, insn, cfg)
	super(insn, cfg)
	@guard_value = val
	bug() unless @guard_value.is_a?(Variable)
	@values = [@guard_value]
	@variables = []
	@variables_without_result = []
	@variables << @guard_value
	@variables_without_result << @guard_value
	@result_variable = nil
	@dependent_variables = get_dependent_variables(vars)
	@source = @insn.source
	@source = @source.empty? ? nil : @source
	@source_line = @insn.line.to_s
	@label = self.__id__.to_s.gsub(/-/, "_")
      end

      ### unboxing begin ###
      def unboxing_prelude()
	# TODO inline api の返り値で unbox 可能なものは、class_exact にして伝播させること。
	if @guard_value.class_exact? && @guard_value.can_unbox?
	  @guard_value.can_unbox()
	else
	  @guard_value.can_not_unbox()
	end
      end

      def propergate_value_which_can_not_unbox(defs)
	change = false

	# forward
	change |= defs.can_not_unbox_variable_resolve_forward(@guard_value)

	# backward
	if @guard_value.can_not_unbox?
	  change |= defs.can_not_unbox_variable_resolve_backward(@guard_value)
	  if @configuration.deoptimize?
	    @dependent_variables.each do |v|
	      change |= v.can_not_unbox()
	    end
	  end
	end

	change
      end

      def propergate_box_value(defs)
	change = false

	# forward
	change |= defs.box_value_resolve_forward(@guard_value)

	# backward
	if @guard_value.boxed?
	  change |= defs.box_value_resolve_backward(@guard_value)
	  if @configuration.deoptimize?
	    @dependent_variables.each do |v|
	      v.box()
	      change |= defs.box_value_resolve_backward(v)
	    end
	  end
	end

	change
      end

      def propergate_unbox_value(defs)
	return false if @guard_value.can_not_unbox?
	bug() unless @guard_value.class_exact?
	defs.unbox_value_resolve(@guard_value)
      end
      ### unboxing end ###

      def propergate_exact_class(defs)
	defs.exact_class_resolve(@guard_value)
      end

      def to_c()
	if @configuration.inject_guard? && !@guard_value.class_exact?
	  bug() if @insn.pc == -1
	  bug() unless @insn.depth
	  GUARD_TEMPLATE.trigger(binding).chomp
	end
      end

      def type_propergation(defs)
	bug()
      end

      def mark(defs)
	if !@alive
	  @alive = true
	  defs.mark(@guard_value)
	  if @configuration.deoptimize?
	    @dependent_variables.each{|v| defs.mark(v)}
	  end
	  true
	else
	  false
	end
      end

      private
      
      def simple?
	bug() if @guard_value.dynamic?
	bug() if @guard_value.class_exact?
	special_consts = [NilClass, TrueClass, FalseClass, Symbol, Fixnum]
	special_consts.size.times do |i|
	  special_consts.combination(i + 1).each do |pattern|
	    return true if @guard_value.is_just?(pattern)
	  end
	end
	false
      end

      def guard_begin()
        GUARD_CHECK_TEMPLATE.trigger(binding).chomp.chomp
      end

      def guard_end()
        "  }"
      end

      def get_dependent_variables(vars)
	targets = []
	s = @insn.iseq
	while s
	  s.lvars.each do |var_name, var_id, var_annotation|
	    if @translator.inline_block?
	      targets << "local#{var_id}_#{var_name}" # FIXME
	    else
	      targets << "lvp[#{var_id}]" # FIXME
	    end
	  end
	  s = s.parent
	end
	d = @insn.depth
	while d > 0 do
	  d -= 1
	  targets << "tmp#{d}" # FIXME
	end
	vars.select{|v| targets.include?(v.to_name)}.uniq()
      end
    end

    class StandardGuard < GuardIR
      def to_debug_string()
	"StandardGuard(#{@guard_value.to_debug_string()})"
      end
    end

    class JumpGuard < GuardIR
      def initialize(val, vars, insn, cfg)
	super(val, vars, insn, cfg)
        @bool = bool_value()
      end

      def type_propergation(defs)
        defs.type_resolve(@guard_value) #分岐のみで使用されるインスタンス変数等のために必要
      end

      def reset()
	super()
	if @configuration.deoptimize?
	  @dependent_variables.map! do |v|
	    bug() unless v.is_a?(Variable)
	    @cfg.find_variable(v)
	  end
	  bug() if @dependent_variables.include?(nil)
	end
      end

      def to_debug_string()
	"JumpGuard(#{@guard_value.to_debug_string()})"
      end

      def to_c()
        bug() unless @bool == bool_value()
        super()
      end

      private

      def bool_value()
        bug() if @guard_value.dynamic?
        return false if @guard_value.is_just?(NilClass) || @guard_value.is_just?(FalseClass)
        return false if @guard_value.is_just?([NilClass, FalseClass])
        bug() if @guard_value.is_also?(NilClass) || @guard_value.is_also?(FalseClass)
        true
      end

      def guard_begin()
        if @bool
          "  if (UNLIKELY(!RTEST(#{@guard_value}))) {"
        else
          "  if (UNLIKELY(RTEST(#{@guard_value}))) {"
        end
      end
    end
  end
end

