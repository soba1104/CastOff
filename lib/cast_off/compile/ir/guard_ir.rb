# coding=utf-8

module CastOff
  module Compiler
  module SimpleIR
    class GuardIR < IR
      attr_reader :guard_value, :variables_without_result, :variables, :result_variable, :values

      GUARD_DEOPTIMIZATION_TEMPLATE = ERB.new(<<-EOS, 0, '%-', 'g2')
  /* depth = <%= @insn.depth %> */
%  @information.undefined_variables.each do |var|
%    @insn.iseq.initialize_for_guards(var) if var.is_a?(LocalVariable)
%  end
%  top = @insn.iseq
%  a = [@insn.iseq]
%  a = @insn.iseq.ancestors.reverse + a if @translator.inline_block?
%  stacks = a.map{|s| s.depth}
%  stacks.shift
%  stacks.push(@insn.depth)
%  stacks = stacks.zip(a.map{|s| s.depth}).map{|d0, d1| d0 - d1}
%  valid = @translator.inline_block? ? @insn.depth : (@insn.depth - @insn.iseq.depth)
%  bug() unless stacks.inject(0){|sum, d| sum + d} == valid
%  a.each_with_index do |s, idx|
  {
%    local_c = s.lvars.size()
%    stack_c = stacks[idx]
%    if @translator.inline_block?
    int local_c = <%= local_c %>;
    VALUE local_v[<%= local_c %>];
%    end
    int stack_c = <%= stack_c %>;
    VALUE stack_v[<%= stack_c %>];
    rb_iseq_t *iseq = <%= s %>;
%    s.lvars.each_with_index do |(var_name, var_id, op_idx, depth, var_annotation), i|
%      if @translator.inline_block?
    local_v[<%= i %>] = local<%= var_id %>_<%= var_name %>; /* FIXME */
%      end
%    end
%    stack_c.times do |i|
    stack_v[<%= i %>] = tmp<%= s.depth + i %>;
%    end
%    method_p = (s.itype == :method ? 1 : 0)
%    lambda_p = (s.itype == :method ? 0 : 'lambda_p')
%    top_p    = (top == s ? 1 : 0)
%    bottom_p = (s.root? ? 1 : 0)
%    if @translator.inline_block?
%      if s.root?
    thval = rb_thread_current();
    th = DATA_PTR(thval);
    specval = 0;
    lfp = 0;
    dfp = 0;
%      else
    <%= s.loopkey.dopt_func %>(&<%= s.loopkey %>, specval);
%      end
%      if s == top
    return cast_off_deoptimize_inline(self, iseq, NULL, pc, local_c, local_v, stack_c, stack_v, <%= top_p %>, <%= bottom_p %>, <%= method_p %>, lfp, dfp);
%      else
%        bug() unless idx + 1 < a.size
%        biseq = a[idx + 1]
%        bug() unless biseq.parent_pc
    specval = cast_off_deoptimize_inline(self, iseq, <%= biseq %>, <%= biseq.parent_pc %>, local_c, local_v, stack_c, stack_v, <%= top_p %>, <%= bottom_p %>, <%= method_p %>, lfp, dfp);
%        if s.root?
    lfp = th->cfp->lfp;
%        end
    dfp = th->cfp->dfp;
%      end
%    else
    {
      VALUE return_value = cast_off_deoptimize_noinline(self, iseq, pc, stack_c, stack_v, <%= method_p %>, <%= lambda_p %>, <%= s.parent_pc ? s.parent_pc : -1 %>);
%      if s.catch_exception?
      TH_POP_TAG2();
%      end
      return return_value;
    }
%    end
  }
%  end
  rb_bug("should not be reached");
      EOS

      GUARD_EXCEPTION_FUNCTION_TEMPLATE = ERB.new(<<-EOS, 0, '%-', 'g1')
NORETURN(static inline int <THROW_EXCEPTION_FUNCTION_NAME>(VALUE obj));
static inline int <THROW_EXCEPTION_FUNCTION_NAME>(VALUE obj)
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

      GUARD_RECOMPILATION_FUNCTION_TEMPLATE = ERB.new(<<-EOS, 0, '%-', '__recompilation')
