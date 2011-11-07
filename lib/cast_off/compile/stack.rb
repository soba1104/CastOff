module CastOff::Compiler
  class Translator::CFG
    class BasicBlock

      def in_depth=(depth)
        @in_depth = depth
      end

      def in_depth()
        bug() unless @in_depth
        @in_depth
      end

      def out_depth()
        bug() unless @in_depth
        @in_depth + stackincrease()
      end

      def find_insn_stack_depth(insn)
        bug() unless @insns.include?(insn)
        depth = in_depth()
        @insns.each do |i|
          return depth if i == insn
          depth += i.stack_usage()
        end
        bug()
      end

      private

      def stackincrease()
        @insns.inject(0){|inc, i| inc + i.stack_usage()}
      end
    end

    def find_insn_stack_depth(insn)
      b = @blocks.find{|b| b.insns.include?(insn)}
      b ? b.find_insn_stack_depth(insn) : nil
    end

    private

    def validate_stack()
      # Breadth first search
      @blocks[0].in_depth = 0
      achieved = {}
      vertex = nil
      queue = [@blocks[0]]
      while achieved.size() != @blocks.size()
        vertex = queue.shift()
        bug() unless vertex
        achieved[vertex] = true
        depth = vertex.out_depth
        vertex.next.each do |b|
          if !queue.include?(b) && !achieved[b]
            b.in_depth = depth
            queue << b
          end
        end
      end
      @blocks.each{|b0| bug() if b0.next.find{|b1| b0.out_depth != b1.in_depth}}
    end
  end
end

