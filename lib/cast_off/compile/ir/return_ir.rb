# coding=utf-8

module CastOff::Compiler
  module SimpleIR
    class ReturnIR < IR
      attr_reader :return_value, :variables_without_result, :variables, :result_variable, :values

      class ThrowObj
        attr_reader :type, :raw_state, :state

        def initialize(type, raw_state, state, flag, level)
          @type = type
          @raw_state = raw_state
          @state = state
        end
      end

      def initialize(retval, throwobj, insn, cfg)
        super(insn, cfg)
        @throwobj = throwobj
        @return_value = retval
        @values = [@return_value]
        @variables = []
        @variables_without_result = []
        if @return_value.is_a?(Variable)
          @variables << @return_value
          @variables_without_result << @return_value
        end
        @result_variable = nil
      end

      ### unboxing begin ###
      def unboxing_prelude()
        @return_value.box()
      end

      def propergate_boxed_value(defs)
        bug() unless @return_value.boxed?
        defs.propergate_boxed_value_backward(@return_value)
      end
      ### unboxing end ###

      def propergate_exact_class(defs)
        false
      end

      def to_c()
        if @insn.iseq.catch_exception?
          prereturn = "  TH_POP_TAG2();\n"
        else
          prereturn = ''
        end
        case @throwobj
        when ThrowObj 
          if @translator.inline_block?
            return prereturn + "  return_from_execute(#{@throwobj.raw_state}, #{@return_value});"
          else
            return prereturn + "  return return_block(#{@throwobj.raw_state}, #{@return_value}, lambda_p);"
          end
        when NilClass
          return prereturn + "  return #{@return_value};"
        end
        bug()
      end

      def type_propergation(defs)
        defs.type_resolve(@return_value)
      end

      def mark(defs)
        if !alive?
          alive()
          defs.mark(@return_value)
          true
        else
          false
        end
      end
    end
  end
end

