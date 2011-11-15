# coding=utf-8

module CastOff::Compiler
  module Instruction
    extend CastOff::Util

    VM_CALL_ARGS_SPLAT_BIT     = (0x01 << 1)
    VM_CALL_ARGS_BLOCKARG_BIT  = (0x01 << 2)
    VM_CALL_FCALL_BIT          = (0x01 << 3)
    VM_CALL_VCALL_BIT          = (0x01 << 4)
    VM_CALL_TAILCALL_BIT       = (0x01 << 5)
    VM_CALL_TAILRECURSION_BIT  = (0x01 << 6)
    VM_CALL_SUPER_BIT          = (0x01 << 7)
    VM_CALL_OPT_SEND_BIT       = (0x01 << 8)

    SupportInstruction = [
      :trace, :nop, :putnil, :getdynamic, :send, :leave, :putobject, :putself, :putstring, :newrange,
      :newarray, :duparray, :tostring, :concatstrings, :setdynamic, :newhash, :branchunless, :branchif, :toregexp,
      :adjuststack, :dup, :dupn, :setn, :pop, :jump, :opt_plus, :opt_minus, :opt_mult, :opt_div, :opt_mod, :opt_succ,
      :opt_lt, :opt_le, :opt_gt, :opt_ge, :opt_neq, :opt_eq, :opt_length, :opt_size, :opt_ltlt, :opt_aref, :opt_not,
      :getinlinecache, :setinlinecache, :getconstant, :swap, :topn, :concatarray, :getinstancevariable, :setinstancevariable,
      :getclassvariable, :setclassvariable, :getglobal, :setglobal, :getlocal, :setlocal, :opt_case_dispatch,
      :opt_regexpmatch1, :opt_regexpmatch2, :expandarray, :splatarray, :checkincludearray, :getspecial, :invokeblock,
      :throw, :defined,
      :cast_off_prep, :cast_off_loop, :cast_off_cont, :cast_off_finl,
      :cast_off_getlvar, :cast_off_setlvar, :cast_off_getivar, :cast_off_setivar,
      :cast_off_getcvar, :cast_off_setcvar, :cast_off_getgvar, :cast_off_setgvar,
      :cast_off_handle_optional_args, :cast_off_fetch_args, :cast_off_decl_arg, :cast_off_decl_var,
      :cast_off_getconst, :cast_off_enter_block, :cast_off_leave_block, :cast_off_continue_loop,
      :cast_off_break_block,
      :cast_off_getdvar, :cast_off_setdvar,
    ]

    IgnoreInstruction = [
      :trace, :setinlinecache, :nop
    ]

    BlockSeparator = [
      :leave, :throw, :branchunless, :jump, :branchif, :cast_off_handle_optional_args,
      :cast_off_enter_block, :cast_off_leave_block, :cast_off_continue_loop,
      :cast_off_break_block,
    ]

    BranchInstruction = [
      :branchunless, :jump, :branchif, :cast_off_handle_optional_args,
      :cast_off_enter_block, :cast_off_leave_block, :cast_off_continue_loop,
      :cast_off_break_block,
    ]

    JumpOrReturnInstruction = [
      :leave, :throw, :jump, :cast_off_handle_optional_args,
      :cast_off_enter_block, :cast_off_leave_block, 
      :cast_off_break_block,
    ]

    TypeInfoUser = [
      :send, :opt_plus, :opt_minus, :opt_mult, :opt_div, :opt_mod, :opt_lt, :opt_le, :opt_gt, :opt_ge, :opt_neq, :opt_eq, :opt_ltlt, :opt_aref,
      :opt_length, :opt_size, :opt_not, :opt_succ,
      :putstring, :newarray, :newhash, :duparray, :tostring, :toregexp, :concatstrings, :concatarray, :newrange, :opt_regexpmatch1, :opt_regexpmatch2,
      :expandarray, :splatarray, :checkincludearray, :getconstant, :getspecial, 
      :branchif, :branchunless, 
      :cast_off_prep, :cast_off_loop, :cast_off_finl, :cast_off_fetch_args, :cast_off_handle_optional_args
      #:opt_case_dispatch,
    ]

    unless (BlockSeparator - SupportInstruction).empty?
      bug()
    end

    unless (IgnoreInstruction - SupportInstruction).empty?
      bug()
    end

    unless (BranchInstruction - SupportInstruction).empty?
      bug()
    end

    unless (JumpOrReturnInstruction - SupportInstruction).empty?
      bug()
    end

    unless (TypeInfoUser - SupportInstruction).empty?
      bug()
    end

    class InsnInfo
      include CastOff::Util
      attr_reader :op, :argv, :pc, :iseq, :depth, :guard_label, :line, :ic_class

      # pc > 0  : standard instruction
      # pc == -1: cast_off instruction
      # safe = true : should not be generate guard
      # safe = false: should be generate guard
      def initialize(insn, iseq, pc = -1, line = -1, safe = false, depth = nil)
        @op, *@argv = *insn
        bug() unless iseq.is_a?(Iseq)
        @iseq = iseq
        @pc = pc
        @ic_class = class_information_in_ic(@iseq.iseq)
        @line = line
        @safe = safe
        if pc == -1 && !safe
          bug(op) if TypeInfoUser.include?(op)
        end
        @depth = depth
        @guard_label = "guard_#{self.hash.to_s.gsub(/-/, "_")}"
      end

      def size
        @argv.size + 1
      end

      def set_stack_depth(depth)
        @depth = depth
      end

      def need_guard?
        @safe ? false : true
      end

      def to_s
        "line[#{@line}]: #{source()}"
      end

      def source()
        bug() unless @iseq
        src = @iseq.source
        if @line > 0 && src
          src = src[@line - 1]
          src ? src.sub(/^[\s]+/, '').chomp : ''
        else
          ''
        end
      end

      def dup()
        ret = InsnInfo.new(insn(), @iseq, @pc, @line, @safe)
        ret.set_stack_depth(@depth)
        ret
      end

      def update(n_insn)
        n_op, *n_argv = *n_insn
        case @op
        when :getdynamic, :getlocal
          bug() unless n_op == :cast_off_getlvar || n_op == :cast_off_getdvar
        when :setdynamic, :setlocal
          bug() unless n_op == :cast_off_setlvar || n_op == :cast_off_setdvar
        when :getinstancevariable
          bug() unless n_op == :cast_off_getivar
        when :setinstancevariable
          bug() unless n_op == :cast_off_setivar
        when :getclassvariable
          bug() unless n_op == :cast_off_getcvar
        when :setclassvariable
          bug() unless n_op == :cast_off_setcvar
        when :getglobal
          bug() unless n_op == :cast_off_getgvar
        when :setglobal
          bug() unless n_op == :cast_off_setgvar
        else
          bug()
        end
        @op = n_op
        @argv = n_argv
      end

      def get_unsupport_message()
        case @op
        when :defineclass
          "Currently, CastOff cannot handle class definition"
        when :putspecialobject, :putiseq
          "Currently, CastOff cannot handle #{@op} instruction which is used for method definition"
        when :invokesuper
          "Currently, CastOff cannot handle super"
        else
          "Currently, CastOff cannot handle #{@op} instruction"
        end
      end

      def support?
        if SupportInstruction.index(@op)
          case @op
          when :throw
            support_throw_instruction?
          else
            true
          end
        else
          false
        end
      end

      def ignore?
        IgnoreInstruction.index(@op)
      end

      def get_iseq()
        index = get_iseq_index()
        index ? @argv[index] : nil
      end

      def set_iseq(iseq)
        index = get_iseq_index()
        bug() unless index
        @argv[index] = iseq
      end

      def get_label()
        index = get_label_index()
        index ? @argv[index] : nil
      end

      def set_label(label)
        index = get_label_index()
        bug() unless index
        @argv[index] = label
      end

      def popnum()
        case @op
        when :leave, :throw
          return 1
        when :dup
          return 1
        when :dupn
          n = @argv[0]
          return n
        when :setn
          n = @argv[0]
          return n + 1
        when :topn
          n = @argv[0]
          return n + 1
        end
        begin
          return instruction_popnum(insn())
        rescue ArgumentError => e
          case @op
          when :cast_off_prep
            return @argv.last.popnum()
          when :cast_off_loop
            return 0 # push true(continue loop) or false(not continue loop)
          when :cast_off_cont
            return 0
          when :cast_off_finl
            return 0
          when :cast_off_getlvar
            return 0
          when :cast_off_setlvar
            return 1
          when :cast_off_getivar
            return 0
          when :cast_off_setivar
            return 1
          when :cast_off_getcvar
            return 0
          when :cast_off_setcvar
            return 1
          when :cast_off_getgvar
            return 0
          when :cast_off_setgvar
            return 1
          when :cast_off_getdvar
            return 0
          when :cast_off_setdvar
            return 1
          when :cast_off_handle_optional_args
            return 1
          when :cast_off_fetch_args
            return 0
          when :cast_off_decl_arg, :cast_off_decl_var
            return 0
          when :cast_off_getconst
            return 0
          when :cast_off_enter_block, :cast_off_leave_block
            return 0
          when :cast_off_break_block
            return 1
          when :cast_off_continue_loop
            return 1
          else
            bug("unsupported instruction #{@op}, #{@argv}")
          end
        end
      end

      def pushnum()
        case @op
        when :leave, :throw
          return 0
        when :dup
          return 2
        when :dupn
          n = @argv[0]
          return n * 2
        when :setn
          n = @argv[0]
          return n + 1
        when :topn
          n = @argv[0]
          return n + 2
        end
        begin
          return instruction_pushnum(insn())
        rescue ArgumentError => e
          case @op
          when :cast_off_prep
            return @argv.last.pushnum()
          when :cast_off_loop
            return 0 # push true(continue loop) or false(not continue loop)
          when :cast_off_cont
            return 0
          when :cast_off_finl
            return 1
          when :cast_off_getlvar
            return 1
          when :cast_off_setlvar
            return 0
          when :cast_off_getivar
            return 1
          when :cast_off_setivar
            return 0
          when :cast_off_getcvar
            return 1
          when :cast_off_setcvar
            return 0
          when :cast_off_getgvar
            return 1
          when :cast_off_setgvar
            return 0
          when :cast_off_getdvar
            return 1
          when :cast_off_setdvar
            return 0
          when :cast_off_handle_optional_args
            return 0
          when :cast_off_fetch_args
            return 1
          when :cast_off_decl_arg, :cast_off_decl_var
            return 0
          when :cast_off_getconst
            return 1
          when :cast_off_enter_block, :cast_off_leave_block
            return 0
          when :cast_off_break_block
            return 1
          when :cast_off_continue_loop
            return 0
          else
            bug("unsupported instruction #{@op}, #{@argv}")
          end
        end
      end

      def stack_usage()
        pushnum() - popnum()
      end

      def get_throw_info()
        bug() unless @op == :throw
        # 1.9.2 and 1.9.3 compatible
        throw_state = @argv[0]
        state = throw_state & 0xff;
        flag = throw_state & 0x8000;
        level = throw_state >> 16;
        case state
        when THROW_TAG_RETURN
          type = :return
        when THROW_TAG_BREAK
          type = :break
        when THROW_TAG_NEXT
          type = :next
        when THROW_TAG_RETRY
          type = :retry
        when THROW_TAG_REDO
          type = :redo
        when THROW_TAG_RAISE
          type = :raise
        when THROW_TAG_THROW
          type = :throw
        when THROW_TAG_FATAL
          type = :fatal
        else
          bug()
        end
        [type, state, flag, level]
      end

      private

      def insn()
        [@op] + @argv
      end

      def get_label_index()
        case @op
        when :jump, :branchif, :branchunless
          0
        when :getinlinecacge
          0
        when :onceinlinecache, :opt_case_dispatch
          bug()
        else
          nil
        end
      end

      def get_iseq_index()
        case @op
        when :send
          2
        when :invokesuper, :defineclass
          1
        when :putiseq
          0
        else
          nil
        end
      end

      def support_throw_instruction?
        type, state, flag, level = get_throw_info()
        return false unless flag == 0
        case type
        when :return, :break
          true
        else
          false
        end
      end
    end
  end
end

