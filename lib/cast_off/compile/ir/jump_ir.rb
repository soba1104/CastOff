# coding=utf-8

module CastOff::Compiler
  module SimpleIR
    class JumpIR < IR
      attr_reader :cond_value, :jump_targets, :jump_type, :variables_without_result, :variables, :result_variable, :values

      def initialize(val, insn, cfg)
        super(insn, cfg)

        @cond_value = val
        @jump_type = insn.op
        argv = insn.argv
        case @jump_type
        when :jump, :branchif, :branchunless, :cast_off_enter_block, :cast_off_leave_block, :cast_off_continue_loop
          @jump_targets = [argv[0]]
          @must = nil
          @post = nil
        when :cast_off_break_block
          @jump_targets = [argv[0]]
          @raw_state = argv[1]
          bug() unless @raw_state
          @exc_pc = argv[2]
          bug() unless @exc_pc >= 0
          @must = nil
          @post = nil
        when :cast_off_handle_optional_args
          @jump_targets = argv[0]
          @must = argv[1]
          @post = argv[2]
        else
          bug()
        end
        bug() unless @jump_targets.is_a?(Array)
        @values = @cond_value ? [@cond_value] : []
        @variables = []
        @variables_without_result = []
        if @cond_value.is_a?(Variable)
          @variables << @cond_value
          @variables_without_result << @cond_value
        end
        @result_variable = nil
      end

      ### unboxing begin ###
      def unboxing_prelude()
        @cond_value.box() if @cond_value
      end

      def propergate_boxed_value(defs)
        return false unless @cond_value
        bug() unless @cond_value.boxed?
        defs.propergate_boxed_value_backward(@cond_value)
      end
      ### unboxing end ###

      def propergate_exact_class(defs)
        @cond_value ? defs.exact_class_resolve(@cond_value) : false
      end

      def to_debug_string()
        "Jump(#{@jump_type}#{@cond_value ? " : #{@cond_value.to_debug_string()}" : ''}) => #{@jump_targets}"
      end

      def to_c()
        ret = []
        # FIXME detect backedge
        # FIXME add interrupt check when ehable intterupt check option
        s = sampling_variable()
        ret << s if s
        case @jump_type
        when :cast_off_enter_block
          if @translator.inline_block?
            bug() unless @jump_targets.size() == 1
            ret << "  goto #{@jump_targets[0]};"
          end
        when :cast_off_leave_block
          if @translator.inline_block?
            bug() unless @jump_targets.size() == 1
            ret << "  goto #{@jump_targets[0]};"
          else
            ret << "  return tmp#{@insn.iseq.depth};" # FIXME
          end
        when :cast_off_break_block
          if @translator.inline_block?
            bug() unless @jump_targets.size() == 1
            ret << "  goto #{@jump_targets[0]};"
          else
            ret << "  break_block(#{@raw_state}, #{@exc_pc}, tmp#{@insn.iseq.depth});" # FIXME
          end
        when :cast_off_continue_loop
          if @translator.inline_block?
            bug() unless @jump_targets.size() == 1
            ret << "  if (RTEST(#{@cond_value})) goto #{@jump_targets[0]};"
          end
        when :jump
          bug() unless @jump_targets.size() == 1
          #ret << "  RUBY_VM_CHECK_INTS();"
          ret << "  goto #{@jump_targets[0]};"
        when :branchunless
          bug() unless @jump_targets.size() == 1
          ret << "  if (!RTEST(#{@cond_value})) goto #{@jump_targets[0]};"
=begin
            ret << <<-EOS
  if (!RTEST(#{@cond_value})) {
    RUBY_VM_CHECK_INTS();
    goto #{@jump_targets[0]};
  }
            EOS
=end
          when :branchif
            bug() unless @jump_targets.size() == 1
            ret << "  if (RTEST(#{@cond_value})) goto #{@jump_targets[0]};"
=begin
            ret << <<-EOS
  if (RTEST(#{@cond_value})) {
    RUBY_VM_CHECK_INTS();
    goto #{@jump_targets[0]};
  }
            EOS
=end
        when :cast_off_handle_optional_args
          bug() unless @jump_targets.size() > 1
          bug() unless @cond_value.is_just?(Fixnum)
          ret << "  switch(#{@cond_value}) {"
          @jump_targets.each_with_index do |t, i|
            ret << "    case(INT2FIX(#{i + @must})): goto #{t};"
          end
          if @post
            ret << <<-EOS
    default: {
      int num = FIX2INT(#{@cond_value});
      if (num >= #{@jump_targets.size() + @must}) {
        goto #{@jump_targets.last};
      } else {
        rb_bug("should not be reached");
      }
    }
            EOS
          else
            ret << "    default: rb_bug(\"should not be reached\");"
          end
          ret << "  }"
        else
          bug("unexpected jump type #{@jump_type}")
        end
        ret.join("\n")
      end

      def type_propergation(defs)
        @cond_value ? defs.type_resolve(@cond_value) : false
      end

      def unused_target()
        case @jump_type
        when :jump
          bug()
        when :cast_off_handle_optional_args, :cast_off_enter_block, :cast_off_leave_block, :cast_off_continue_loop, \
             :cast_off_break_block
          # nothing to do
          return nil
        when :branchif, :branchunless
          bug() if @cond_value.undefined?
          return nil if @cond_value.dynamic?
          nil_wrapper = ClassWrapper.new(NilClass, true)
          false_wrapper = ClassWrapper.new(FalseClass, true)
          classes = @cond_value.types
          bug() if classes.empty?
          constant = true
          bool = nil
          classes.each do |c|
            if c == nil_wrapper || c == false_wrapper
              __bool = false
            else
              __bool = true
            end
            if bool.nil?
              bool = __bool
            else
              unless bool == __bool
                constant = false
                break
              end
            end
          end
          if constant
            bug() if bool.nil?
            fallthrough = (bool && @jump_type == :branchunless) || (!bool && @jump_type == :branchif)
            bug() if @jump_targets.size() != 1
            target = @jump_targets[0]
            return fallthrough ? target : :fallthrough
          else
            return nil
          end
        end
        bug()
      end

      def mark(defs)
        if !alive?
          alive()
          defs.mark(@cond_value) if @cond_value
          true
        else
          false
        end
      end
    end
  end
end

