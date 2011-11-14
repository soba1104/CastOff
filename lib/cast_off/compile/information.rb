# coding=utf-8

module CastOff::Compiler
  class Translator::CFG
    class Information
      include CastOff::Util
      include SimpleIR

      attr_reader :variable_definition, :undefs, :block, :alias
      attr_reader :variable_condition

      def initialize(block, vars, a, defs, undefs, ptr_defs, ptrs)
        @block = block
        @alias = a.instance_of?(Alias) ? a : Alias.new(@block, a, vars, ptrs)
        @variable_definition = defs
        @ptr_defs = ptr_defs
        @undefs = undefs
        @ptrs = ptrs
        @vars = vars
        @variable_condition = VariableCondition.new(@block, @ptrs, @alias)
        check_initialize()
      end

      def freeze()
        super()
        check_initialize()
        @alias.freeze()
        @variable_definition.freeze()
        @ptr_defs.freeze()
        @undefs.freeze()
        @ptrs.freeze()
        @vars.freeze()
        @variable_condition.freeze()
      end

      def final_state()
        # variable_condition までは final_state にならないので注意
        check_initialize()
        final_alias = @alias.final_state()
        final_defs = (@variable_definition - @block.ekill) | @block.egen
        final_undefs = @undefs + @block.ekill.map{|ir| ir.result_variable} - @block.egen.map{|ir| ir.result_variable}
        Information.new(@block, @vars, final_alias, final_defs, final_undefs, @ptr_defs, @ptrs)
      end

      def find_same_variables(var)
        check_initialize()
        @alias.find_set(var)
      end

      def validate()
        check_initialize()
        @alias.validate()
        bug() unless @alias.final_state() == @block.information.alias.final_state()
        defs = @variable_definition.map{|d| d.result_variable}.compact()
        bug() unless (defs & @undefs).empty?
        bug() unless (@vars - (defs | @undefs)).empty?
      end

      def validate_final()
        check_initialize()
        @alias.validate()
        bug() unless @alias == @block.information.alias.final_state()
        defs = @variable_definition.map{|d| d.result_variable}.compact()
        bug() unless (defs & @undefs).empty?
        bug() unless (@vars - (defs | @undefs)).empty?
      end

      def step(ir)
        check_initialize()
        @alias.step(ir)
        @variable_condition.step(ir)
        delete(ir)
        add(ir)
      end

      def |(other)
        check_initialize()
        bug() unless other.instance_of?(Information)
        Information.new(@block, @vars, @alias.union(other.alias), @variable_definition | other.variable_definition, @undefs | other.undefs, @ptr_defs, @ptrs)
      end

      def kill_definition(other)
        @variable_definition.delete_if do |d0|
          next unless d0.result_variable
          not other.variable_definition.find{|d1| d0.result_variable == d1.result_variable}
        end
      end

      def eql?(other)
        check_initialize()
        bug() unless other.instance_of?(Information)
        bug() unless @block == other.block
        return false unless (@variable_definition - other.variable_definition).empty? && (other.variable_definition - @variable_definition).empty?
        return false unless (@undefs - other.undefs).empty? && (other.undefs - @undefs).empty?
        @alias == other.alias
      end

      def ==(other)
        check_initialize()
        eql?(other)
      end

      def size()
        check_initialize()
        @variable_definition.size()
      end

      def replace_entry(ir)
        check_initialize()
        i = @variable_definition.index(ir)
        @variable_definition[i] = ir if i
      end

      def reject!(&b)
        check_initialize()
        @variable_definition.reject!{|ir| yield ir}
      end

      def flatten!
        check_initialize()
        @variable_definition.flatten!
      end

      def hash()
        bug()
      end

      def dup()
        check_initialize()
        Information.new(@block, @vars, @alias.dup(), @variable_definition.dup(), @undefs.dup(), @ptr_defs, @ptrs)
      end

      def to_s()
        @variable_definition.join("\n")
      end

      def variable_definition_of(var)
        check_initialize()
        @variable_definition.select{|d| d.result_variable == var}
      end

      def undefined_variables()
        check_initialize()
        @undefs
      end

      def mark(var)
        check_initialize()
        ds = @variable_definition.select {|d| var == d.result_variable }
        ds.inject(false){|change, d| d.alive() || change}
      end

      def type_resolve(var)
        check_initialize()
        #return false if var.dynamic? || var.static?
        return false unless var.is_a?(Variable)
        ret = false

        bug() unless @variable_condition
        ret |= @variable_condition.use(var)
        ds = @variable_definition.select {|d| var == d.result_variable }
        if @undefs.include?(var) || ds.empty?
          case var
          when TmpBuffer
            ret |= var.is_dynamic()
          when Pointer, Argument
            ret |= var.is_dynamic()
          when Self
            bug() if var.undefined?
          else
            bug(var)
          end
        else
          ds.each { |d| ret = true if var.union(d.result_variable) }
        end
        ret
      end

      def exact_class_resolve(var)
        check_initialize()
        return false if !var.is_a?(Variable) || var.class_exact?

        ds = @variable_definition.select{|d| var == d.result_variable }
        if @undefs.include?(var) || ds.empty?
          case var
          when TmpBuffer, Pointer, Argument, Self
            return false
          else
            bug(var)
          end
        else
          ds.each do |d|
            r = d.result_variable
            return false unless r.class_exact?
          end
          var.is_class_exact()
          return true
        end
        bug()
      end

      ### unboxing begin ###
      def can_not_unbox_variable_resolve_forward(var)
        check_initialize()
        return false if var.can_not_unbox?
        ds = @variable_definition.select {|d| var == d.result_variable }
        if ds.empty?
          case var
          when TmpBuffer, Pointer, Argument, Self, ConstWrapper, Literal
            return false
          else
            bug(var)
          end
        end
        ds.each do |d|
          if d.result_variable.can_not_unbox?
            var.can_not_unbox()
            return true
          end
        end
        return false
      end

      def can_not_unbox_variable_resolve_backward(var)
        check_initialize()
        bug() unless var.can_not_unbox?
        ds = @variable_definition.select {|d| var == d.result_variable }
        if ds.empty?
          case var
          when TmpBuffer, Pointer, Argument, Self, ConstWrapper, Literal
            return false
          else
            bug(var)
          end
        end
        ds.inject(false){|change, d| d.result_variable.can_not_unbox() || change}
      end

      def box_value_resolve_forward(var)
        check_initialize()
        bug() if !var.unboxed? && !var.boxed?
        return false if var.boxed?
        ds = @variable_definition.select {|d| var == d.result_variable }
        if ds.empty?
          case var
          when TmpBuffer, Pointer, Argument, Self, ConstWrapper, Literal
            #bug(var)
            return false
          else
            bug(var)
          end
        end
        ds.each do |d|
          if d.result_variable.boxed?
            var.box()
            return true
          end
        end
        return false
      end

      def box_value_resolve_backward(var)
        check_initialize()
        bug() unless var.boxed?
        ds = @variable_definition.select {|d| var == d.result_variable }
        if ds.empty?
          case var
          when TmpBuffer, Pointer, Argument, Self, ConstWrapper, Literal
            return false
          else
            bug(var)
          end
        end
        ds.inject(false){|change, d| d.result_variable.box() || change}
      end

      def unbox_value_resolve(var)
        check_initialize()
        bug() if var.can_not_unbox?
        return false if var.unboxed?
        ds = @variable_definition.select {|d| var == d.result_variable }
        if ds.empty?
          case var
          when TmpBuffer, Pointer, Argument, Self, ConstWrapper, Literal
            return false
          else
            bug(var)
          end
        end
        c = nil
        ds.each do |d|
          v = d.result_variable
          return false unless v.unboxed?
          bug() if v.dynamic?
          bug() unless v.types.size == 1
          if c
            bug() unless c == v.types[0]
          else
            c = v.types[0]
          end
        end
        var.unbox()
        true
      end
      ### unboxing end ###

      private

      def check_initialize()
        bug() unless @block.instance_of?(BasicBlock)
        bug() unless @variable_definition.instance_of?(Array)
        bug() unless @ptr_defs.instance_of?(Array)
        bug() unless @undefs.instance_of?(Array)
        bug() unless @ptrs.instance_of?(Array)
        bug() unless @vars.instance_of?(Array)
        bug() unless @alias.instance_of?(Alias)
        bug() unless @variable_condition.instance_of?(VariableCondition)
      end

      def delete(ir)
        check_initialize()
        @variable_definition.reject!{|d| d.result_variable == ir.result_variable}
        if ir.dispatch_method?
          @variable_definition -= @ptr_defs 
          @undefs |= @ptrs
        end
      end

      def add(ir)
        check_initialize()
        @variable_definition << ir
        result_variable = ir.result_variable
        @undefs -= [result_variable] if result_variable
      end

      class Alias
        include CastOff::Compiler::SimpleIR
        include CastOff::Util
        attr_reader :set

        def initialize(b, a, all, ptrs)
          bug() unless b.instance_of?(BasicBlock)
          @block = b
          @all = all
          @ptrs = ptrs
          case a
          when NilClass
            a = all.dup()
            bug() if a.find{|v| not v.is_a?(Variable)}
            @set = [a]
          when Array
            bug() if a.find{|v| not v.is_a?(Variable)}
            @set = a.map{|v| [v]}
          when Alias
            @set = a.set.map{|s| s.dup()}
          else
            bug()
          end
          validate()
        end

        def freeze()
          super()
          @all.freeze()
          @set.freeze()
          @ptrs.freeze()
        end

        def final_state()
          a = dup()
          @block.irs.each{|ir| a.step(ir)}
          a
        end

        def step(ir)
          case ir
          when SubIR
            src = ir.src
            dst = ir.dst
            src.is_a?(Variable) ? sub(src, dst) : isolate(dst)
          when CallIR
            return_value = ir.return_value
            bug() unless return_value.is_a?(Variable)
            isolate(return_value)
            @ptrs.each{|p| isolate(p)} if ir.dispatch_method?
          end
        end

        def dup()
          Alias.new(@block, self, @all, @ptrs)
        end

        def find_set(var)
          bug() unless var.is_a?(Variable)
          set.each{|s| return s if s.include?(var)}
          bug("set = #{set}, var = #{var}, #{var.class}")
        end

        def validate()
          a = @set.inject([]) do |ary, s|
            bug() unless (ary & s).empty?
            ary + s
          end
          size = @all.size()
          bug() unless a.size() == size && (a & @all).size() == size
        end

        def eql?(other)
          other_set = other.set.dup()
          @set.each{|s| other_set.delete(s){return false}}
          bug() unless other_set.empty?
          return true
        end

        def ==(other)
          eql?(other)
        end

        def union(other)
          a = @all.dup()
          new_set = []
          until a.empty?
            var = a.pop()
            s0 = find_set(var)
            s1 = other.find_set(var)
            s = s0 & s1
            new_set << s
            a -= s
          end
          @set = new_set
          validate()
          dup()
        end

        private

        def sub(arg0, result)
          return if arg0 == result
          reject(result)
          s = find_set(arg0)
          bug() if s.include?(result)
          s << result
        end

        def isolate(var)
          reject(var)
          @set << [var]
        end

        def reject(var)
          s = find_set(var)
          s.delete(var){bug()}
          @set.delete(s){bug()} if s.empty?
        end
      end # Alias

      class VariableCondition
        include CastOff::Util
        include SimpleIR

        attr_reader :block, :condition

        def initialize(b, ptrs, a)
          @block = b
          @ptrs = ptrs
          @condition = initialize_condition_from_block(a)
        end

        def use(v)
          p = @condition[v]
          p ? p.call(v) : false
        end

        def step(ir)
          unless ir.result_variable
            bug() if ir.dispatch_method?
            return
          end
          @condition.delete(ir.result_variable)
          @ptrs.each{|p| @condition.delete(p)} if ir.dispatch_method?
        end

        def eql?(other)
          #@condition == other.condition && @block == other.block
          bug()
        end

        def ==(other)
          eql?(other)
        end

        def hash
          bug()
        end

        def freeze()
          super()
          @ptrs.freeze()
          @condition.freeze()
        end

        private

        NilWrapper   = ClassWrapper.new(NilClass,   true)
        FalseWrapper = ClassWrapper.new(FalseClass, true)
        def initialize_condition_from_block(a)
          cond = {}
          bug() unless a.instance_of?(Alias)
          return cond unless @block.pre.size == 1
          b = @block.pre[0]
          ir = b.irs.last
          return cond unless ir.is_a?(JumpIR)
          fallthrough = (ir.jump_targets & @block.labels).empty?
          p = nil
          case ir.jump_type
          when :branchif
            if fallthrough
              p = proc{|v| v.is_negative_cond_value; v.is_static([NilWrapper, FalseWrapper])}
            else
              p = proc{|v| v.is_not([NilWrapper, FalseWrapper])}
            end
          when :branchunless
            if fallthrough
              p = proc{|v| v.is_not([NilWrapper, FalseWrapper])}
            else
              p = proc{|v| v.is_negative_cond_value; v.is_static([NilWrapper, FalseWrapper])}
            end
          end
          if p
            set = a.find_set(ir.cond_value)
            bug() if set.empty?
            set.each{|s| cond[s] = p}
          end
          cond
        end
      end #VariableCondition
    end # Information

    def calc_egen_ekill
      all = all_ir()
      @blocks.each { |b| b.calc_egen() }
      @blocks.each { |b| b.calc_ekill(all) }
    end

    class BasicBlock
      attr_reader :egen, :ekill
      attr_accessor :information, :out_undefined, :in_undefined
      attr_accessor :in_guards

      def calc_egen()
        egen = []
        kill = []
        @irs.reverse.each do |ir|
          next unless ir.result_variable
          gen = [ir]
          egen |= (gen - kill)
          kill |= @irs.select{|i| i.result_variable == ir.result_variable && i != ir }
          kill |= @irs.select{|i| i.result_variable.is_a?(Pointer) && i != ir } if ir.dispatch_method?
        end
        @egen = egen
        @egen.freeze()
      end

      def calc_ekill(all)
        kill = []
        @irs.each do |ir|
          next unless ir.result_variable
          kill |= all.select{|i| i.result_variable == ir.result_variable && i != ir }
          kill |= all.select{|i| i.result_variable.is_a?(Pointer) && i != ir } if ir.dispatch_method?
        end
        @ekill = kill
        @ekill.freeze()
      end
    end # BasicBlock

    def calc_undefined_variables()
      vars = all_variable()
      change = true
      entry = @blocks[0]
      bug() if @blocks.find{|b| b != entry && b.pre.empty? }
      bug() unless entry.pre.empty?
      entry.in_undefined = vars
      @blocks.each{|b| b.out_undefined = []}
      entry.out_undefined = entry.in_undefined - entry.egen.map{|ir| ir.result_variable}
      while change
        change = false
        @blocks.each do |b0|
          if b0 != entry
            b0.in_undefined = b0.pre.inject([]){|in_undefined, b1| in_undefined | b1.out_undefined }
            out_undefined = b0.in_undefined + b0.ekill.map{|ir| ir.result_variable} - b0.egen.map{|ir| ir.result_variable}
            if !(out_undefined - b0.out_undefined).empty?
              b0.out_undefined |= out_undefined
              change = true
            end
          end
        end
      end
      @blocks.each do |b|
        b.in_undefined.freeze()
        b.out_undefined.freeze()
      end
      # validation
      @blocks.each do |b|
        undefined = b.in_undefined.dup()
        b.irs.each do |ir|
          ir.variables_without_result.each do |var|
            var.has_undefined_path() if undefined.include?(var)
          end
          result_variable = ir.result_variable
          undefined -= [result_variable] if result_variable
        end
      end
    end

    def set_information
      ptr_defs = all_pointer_definition()
      ptrs = all_pointer()
      vars = all_variable()
      calc_egen_ekill()
      calc_undefined_variables()
      entry = @blocks[0]
      bug() if @blocks.find{|b| (not b.in_undefined) || (not b.out_undefined)}
      bug() if @blocks.find{|b| b != entry && b.pre.empty? }
      bug() unless entry.pre.empty?
      @blocks.each{|b| b.information = Information.new(b, vars, vars, [], [], ptr_defs, ptrs)}
      entry.information = Information.new(entry, vars, vars, [], vars, ptr_defs, ptrs)
      change = true
      while change
        change = false
        @blocks.each do |b0|
          next if b0 == entry
          info = b0.pre.inject(Information.new(b0, vars, nil, [], [], ptr_defs, ptrs)) {|info, b1| info | b1.information.final_state()}
          change = true if b0.information != info
          b0.information = info
        end
      end
      change = true
      while change
        change = false
        @blocks.each do |b0|
          next if b0 == entry
          info = b0.information.dup
          b0.pre.each{|b1| info.kill_definition(b1.information.final_state())}
          change = true if b0.information != info
          b0.information = info
        end
      end
      @blocks.each{|b| b.information.freeze()}
      # validation
      @blocks.each do |b|
        variable_definition = b.information.dup()
        variable_definition.validate()
        b.irs.each do |ir|
          ir.variables_without_result.each do |var|
            var.has_undefined_path() if variable_definition.undefined_variables.include?(var)
          end
          variable_definition.step(ir)
        end
        variable_definition.validate_final()
      end
      @blocks.each do |b|
        u0 = b.in_undefined
        u1 = b.information.undefined_variables
        bug("u1 = #{u1}, u0 = #{u0}") unless (u0 - u1).empty? && (u1 - u0).empty?
        u0 = b.out_undefined
        u1 = b.information.final_state.undefined_variables
        bug("u1 = #{u1}, u0 = #{u0}") unless (u0 - u1).empty? && (u1 - u0).empty?
      end
    end

    class Guards
      include CastOff::Util
      include CastOff::Compiler::SimpleIR

      attr_reader :guards, :block

      def initialize(b, d, g, ptrs)
        @block = b
        @variable_definition = d
        @guards = g
        @ptrs = ptrs
      end

      def dup()
        Guards.new(@block, @variable_definition.dup(), @guards.dup(), @ptrs)
      end

      def &(other)
        bug() unless other.instance_of?(Guards)
        Guards.new(@block, @variable_definition.dup(), @guards & other.guards, @ptrs)
      end

      def eql?(other)
        bug() unless other.instance_of?(Guards)
        bug() unless other.block == @block
        @guards == other.guards
      end

      def ==(other)
        eql?(other)
      end

      def final_state()
        g = dup()
        @block.irs.each{|ir| g.step(ir)}
        g
      end

      def validate_final()
        @variable_definition.validate_final()
      end

      def redundant?(ir)
        ir.is_a?(StandardGuard) ? @guards.include?(ir.guard_value) : false
      end

      def step(ir)
        case ir
        when StandardGuard
          guard_value = ir.guard_value
          bug() unless guard_value.is_a?(Variable)
          @guards | [guard_value]
          @guards |= @variable_definition.find_same_variables(guard_value)
        when SubIR
          src = ir.src
          dst = ir.dst
          if @guards.include?(src)
            @guards |= [dst]
          else
            @guards -= [dst]
          end
        when CallIR
          @guards -= [ir.return_value]
          @guards -= @ptrs if ir.dispatch_method?
        end
        @variable_definition.step(ir)
      end

      def freeze()
        super()
        @guards.freeze()
        @variable_definition.freeze()
      end

      def to_s()
        @guards.map{|g| "#{g.to_debug_string()}"}.join(", ")
      end
    end

    def inject_guards()
      vars = all_variable()
      ptrs = all_pointer()
      vars.freeze()
      ptrs.freeze()
      @blocks.each do |b|
        b.irs.map! do |ir|
          g = ir.generate_guard(vars)
          g ? [g, ir] : ir
        end
        b.irs.flatten!
      end

      bug() if @blocks.find{|b| not b.information.frozen?}
      @blocks.each{|b| b.in_guards = Guards.new(b, b.information, [], ptrs)}
      change = true
      while change
        change = false
        @blocks.each do |b0|
          next if b0.entry_point?
          in_guards = b0.pre.inject(Guards.new(b0, b0.information, vars, ptrs)){|in_g, b1| in_g & b1.in_guards.final_state()}
          change = true if b0.in_guards != in_guards
          b0.in_guards = in_guards
        end
      end
      @blocks.each{|b| b.in_guards.freeze()}
    end
  end
end

