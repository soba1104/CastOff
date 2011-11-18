# coding=utf-8

module CastOff::Compiler
  class Translator::CFG
    class BasicBlock
      include CastOff::Util
      include CastOff::Compiler::Instruction
      include CastOff::Compiler::SimpleIR

      attr_reader :insns, :pre, :next, :labels, :number, :irs, :iseq

      def initialize(cfg, insns, number)
        @cfg = cfg
        @insns = insns
        bug() if @insns.find{|i| not i.instance_of?(InsnInfo)}
        @number = number
        @pre = nil
        @next = nil
        @labels = []
        @irs = nil
        @entry_point = number == 0
        @iseq = @insns[0].iseq
        bug() if @insns.find{|i| i.iseq != @iseq}
      end

      def source
        return '' unless @irs
        line = nil
        @irs.inject(''){|src, ir|
          insn = ir.insn
          next src if insn.line == line
          next src if insn.source.empty?
          line = insn.line
          src.concat(insn.source).concat("\n")
        }.chomp
      end

      def entry_point?
        @entry_point
      end

      def set_prev_block(blocks)
        @pre = []
        index = blocks.index(self)
        if index != 0
          pre = blocks[index - 1]
          case pre
          when Symbol
            # this block is branch or jump target
            @labels << pre
            i = index - 2
            while i >= 0
              break unless blocks[i].is_a?(Symbol)
              @labels << blocks[i]
              i -= 1
            end
            matchlabels = []
            blocks.each do |basicblock|
              case basicblock when BasicBlock
                last_insn = basicblock.insns.last
                op = last_insn.op
                argv = last_insn.argv
                if BranchInstruction.include?(op)
                  case op
                  when :jump, :branchunless, :branchif, \
                       :cast_off_enter_block, :cast_off_leave_block, :cast_off_continue_loop, \
                       :cast_off_break_block
                    targets = [argv[0]]
                  when :cast_off_handle_optional_args
                    targets = argv[0]
                  else
                    bug("unexpected instruction #{op}")
                  end
                  targets.each do |t|
                    if @labels.include?(t)
                      matchlabels << t
                      @pre << basicblock unless @pre.include?(basicblock)
                    end
                  end
                end
              end
            end
            if @pre.empty?
              # join point with exception handler
              # nothing to do
              @labels = []
            else
              @labels = @labels & matchlabels
              bug() if @labels.empty?
            end
            # consider fall-throuth from previous block
            i = index - 2
            while i >= 0
              pre = blocks[i]
              break if pre.is_a?(BasicBlock)
              i -= 1
            end
            if pre.is_a?(BasicBlock)
              last_insn = pre.insns.last
              @pre << pre if !JumpOrReturnInstruction.include?(last_insn.op)
            end
          when BasicBlock
            # fall-throuth from previous block
            last_insn = pre.insns.last
            if JumpOrReturnInstruction.include?(last_insn.op)
              # dead block
            else
              @pre << pre
            end
          else
            bug()
          end
        else
          # entry point
        end
      end

      def set_next_block(blocks)
        @next = []
        bug() if blocks.find{|b| b.instance_of?(BasicBlock) && !b.pre }
        blocks.each{|b| @next << b if b.instance_of?(BasicBlock) && b.pre.include?(self)}
      end

      def gen_ir()
        @irs = generate_ir(@cfg, @insns, in_depth())
      end

      def to_c()
        params = []
        codes = []
        @labels.each{|label| codes << "#{label}:" }
        @irs.each do |ir|
          bug() unless ir.insn.iseq == @iseq
          ir.variables.each{|v| @iseq.declare_local_variable("#{v.declare()} #{v}") if v.declare?}
          case ir
          when SubIR, JumpIR, ReturnIR, GuardIR
            codes << ir.to_c()
          when ParamIR
            params << ir.param_value
          when CallIR
            codes << ir.to_c(params)
          else
            bug("invalid ir #{ir}")
          end
        end
        bug() unless params.empty?
        codes.join("\n")
      end

      def to_s()
        pstr = "#{@pre.map{|b|  "BB#{b.number}"}.join(", ")}"
        nstr = "#{@next.map{|b| "BB#{b.number}"}.join(", ")}"
        "(#{pstr})BB#{@number}-#{@iseq}(#{nstr})"
      end
    end
  end
end