NOINLINE(static void <RECOMPILATION_FUNCTION_NAME>(VALUE obj));
static void <RECOMPILATION_FUNCTION_NAME>(VALUE obj)
{
#if 1
  if(!sampling_table) register_sampling_table(rb_hash_new());
%  count = 0
%  defs = get_definition(@guard_value)
%  defs.each do |defn|
%    case defn
%    when SubIR
%      case defn.src
%      when LocalVariable, DynamicVariable, InstanceVariable, ClassVariable, GlobalVariable, Self
%        count += 1
  sampling_variable(obj, ID2SYM(rb_intern("<%= defn.src.source %>")));
%      when ConstWrapper
%        # Fixme
  /* <%= defn.src.path %> */
%      when Literal
%        # nothing to do
%      else
%        bug(defn.src)
%      end
%    when InvokeIR
%      recv = defn.param_variables.first
%      bug() if recv.dynamic?
%      recv.types.each do |k|
%        recv_class = @translator.get_c_classname(k)
%        bug() unless recv_class
%        count += 1
  __sampling_poscall(obj, <%= recv_class %>, ID2SYM(rb_intern("<%= defn.method_id %>")));
%      end
%    end
%  end
%  if count > 0
  rb_funcall(rb_mCastOff, rb_intern("re_compile"), 2, rb_str_new2("<%= @translator.signiture() %>"), sampling_table_val);
%  else
%    dlog("skip recompilation: defs = \#{defs.join("\\n")}")
%  end
#endif
}
      EOS

      GUARD_TEMPLATE = ERB.new(<<-EOS, 0, '%-', 'g0')
%bug() if @guard_value.undefined? || @guard_value.dynamic?
<%= guard_begin() %>
%func = @translator.declare_recompilation_function(GUARD_RECOMPILATION_FUNCTION_TEMPLATE.trigger(binding))
    <%= func %>(<%= @guard_value %>);
%if @configuration.deoptimize?
    goto <%= @insn.guard_label %>;
%  @insn.iseq.inject_guard(@insn, GUARD_DEOPTIMIZATION_TEMPLATE.trigger(binding))
%else
%  func = @translator.declare_throw_exception_function(GUARD_EXCEPTION_FUNCTION_TEMPLATE.trigger(binding))
    <%= func %>(<%= guard_value %>);
%end
<%= guard_end() %>
      EOS

      GUARD_CHECK_TEMPLATE = ERB.new(<<-EOS, 0, '%-', 'g3')
%if @guard_value.is_just?(NilClass)
  if (UNLIKELY(!NIL_P(<%= @guard_value %>))) {
%elsif @guard_value.is_just?(TrueClass)
  if (UNLIKELY(<%= @guard_value %> != Qtrue)) {
%elsif @guard_value.is_just?(FalseClass)
  if (UNLIKELY(<%= @guard_value %> != Qfalse)) {
%elsif @guard_value.is_just?(Symbol)
  if (UNLIKELY(!SYMBOL_P(<%= @guard_value %>))) {
%elsif @guard_value.is_just?(Fixnum)
  if (UNLIKELY(!FIXNUM_P(<%= @guard_value %>))) {
%else
%  if simple?
%    func = @translator.declare_class_check_function(CLASS_CHECK_FUNCTION_TEMPLATE_SIMPLE.trigger(binding))
  if (UNLIKELY(!<%= func %>(<%= @guard_value %>))) {
%  else
%    func = @translator.declare_class_check_function(CLASS_CHECK_FUNCTION_TEMPLATE_COMPLEX.trigger(binding))
  if (UNLIKELY(!<%= func %>(<%= @guard_value %>, rb_class_of(<%= @guard_value %>)))) {
%  end
%end

      EOS

      CLASS_CHECK_FUNCTION_TEMPLATE_SIMPLE = ERB.new(<<-EOS, 0, '%-', 'g4')
static inline int <CLASS_CHECK_FUNCTION_NAME>(VALUE obj)
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
NOINLINE(static int <CLASS_CHECK_FUNCTION_NAME>_failed(VALUE obj, VALUE klass));

static inline int <CLASS_CHECK_FUNCTION_NAME>(VALUE obj, VALUE klass)
{
  if (0) {
%  @guard_value.types.each do |klass|
%    name = @translator.get_c_classname(klass)
%    raise(CompileError.new("can't generate guard for \#{klass}, you should pass binding to CastOff (\#{klass.singleton? ? 1 : 0})")) unless name
  } else if (LIKELY(klass == <%= name %>)) {
    return 1;
%  end
  } else {
    if (LIKELY(<CLASS_CHECK_FUNCTION_NAME>_failed(obj, klass))) {
      return 1;
    } else {
      return 0;
    }
  }
}

static int <CLASS_CHECK_FUNCTION_NAME>_failed(VALUE obj, VALUE klass)
{
  if (UNLIKELY(FL_TEST(klass, FL_SINGLETON) && empty_method_table_p(klass))) {
    return <CLASS_CHECK_FUNCTION_NAME>(obj, rb_obj_class(obj));
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
        level = @insn.iseq.generation
        while s
          s.lvars.each do |var_name, var_id, op_idx, depth, var_annotation|
            bug() unless depth == level
            if @translator.inline_block?
              targets << "local#{var_id}_#{var_name}" # FIXME
            else
              targets << "dfp#{depth}[#{op_idx}]" # FIXME
            end
          end
          level -= 1
          s = s.parent
        end
        bug() unless level == -1
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
end

