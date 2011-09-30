# coding=utf-8

module CastOff::Compiler
  class Translator
  class CFG
    include CastOff::Util
    include CastOff::Compiler::Instruction
    include CastOff::Compiler::SimpleIR

    attr_reader :blocks

    def to_c()
      @blocks.each{|b| b.iseq.append_c_function_body(b.to_c())}
    end

    def to_s()
      @blocks.join("\n")
    end

    def translator
      bug() unless @translator
      @translator
    end

    def initialize(body)
      @translator = nil
      blocks = []
      basicblock = []
      body.each do |v|
	case v
	when InsnInfo
	  basicblock << v
	  if BlockSeparator.include?(v.op)
	    blocks << basicblock
	    basicblock = []
	  end
	when Symbol
	  if !basicblock.empty?
	    blocks << basicblock
	    basicblock = []
	  end
	  blocks << v
	else
	  bug("v = #{v}")
	end
      end
      blocks << basicblock unless basicblock.empty?

      bbnum = -1
      blocks.map!{|b| b.instance_of?(Array) ? BasicBlock.new(self, b, bbnum += 1) : b}
      blocks.each{|b| b.set_prev_block(blocks) if b.instance_of?(BasicBlock)}
      blocks.each{|b| b.set_next_block(blocks) if b.instance_of?(BasicBlock)}
      @blocks = blocks.select{|b| b.instance_of?(BasicBlock)}
      @blocks.each{|b| bug() unless b.next && b.pre}

      eliminate_unreachable_blocks()
      validate_stack() # stack.rb
    end

    def gen_ir(t)
      @translator = t
      @blocks.each{|b| b.gen_ir()}
      change = true
      while change
        change = false
	set_information() # information.rb
	type_propergation()
	propergate_exact_class()
	propergate_guard_usage()
	inject_guards()
	reject_redundant_guards()
	if transform_branch_instruction()
	  eliminate_unreachable_blocks() # this method generates jump_guards
          change = true
        end
	reject_unused_ir() # should be call after guard generation
        change |= method_inlining()
	if change
	  validate_stack() # stack.rb
	  reject_guards()
	  reset_ir()
	end
      end
      unboxing()
      attach_var_info()
      set_sampling()
    end

    def find_variable(v0)
      all_variable.find{|v1| v0 == v1}
    end

    private

    def all_ir()
      @blocks.inject([]){|a, b| a.concat(b.irs)}.freeze()
    end

    def all_pointer_definition()
      all_ir().select{|ir| ir.result_variable.is_a?(Pointer)}.freeze()
    end

    def all_pointer()
      ptrs = all_pointer_definition().map{|ir| ir.result_variable}.uniq()
      bug() if ptrs.find{|p| not p.is_a?(Pointer)}
      ptrs.freeze()
    end

    def all_variable()
      all_ir().inject([]){|a, ir| a.concat(ir.variables)}.uniq()
    end

    def reset_ir()
      all_ir().each{|ir| ir.reset()}
    end

    def eliminate_unreachable_blocks()
      # Breadth first search
      achieved = []
      vertex = nil
      depth = 0
      queue = [@blocks[0]]
      while !queue.empty?
	vertex = queue.shift()
	bug() unless vertex
	achieved << vertex
	queue += vertex.next.select{|b| !queue.include?(b) && !achieved.include?(b)}
      end
      deadblocks = @blocks - achieved
      achieved.each do |aliveblock|
	aliveblock.pre.reject!{|b| deadblocks.include?(b)}
	bug() if aliveblock.next.find{|b| deadblocks.include?(b)}
      end
      @blocks = achieved
      @blocks.sort! {|a, b| a.number <=> b.number}
      bug() if @blocks.find{|b| b.pre.empty? && !b.entry_point?}
    end

    def reject_unused_ir()
      change = true
      while change
	change = false
	@blocks.each do |b|
	  defs = b.information.dup
	  b.irs.each do |ir|
	    change |= ir.mark(defs)
	    defs.step(ir)
	  end
	end
      end
      @blocks.each do |b|
	information = b.information.dup
	information.reject!{|ir| not ir.alive?}
	b.information = information
	b.irs.reject!{|ir| not ir.alive?}
      end
    end

    def transform_branch_instruction()
      change = false
      @blocks.each do |b|
	if b.next.size > 1
	  ir = b.irs.last
	  bug() unless ir.is_a?(JumpIR)
	  unused = ir.unused_target()
	  if unused
	    change = true
	    bug() unless b.next.size == 2
	    targets = ir.jump_targets
	    bug() unless targets.size() == 1
	    target = targets[0]
	    fallthrough = unused != :fallthrough
	    if fallthrough
	      dead_index = b.next[0].labels.include?(target) ? 0 : 1
	    else
	      dead_index = b.next[0].labels.include?(target) ? 1 : 0
	    end
	    dead  = b.next[dead_index]
	    jir = b.irs.pop()
            b.irs.push(JumpGuard.new(jir.cond_value, all_variable, jir.insn, self))
	    if !fallthrough
	      insn = InsnInfo.new([:jump, target], ir.insn.iseq, -1, -1)
	      b.irs.push(JumpIR.new(nil, insn, self))
	    end
	    b.next.delete(dead)
	    dead.pre.delete(b)
	  end
	end
      end
      change
    end

    def method_inlining()
      @blocks.each do |b|
        b.irs.each do |ir|
          if ir.inlining_target?
            todo()
          end
        end
      end
      false
    end

    def type_propergation()
      change = true
      while change
	change = false
	@blocks.each do |b|
	  defs = b.information.dup
	  b.irs.each do |ir|
	    change |= ir.type_propergation(defs)
	    bug() unless change == true || change == false
	    defs.step(ir)
	  end
	end
      end
      all_ir().each{|ir| ir.variables.each{|v| v.not_initialized() if v.undefined?}}
      bug() if all_ir().find{|ir| ir.variables.find{|v| v.undefined?}}
    end

    def propergate_exact_class()
      change = true
      while change
	change = false
	@blocks.each do |b|
	  defs = b.information.dup
	  b.irs.each do |ir|
	    change |= ir.propergate_exact_class(defs)
	    defs.step(ir)
	  end
	end
      end
    end

    def propergate_guard_usage()
      irs = all_ir()
      irs.each{|ir| ir.propergate_guard_usage()}
    end

    ### unboxing begin ###
    def unboxing()
      # 1: mark value which can not unbox
      # 1: mark value which can unbox
      irs = all_ir()
      irs.each{|ir| ir.unboxing_prelude()}
      bug() if irs.map{|ir| ir.values }.flatten.find{|v| v.box_unbox_undefined? }

      # 2: propergate value which can not unbox
      change = true
      while change
	change = false
	@blocks.each do |b|
	  defs = b.information.dup
	  b.irs.each do |ir|
	    change |= ir.propergate_value_which_can_not_unbox(defs)
	    defs.step(ir)
	  end
	end
      end
      bug() if irs.find{|ir| ir.instance_of?(SubIR) && ir.dst.can_not_unbox? != ir.src.can_not_unbox?}

      # 3: propergate value which can unbox
      change = true
      while change
	change = false
	@blocks.each do |b|
	  defs = b.information.dup
	  b.irs.each do |ir|
	    change |= ir.propergate_unbox_value(defs)
	    defs.step(ir)
	  end
	end
      end

      bug() if irs.map{|ir| ir.values }.flatten.find{|v| v.unboxed? && (v.dynamic? || v.types.size != 1)}
      irs.each do |ir|
	ir.values.each do |v|
	  next unless v.unboxed?
	end
      end

      irs.map{|ir| ir.values}.flatten.each{|v| v.box() unless v.unboxed?}
      irs.map{|ir| ir.values}.flatten.each{|v| bug() if !v.boxed? && !v.unboxed?}
      change = true
      while change
	change = false
	@blocks.each do |b|
	  defs = b.information.dup
	  b.irs.each do |ir|
	    change |= ir.propergate_box_value(defs)
	    defs.step(ir)
	  end
	end
      end

      @blocks.each do |b|
	defs = b.information.dup
	b.irs.each do |ir|
	  case ir
	  when SubIR
	    bug() unless ir.src.boxed?   == ir.dst.boxed?
	    bug() unless ir.src.unboxed? == ir.dst.unboxed?
	  end
	  ir.variables_without_result.each do |v|
	    ds = defs.variable_definition.select {|d| v == d.result_variable }
	    if v.unboxed?
	      bug() if ds.find{|d| not d.result_variable.unboxed? }
	    elsif v.boxed?
	      bug() if ds.find{|d| d.result_variable.unboxed? }
	    else
	      bug(ir)
	    end
	  end
	  defs.step(ir)
	end
      end
    end
    ### unboxing end ###

    def reject_redundant_guards()
      redundant = []
      ptrs = all_pointer()
      @blocks.each do |b|
	safe = b.in_guards.dup()
	b.irs.each do |ir|
	  redundant << ir if safe.redundant?(ir)
	  safe.step(ir)
	end
	safe.validate_final()
	b.irs.reject!{|ir| redundant.include?(ir)}
      end
    end

    def reject_guards()
      @blocks.each{|b| b.irs.reject!{|ir| ir.is_a?(StandardGuard)}}
    end

    def set_sampling()
      all_ir().each do |ir|
	targets = nil
	case ir
	when CallIR
	  case ir
	  when InvokeIR
	    ir.sampling_return_value()
	  else
	    # TODO
	  end
	  targets = ir.param_variables()
	when JumpIR
	  targets = [ir.cond_value] if ir.cond_value
	end
	next unless targets
	targets.each do |p|
	  next unless p.dynamic?
	  ir.get_definition(p).each do |d|
	    case d
	    when Literal
	      bug()
	    when Self
	      ir.add_sampling_variable(d)
	    when SubIR
	      ir.add_sampling_variable(d.src)
	    when CallIR
	      # Nothing to do.
	      # Always sampling CallIR's return value.
	    else
	      bug()
	    end
	  end
	end
      end
    end

    def attach_var_info()
      set_information() # information.rb

      @blocks.each do |b|
	defs = b.information.dup()
	b.irs.each do |ir|
	  ir.set_info(defs.dup())
	  defs.step(ir)
	end
	defs.validate_final()
      end
    end
  end
  end
end

