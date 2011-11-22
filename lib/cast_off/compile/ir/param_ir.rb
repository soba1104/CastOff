# coding=utf-8

module CastOff::Compiler
  module SimpleIR
    class ParamIR < IR
      attr_reader :param_value, :variables_without_result, :variables, :result_variable, :values
      def initialize(val, insn, cfg)
        super(insn, cfg)
        @param_value = val
        @values = [@param_value]
        @variables = []
        @variables_without_result = []
        if @param_value.is_a?(Variable)
          @variables << @param_value
          @variables_without_result << @param_value
        end
        @result_variable = nil
        @need_guard = nil
      end

      ### unboxing begin ###
      def unboxing_prelude()
        # nothing to do
      end

      def propergate_boxed_value(defs)
        change = false

        # forward
        change |= defs.propergate_boxed_value_forward(@param_value)

        # backward
        change |= defs.propergate_boxed_value_backward(@param_value) if @param_value.boxed?

        change
      end
      ### unboxing end ###

      def propergate_exact_class(defs)
        defs.exact_class_resolve(@param_value)
      end

      def to_c()
        bug()
      end

      def type_propergation(defs)
        defs.type_resolve(@param_value)
      end

      def need_guard(bool)
        @need_guard = !!bool
      end

      def reset()
        @need_guard = nil
        super()
      end

      def standard_guard_target()
        need_guard? ? @param_value : nil
      end

      def mark(defs)
        alive? && defs.mark(@param_value)
      end

      private

      def need_guard?()
        bug() if @need_guard.nil?
        @need_guard
      end
    end
  end
end

