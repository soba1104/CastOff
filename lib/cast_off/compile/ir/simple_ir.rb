# coding=utf-8

module CastOff
  module Compiler
  module SimpleIR
    # 3 address code

    include Instruction

    class Stack
      include CastOff::Util

      attr_reader :depth

      def initialize(depth)
        @depth = depth
      end

      def pop()
        @depth -= 1
        bug() if @depth < 0
        @depth
      end

      def push()
        ret = @depth
        @depth += 1
        ret
      end
    end

    def block_argument_is_unsupported(translator, insn)
      raise UnsupportedError.new(<<-EOS)

Currently, CastOff doesn't support method and block invocation with a block argument.
------------------------------------------------------------------------------
Target file is (#{translator.target_name()}).
Call site is (#{insn}).
      EOS
    end

    def generate_ir(cfg, insns, depth)
      irs = []
      translator = cfg.translator
      stack = Stack.new(depth)
      insns.each do |insn|
        bug() unless stack.depth == insn.depth
        op = insn.op
        argv = insn.argv
        case op
        when :send,
             :opt_plus, :opt_minus, :opt_mult, :opt_div, :opt_mod, :opt_lt, :opt_le, :opt_gt, :opt_ge, :opt_neq, :opt_eq, :opt_ltlt, :opt_aref,
             :opt_length, :opt_size, :opt_not, :opt_succ
          fcall = false
          flags = 0
          case op
          when :send
            id = argv[0]
            argc = argv[1]
            blockiseq = argv[2]
            bug() if blockiseq # should be convert to cast_off_prep, ...
            flags = argv[3]
            fcall = (flags & VM_CALL_FCALL_BIT) != 0
            bug() if flags & VM_CALL_OPT_SEND_BIT != 0 # VM_CALL_OPT_SEND_BIT is set at the vm_call_method
            bug() if flags & VM_CALL_SUPER_BIT != 0 # VM_CALL_SUPER_BIT is set at the invokesuper
            #VM_CALL_VCALL_BIT: variable or call, 要検討
          when :opt_plus
            id = "+".intern
            argc = 1
          when :opt_minus
            id = "-".intern
            argc = 1
          when :opt_mult
            id = "*".intern
            argc = 1
          when :opt_div
            id = "/".intern
            argc = 1
          when :opt_mod
            id = "%".intern
            argc = 1
          when :opt_lt
            id = "<".intern
            argc = 1
          when :opt_le
            id = "<=".intern
            argc = 1
          when :opt_gt
            id = ">".intern
            argc = 1
          when :opt_ge
            id = ">=".intern
            argc = 1
          when :opt_neq
            id = "!=".intern
            argc = 1
          when :opt_eq
            id = "==".intern
            argc = 1
          when :opt_ltlt
            id = "<<".intern
            argc = 1
          when :opt_aref
            id = "[]".intern
            argc = 1
          when :opt_length
            id = :length
            argc = 0
          when :opt_size
            id = :size
            argc = 0
          when :opt_not
            id = "!".intern
            argc = 0
          when :opt_succ
            id = :succ
            argc = 0
          else
            bug()
          end

          if (flags & VM_CALL_ARGS_BLOCKARG_BIT) != 0
            blockarg = TmpVariable.new(stack.pop())
          else
            blockarg = nil
          end

          args = []
          argc.times { args << TmpVariable.new(stack.pop()) }

          if fcall
            stack.pop();
            irs << SubIR.new(Self.new(translator, insn.iseq), TmpVariable.new(stack.push()), InsnInfo.new([:putself], insn.iseq, -1, -1, true), cfg)
          end
          recv = TmpVariable.new(stack.pop())
          recv.is_also(insn.ic_class) if insn.ic_class
          param = []
          param << ParamIR.new(recv, insn, cfg)
          param += args.reverse.map{|arg| ParamIR.new(arg, insn, cfg)}
          if blockarg
            param << ParamIR.new(blockarg, insn, cfg)
            argc += 1
          end

          irs += param
          irs << InvokeIR.new(id, flags, param, argc + 1, TmpVariable.new(stack.push()), insn, cfg)
        when :invokeblock
          num = argv[0]
          flags = argv[1]

          block_argument_is_unsupported(translator, insn) if flags & VM_CALL_ARGS_BLOCKARG_BIT != 0

          args = []
          num.times { args << TmpVariable.new(stack.pop()) }
          param = []
          param += args.reverse.map{|arg| ParamIR.new(arg, insn, cfg)}

          irs += param
          irs << YieldIR.new(flags, param, num, TmpVariable.new(stack.push()), insn, cfg)
        when :putnil
          irs << SubIR.new(Literal.new(nil, translator), TmpVariable.new(stack.push()), insn, cfg)
        when :putself
          irs << SubIR.new(Self.new(translator, insn.iseq), TmpVariable.new(stack.push()), insn, cfg)
        when :putstring
          obj = argv[0]
          param = []
          param << ParamIR.new(Literal.new(obj, translator), insn, cfg)
          irs += param
          irs << Putstring.new(param, 1, TmpVariable.new(stack.push()), insn, cfg)
        when :putobject
          obj = argv[0]
          irs << SubIR.new(Literal.new(obj, translator), TmpVariable.new(stack.push()), insn, cfg)
        when :newarray
          argc = argv[0]
          args = []
          argc.times { args << TmpVariable.new(stack.pop()) }
          param = args.reverse.map{|arg| ParamIR.new(arg, insn, cfg)}
          irs += param
          irs << Newarray.new(param, argc, TmpVariable.new(stack.push()), insn, cfg)
        when :newhash
          argc = argv[0]
          args = []
          argc.times { args << TmpVariable.new(stack.pop()) }
          param = args.reverse.map{|arg| ParamIR.new(arg, insn, cfg)}
          irs += param
          irs << Newhash.new(param, argc, TmpVariable.new(stack.push()), insn, cfg)
        when :duparray
          obj = argv[0]
          param = []
          param << ParamIR.new(Literal.new(obj, translator), insn, cfg)
          irs += param
          irs << Duparray.new(param, 1, TmpVariable.new(stack.push()), insn, cfg)
        when :tostring
          param = []
          param << ParamIR.new(TmpVariable.new(stack.pop()), insn, cfg)
          irs += param
          irs << Tostring.new(param, 1, TmpVariable.new(stack.push()), insn, cfg)
        when :toregexp
          cnt = argv[1]
          args = []
          cnt.times { args << TmpVariable.new(stack.pop()) }
          param = args.reverse.map{|arg| ParamIR.new(arg, insn, cfg)}
          irs += param
          irs << Toregexp.new(param, cnt, TmpVariable.new(stack.push()), insn, cfg)
        when :concatstrings
          argc = argv[0]
          args = []
          argc.times { args << TmpVariable.new(stack.pop()) }
          param = args.reverse.map{|arg| ParamIR.new(arg, insn, cfg)}
          irs += param
          irs << Concatstrings.new(param, argc, TmpVariable.new(stack.push()), insn, cfg)
        when :concatarray
          argc = 2
          args = []
          argc.times { args << TmpVariable.new(stack.pop()) }
          param = args.reverse.map{|arg| ParamIR.new(arg, insn, cfg)}
          irs += param
          irs << Concatarray.new(param, argc, TmpVariable.new(stack.push()), insn, cfg)
        when :newrange
          flag = argv[0]
          argc = 2
          args = []
          argc.times { args << TmpVariable.new(stack.pop()) }
          param = args.reverse.map{|arg| ParamIR.new(arg, insn, cfg)}
          irs += param
          irs << Newrange.new(param, argc, TmpVariable.new(stack.push()), insn, cfg)
        when :opt_regexpmatch1
          r = argv[0]
          argc = 2
          param = []
          param << ParamIR.new(Literal.new(r, translator), insn, cfg)
          param << ParamIR.new(TmpVariable.new(stack.pop()), insn, cfg)
          irs += param
          irs << OptRegexpmatch1.new(param, argc, TmpVariable.new(stack.push()), insn, cfg)
        when :opt_regexpmatch2
          argc = 2
          param = []
          param << ParamIR.new(TmpVariable.new(stack.pop()), insn, cfg)
          param << ParamIR.new(TmpVariable.new(stack.pop()), insn, cfg)
          irs += param
          irs << OptRegexpmatch2.new(param, argc, TmpVariable.new(stack.push()), insn, cfg)
        when :expandarray
          num, flag = *argv
          is_splat = (flag & 0x01) != 0

          op = :expandarray_pre
          # param が Array かどうかという情報は使用しないので、ガードは不要
          expandarray_pre_insn = InsnInfo.new([op], insn.iseq, -1, -1, true)
          param = []
          param << ParamIR.new(TmpVariable.new(stack.pop()), expandarray_pre_insn, cfg)
          irs += param
          irs << ExpandarrayPre.new(param, 1, TmpVariable.new(stack.push()), expandarray_pre_insn, cfg)

          depth = stack.pop()
          if is_splat
            ary_depth = depth + num + 1
          else
            ary_depth = depth + num
          end
          irs << SubIR.new(TmpVariable.new(depth), TmpVariable.new(ary_depth), expandarray_pre_insn, cfg)

          if flag & 0x02 != 0
            # post: ..., nil ,ary[-1], ..., ary[0..-num] # top
            op = :expandarray_post_loop
            num.times do |i|
              # param は Array だと分かっているので、ガードは不要
              expandarray_post_loop_insn = InsnInfo.new([op, num, i], insn.iseq, -1, -1, true)
              param = []
              param << ParamIR.new(TmpVariable.new(ary_depth), expandarray_post_loop_insn, cfg)
              irs += param
              irs << ExpandarrayPostLoop.new(param, 1, TmpVariable.new(stack.push()), expandarray_post_loop_insn, cfg)
            end
            op = :expandarray_post_splat
            if is_splat
              # param は Array だと分かっているので、ガードは不要
              expandarray_post_splat_insn = InsnInfo.new([op, num], insn.iseq, -1, -1, true)
              param = []
              param << ParamIR.new(TmpVariable.new(ary_depth), expandarray_post_splat_insn, cfg)
              irs += param
              irs << ExpandarrayPostSplat.new(param, 1, TmpVariable.new(stack.push()), expandarray_post_splat_insn, cfg)
            end
          else
            # normal: ary[num..-1], ary[num-2], ary[num-3], ..., ary[0] # top
            op = :expandarray_splat
            if is_splat
              # param は Array だと分かっているので、ガードは不要
              expandarray_splat_insn = InsnInfo.new([op, num], insn.iseq, -1, -1, true)
              param = []
              param << ParamIR.new(TmpVariable.new(ary_depth), expandarray_splat_insn, cfg)
              irs += param
              irs << ExpandarraySplat.new(param, 1, TmpVariable.new(stack.push()), expandarray_splat_insn, cfg)
            end
            op = :expandarray_loop
            num.times do |i|
              # param は Array だと分かっているので、ガードは不要
              expandarray_loop_insn = InsnInfo.new([op, num - i - 1], insn.iseq, -1, -1, true)
              param = []
              param << ParamIR.new(TmpVariable.new(ary_depth), expandarray_loop_insn, cfg)
              irs += param
              irs << ExpandarrayLoop.new(param, 1, TmpVariable.new(stack.push()), expandarray_loop_insn, cfg)
            end
          end
        when :splatarray
          param = []
          param << ParamIR.new(TmpVariable.new(stack.pop()), insn, cfg)
          irs += param
          irs << Splatarray.new(param, 1, TmpVariable.new(stack.push()), insn, cfg)
        when :checkincludearray
          flag = argv[0]
          op = :checkincludearray_pre
          # param が Array かどうかという情報は使用しないので、ガードは不要
          checkincludearray_pre_insn = InsnInfo.new([op], insn.iseq, -1, -1, true)
          param = []
          param << ParamIR.new(TmpVariable.new(stack.pop()), checkincludearray_pre_insn, cfg) # ary
          irs += param
          irs << CheckincludearrayPre.new(param, 1, TmpVariable.new(stack.push()), checkincludearray_pre_insn, cfg)

          if flag == true
            op = :checkincludearray_case
            # ary は Array だと分かっているので、ガードは不要
            # obj の型情報は使用しないので、ガードは不要
            checkincludearray_case_insn = InsnInfo.new([op], insn.iseq, -1, -1, true)
            param = []
            param << ParamIR.new(TmpVariable.new(stack.pop()), checkincludearray_case_insn, cfg) # ary
            param << ParamIR.new(TmpVariable.new(stack.pop()), checkincludearray_case_insn, cfg) # obj
            stack.push() # obj
            irs += param
            irs << CheckincludearrayCase.new(param, 2, TmpVariable.new(stack.push()), checkincludearray_case_insn, cfg) #result
          elsif flag == false
            op = :checkincludearray_when
            # ary は Array だと分かっているので、ガードは不要
            checkincludearray_when_insn = InsnInfo.new([op], insn.iseq, -1, -1, true)
            param = []
            param << ParamIR.new(TmpVariable.new(stack.pop()), checkincludearray_when_insn, cfg) # ary
            stack.pop() # obj
            result_depth = stack.push() # result
            irs += param
            irs << CheckincludearrayWhen.new(param, 1, TmpVariable.new(result_depth), checkincludearray_when_insn, cfg)
            irs << SubIR.new(TmpVariable.new(result_depth), TmpVariable.new(stack.push()), checkincludearray_when_insn, cfg)
          else
            bug()
          end
        when :cast_off_decl_arg
          if translator.inline_block?
            irs << SubIR.new(Argument.new(*argv), LocalVariable.new(*argv), insn, cfg)
          else
            irs << SubIR.new(Argument.new(*argv), DynamicVariable.new(*argv), insn, cfg)
          end
        when :cast_off_decl_var
          if translator.inline_block?
            irs << SubIR.new(Literal.new(nil, translator), LocalVariable.new(*argv), insn, cfg)
          else
            ir = SubIR.new(Literal.new(nil, translator), DynamicVariable.new(*argv), insn, cfg)
            ir.vanish()
            irs << ir
          end
        when :cast_off_getconst
          irs << SubIR.new(ConstWrapper.new(*argv, translator), TmpVariable.new(stack.push()), insn, cfg)
        when :cast_off_getgvar
          irs << SubIR.new(GlobalVariable.new(*argv, translator), TmpVariable.new(stack.push()), insn, cfg)
        when :cast_off_getcvar
          irs << SubIR.new(ClassVariable.new(*argv), TmpVariable.new(stack.push()), insn, cfg)
        when :cast_off_getivar
          irs << SubIR.new(InstanceVariable.new(*argv), TmpVariable.new(stack.push()), insn, cfg)
        when :cast_off_getlvar
          irs << SubIR.new(LocalVariable.new(*argv), TmpVariable.new(stack.push()), insn, cfg)
        when :cast_off_getdvar
          irs << SubIR.new(DynamicVariable.new(*argv), TmpVariable.new(stack.push()), insn, cfg)
        when :getdynamic, :setdynamic
          bug()
        when :cast_off_setgvar
          irs << SubIR.new(TmpVariable.new(stack.pop()), GlobalVariable.new(*argv, translator), insn, cfg)
        when :cast_off_setcvar
          irs << SubIR.new(TmpVariable.new(stack.pop()), ClassVariable.new(*argv), insn, cfg)
        when :cast_off_setivar
          irs << SubIR.new(TmpVariable.new(stack.pop()), InstanceVariable.new(*argv), insn, cfg)
        when :cast_off_setlvar
          irs << SubIR.new(TmpVariable.new(stack.pop()), LocalVariable.new(*argv), insn, cfg)
        when :cast_off_setdvar
          irs << SubIR.new(TmpVariable.new(stack.pop()), DynamicVariable.new(*argv), insn, cfg)
        when :getspecial
          param = []
          irs << Getspecial.new(param, 0, TmpVariable.new(stack.push()), insn, cfg)
        when :jump, :cast_off_enter_block, :cast_off_leave_block
          bug("op = #{op}, depth = #{stack.depth}") if op == :cast_off_leave_block && (stack.depth - 1) != insn.iseq.depth
          irs << JumpIR.new(nil, insn, cfg)
        when :cast_off_break_block
          bug("op = #{op}, depth = #{stack.depth}") if (stack.depth - 1) != insn.iseq.depth
          d = stack.pop()
          stack.push()
          irs << SubIR.new(TmpVariable.new(d), TmpVariable.new(stack.push()), insn, cfg)
          irs << JumpIR.new(TmpVariable.new(stack.pop()), insn, cfg)
        when :branchunless, :branchif, :cast_off_continue_loop
          target = argv[0]
          irs << JumpIR.new(TmpVariable.new(stack.pop()), insn, cfg)
        when :pop
          stack.pop()
        when :adjuststack
          # same as popn instruction
          num = argv[0]
          num.times { stack.pop() }
        when :setn
          # deep <-----------------------
          # e.g. num = 3, [:a, :b, :c, :d] => [:d, :b, :c, :d]
          num = argv[0]
          dst = stack.pop() - num
          src = stack.push()
          irs << SubIR.new(TmpVariable.new(src), TmpVariable.new(dst), insn, cfg)
        when :dupn
          # deep <-----------------------
          # e.g. [:a, :b, :c] => [:a, :b, :c, :a, :b, :c]
          num = argv[0]
          num.times do
            depth = stack.push()
            irs << SubIR.new(TmpVariable.new(depth - num), TmpVariable.new(depth), insn, cfg)
          end
        when :dup
          depth = stack.push()
          irs << SubIR.new(TmpVariable.new(depth - 1), TmpVariable.new(depth), insn, cfg)
        when :swap
          tmp = stack.push()
          stack.pop()
          v0 = tmp - 1
          v1 = tmp - 2
          irs << SubIR.new(TmpVariable.new(v0), TmpVariable.new(tmp), insn, cfg)
          irs << SubIR.new(TmpVariable.new(v1), TmpVariable.new(v0), insn, cfg)
          irs << SubIR.new(TmpVariable.new(tmp), TmpVariable.new(v1), insn, cfg)
        when :topn
          n = argv[0]
          dst = stack.push()
          irs << SubIR.new(TmpVariable.new(dst - n - 1), TmpVariable.new(dst), insn, cfg)
        when :throw
          type, state, flag, level = insn.get_throw_info()
          if flag != 0
            bug()
          else
            case type
            when :return
              irs << ReturnIR.new(TmpVariable.new(stack.pop()), ReturnIR::ThrowObj.new(type, argv[0], state, flag, level), insn, cfg)
            else
              bug()
            end
          end
        when :cast_off_prep
          # stack には argc + 1 積まれている
          depth = argv[0]
          loop_args = argv[1]
          send_insn = argv[2]
          send_argv = send_insn.argv
          send_id = send_argv[0]
          send_argc = send_argv[1]
          send_flags = send_argv[3]
          fcall = (send_flags & VM_CALL_FCALL_BIT) != 0
          bug() if send_flags & VM_CALL_OPT_SEND_BIT != 0 # VM_CALL_OPT_SEND_BIT is set at the vm_call_method
          bug() if send_flags & VM_CALL_SUPER_BIT != 0 # VM_CALL_SUPER_BIT is set at the invokesuper
          block_argument_is_unsupported(translator, insn) if send_flags & VM_CALL_ARGS_BLOCKARG_BIT != 0
          #VM_CALL_VCALL_BIT: variable or call, 要検討
          raise UnsupportedError.new(<<-EOS) if send_flags & VM_CALL_ARGS_SPLAT_BIT != 0

Currently, CastOff doesn't support a method invocation which takes a splat argument (like *arg) and which takes a block.
------------------------------------------------------------------------------------------------------------------------
Target file is (#{translator.target_name()}).
Call site is (#{insn}).
          EOS

          send_args = []
          send_argc.times { send_args << TmpVariable.new(stack.pop()) }

          if fcall
            stack.pop();
            irs << SubIR.new(Self.new(translator, insn.iseq), TmpVariable.new(stack.push()), InsnInfo.new([:putself], insn.iseq, -1, -1, true), cfg)
          end
          recv = TmpVariable.new(stack.pop())
          param = []
          param << ParamIR.new(recv, insn, cfg)
          param += send_args.reverse.map{|arg| ParamIR.new(arg, insn, cfg)}

          # loop のための key object を返す, reciever オブジェクト + context (map の場合は返り値の配列 + 帰納変数)
          # rb_ary_each_context_t みたいなのを作る
          # block = true だった場合、recv と id から関数名を特定して、それ用の関数を呼ぶ。返り値は loopkey
          # loopkey は cast_off_ary_each_context_t みたいな構造体
          loopkey = LoopKey.new(send_id, depth, loop_args, insn, cfg.translator)
          translator.loopkey[depth] = loopkey
          irs += param
          irs << LoopIR.new(loopkey, op, param, send_argc + 1, TmpVariable.new(stack.push()), insn, cfg)
        when :cast_off_loop
          depth = argv[0]
          send_insn = argv[2]
          send_argv = send_insn.argv
          send_id = send_argv[0]

          # loopkey を引数で渡す。返り値は true(ループ継続) or false(ループ終了)
          loopkey = translator.loopkey[depth]
          bug() unless loopkey
          param = []
          param << ParamIR.new(TmpVariable.new(stack.pop()), insn, cfg)
          irs += param
          irs << LoopIR.new(loopkey, op, param, 1, TmpVariable.new(stack.push()), insn, cfg)
        when :cast_off_cont
          depth = argv[0]
          args = argv[1]
          if translator.inline_block?
            args.each_with_index{|arg, i| irs << SubIR.new(TmpBuffer.new(i), LocalVariable.new(*arg), insn, cfg)}
          else
            args.each_with_index{|arg, i| irs << SubIR.new(TmpBuffer.new(i), DynamicVariable.new(*arg), insn, cfg)}
          end
          loopkey = translator.loopkey[depth]
          loopkey.block_iseq = insn.iseq
          insn.iseq.set_loopkey(loopkey)
          insn.iseq.use_temporary_c_ary(args.size())
        when :cast_off_finl
          depth = argv[0]
          send_insn = argv[2]
          send_argv = send_insn.argv
          send_id = send_argv[0]
          loopkey = translator.loopkey[depth]
          bug() unless loopkey
          param = []
          irs << LoopIR.new(loopkey, op, param, 0, TmpVariable.new(stack.push()), insn, cfg)
        when :cast_off_fetch_args
          param = []
          if argv[0]
            args = argv[0].last
            if translator.inline_block?
              args.map!{|arg| LocalVariable.new(*arg).to_name() }
            else
              args.map!{|arg| DynamicVariable.new(*arg).to_name() }
            end
          end
          irs << CastOffFetchArgs.new(param, 0, TmpVariable.new(stack.push()), insn, cfg)
        when :cast_off_handle_optional_args
          irs << JumpIR.new(TmpVariable.new(stack.pop()), insn, cfg)
        when :leave
          depth = stack.pop()
          unless depth == 0
            if translator.inline_block?
              # throw => leave
            else
              bug()
            end
          end
          irs << ReturnIR.new(TmpVariable.new(depth), nil, insn, cfg)
        when :defined
          t = argv[0]
          case t
          when DEFINED_IVAR, DEFINED_GVAR, DEFINED_FUNC, DEFINED_CONST
            # ok
          when DEFINED_IVAR2
            bug("unexpected defined instruction")
          when DEFINED_CVAR
            raise(UnsupportedError.new("Currently, CastOff cannot handle defined instruction for class variable"))
          when DEFINED_METHOD
            raise(UnsupportedError.new("Currently, CastOff cannot handle defined instruction for methods"))
          when DEFINED_YIELD
            raise(UnsupportedError.new("Currently, CastOff cannot handle defined instruction for yield"))
          when DEFINED_REF
            raise(UnsupportedError.new("Currently, CastOff cannot handle defined instruction for global-variable"))
          when DEFINED_ZSUPER
            raise(UnsupportedError.new("Currently, CastOff cannot handle defined instruction for super"))
          else
            bug()
          end

          param = []
          param << ParamIR.new(TmpVariable.new(stack.pop()), insn, cfg)
          irs += param
          irs << Defined.new(param, 1, TmpVariable.new(stack.push()), insn, cfg)
        else
          raise(UnsupportedError, "unsupported RubyVM instruction #{insn} ")
        end
        unless stack.depth == insn.depth + insn.stack_usage()
          bug("stack.depth = #{stack.depth}, insn.depth = #{insn.depth + insn.stack_usage()}, insn = #{insn}\n#{irs.join("\n")}\n")
        end
      end
      irs
    end

    class IR
      include CastOff::Util

      attr_reader :insn, :alias

      def initialize(insn, cfg)
        @insn = insn
        @cfg = cfg
        @translator = cfg.translator
        @configuration = @translator.configuration
        @dependency    = @translator.dependency
        @information = nil
        @alias = nil
        @alive = false
        @valish_p = false
        @sampling_variable = []
      end

      def vanish()
        @vanish_p = true
      end

      def vanish?
        @vanish_p
      end

      ### unboxing begin ###
      def unboxing_prelude()
        bug()
      end

      def propergate_value_which_can_not_unbox(defs)
        bug()
      end

      def propergate_unbox_value(defs)
        bug()
      end
      ### unboxing end ###

      def sampling_variable()
        s = []
        if @configuration.development?
          @sampling_variable.each do |var|
            next if var.is_a?(Literal)
            s << "  sampling_variable(#{var}, ID2SYM(rb_intern(#{var.source.inspect})));"
          end
        end
        s.empty? ? nil : s.join("\n")
      end

      def add_sampling_variable(var)
        @sampling_variable |= [var]
      end

      def alive()
        @alive ? false : (@alive = true)
      end

      def alive?
        @alive
      end

      def reset()
        @alive = false
        @variables.each{|v| v.reset()}
      end

      def standard_guard_target()
        nil
      end

      def propergate_guard_usage()
        # nothing to do
      end

      def generate_guard(vars)
        target = standard_guard_target()
        if target.is_a?(Variable) && !target.dynamic? && @insn.need_guard?
          # FIXME target <= should be dup
          StandardGuard.new(target, vars, @insn, @cfg)
        else
          nil
        end
      end

      def get_usage()
        blocks = []
        usage = {}
        irs = [self]
        change = true
        while change
          change = false
          @cfg.blocks.each do |b|
            foo = b.irs & irs
            bar = b.information.variable_definition & irs
            if foo.size > 0 || bar.size > 0
              vars = []
              bar.each do |ir|
                result_variable = ir.result_variable
                next unless result_variable
                vars << result_variable
              end
              b.irs.each do |ir|
                case ir
                when SubIR
                  src = ir.src
                  dst = ir.dst
                  if src != dst
                    if vars.include?(dst)
                      vars.reject! {|v| v == dst}
                      #vars -= [dst]
                    end
                    if vars.include?(src)
                      if dst.is_a?(Pointer)
                        usage[:escape] = ir
                        return usage
                      end
                      vars |= [dst]
                      if !irs.include?(ir)
                        irs << ir
                        change = true
                      end
                    end
                  end
                when JumpIR
                  # nothing to do
                when ParamIR
                  if vars.include?(ir.param_value) && !irs.include?(ir)
                    irs << ir
                    change = true
                  end
                when CallIR
                  argc = ir.argc
                  return_value = ir.return_value
                  param = ir.param_variables()
                  param.each do |p|
                    if vars.include?(p)
                      usage[[param[0], ir]] = vars.index(param[0])
                      break
                    end
                  end
                  if vars.include?(return_value)
                    vars.reject! {|v| v == return_value}
                    #vars -= [return_value]
                  end
                when ReturnIR
                  if vars.include?(ir.return_value)
                    usage[:escape] = ir
                    return usage
                  end
                end
                result_variable = ir.result_variable
                vars |= [result_variable] if foo.include?(ir) && result_variable
              end
            end
          end
        end
        usage
      end

      def set_info(d)
        @information = d
      end

      def get_definition(target)
        case target
        when Literal
          return [target]
        when Variable
          ds = @information.variable_definition_of(target)
          bug() if ds.empty?
          ary = []
          ds.each do |d|
            case d
            when SubIR
              src = d.src
              if src.is_a?(TmpVariable)
                ary += d.get_definition(src)
              else
                ary << d
              end
            when CallIR
              ary << d
            else
              bug()
            end
          end
          return ary
        else
          raise(UnsupportedError.new("Currently, CastOff cannot compile this method or block"))
        end
        bug()
      end

      def get_definition_str(target)
        ary = get_definition(target)
        ary.map {|d|
          case d
          when Literal
            d.source
          when SubIR
            d.src.source
          when LoopIR, VMInsnIR
            "vm internal value"
          when InvokeIR
            "result of #{d.to_verbose_string}"
          when YieldIR
            "result of yield"
          else
            bug()
          end
        }.join("\n")
      end

      def dispatch_method?
        # FIXME 型情報を活用（Fixnum#+ とかはインスタンス変数を触らないよね）
        return true if !@translator.inline_block? && self.is_a?(LoopIR)
        self.is_a?(InvokeIR) || self.is_a?(YieldIR)
      end

      def inlining_target?
        false
      end
    end
  end
end
end

