# coding=utf-8

module CastOff::Compiler
  module SimpleIR
    class SubIR < IR
      attr_reader :src, :dst, :variables_without_result, :variables, :result_variable, :values
      def initialize(src, dst, insn, cfg)
	super(insn, cfg)
	@src = src
	@dst = dst
	@values = [@src, @dst]
	@variables = []
	@variables_without_result = []
	if @src.is_a?(Variable)
	  @variables << @src
	  @variables_without_result << @src
	end
	bug() unless @dst.is_a?(Variable)
	@variables << @dst
	@result_variable = @dst
      end

      def to_debug_string()
	"#{@dst.to_debug_string()} = #{@src.to_debug_string()}"
      end

      ### unboxing begin ###
      def unboxing_prelude()
	if @src.can_unbox? && @dst.can_unbox?
	  @src.can_unbox()
	  @dst.can_unbox()
	else
	  @src.can_not_unbox()
	  @dst.can_not_unbox()
	end
      end

      def propergate_value_which_can_not_unbox(defs)
	change = false

	# forward
	change |= defs.can_not_unbox_variable_resolve_forward(@src)
	if @src.can_not_unbox?
	  change |= @dst.can_not_unbox()
	end

	# backward
	if @dst.can_not_unbox?
	  change |= @src.can_not_unbox()
	end
	if @src.can_not_unbox?
	  change |= defs.can_not_unbox_variable_resolve_backward(@src)
	end
	bug() unless @src.can_not_unbox? == @dst.can_not_unbox?

	change
      end

      def propergate_box_value(defs)
	change = false

	# forward
	change |= defs.box_value_resolve_forward(@src)
	if @src.boxed?
	  change |= @dst.box()
	end

	# backward
	if @dst.boxed?
	  change |= @src.box()
	end
	if @src.boxed?
	  change |= defs.box_value_resolve_backward(@src)
	end
	bug() unless @src.boxed?   == @dst.boxed?
	bug() unless @src.unboxed? == @dst.unboxed?

	change
      end

      def propergate_unbox_value(defs)
	#return false if @src.unboxed? && @dst.unboxed?
	if @src.can_not_unbox?
	  bug() unless @dst.can_not_unbox?
	  return false
	else
	  bug() if @dst.can_not_unbox?
	  change = false

	  if @src.instance_of?(Literal)
	    bug() unless @src.types.size == 1
	    bug() unless @src.static?
	    floatwrap  = ClassWrapper.new(Float, true)
	    fixnumwrap = ClassWrapper.new(Fixnum, true)
	    case @src.types[0]
	    when floatwrap, fixnumwrap
	      change |= @src.unbox()
	    end
	  end

	  change |= defs.unbox_value_resolve(@src)
	  if @src.unboxed? && !@dst.unboxed?
	    @dst.unbox()
	    change = true
	  end
	  return change
	end
      end
      ### unboxing end ###

      def propergate_exact_class(defs)
	change = defs.exact_class_resolve(@src)
	if @src.class_exact? && !@dst.class_exact?
	  @dst.is_class_exact()
	  change = true
	end
	change
      end

      def to_c()
	ret = []
	case @src
	when Argument
	  if @translator.inline_block?
	    # nothing to do
	  else
	    ret << "  #{@dst} = #{@src.lvar};"
	  end
	when ConstWrapper
	  @insn.iseq.reference_constant
	  if @src.prefetch?
	    @translator.prefetch_constant(@src.to_name, @src.path, false)
	    ret << "  #{@dst} = #{@src};"
	  else
	    if @src.cache?
	      ret << <<-EOS
  if (UNLIKELY(#{@src} == Qundef)) {
#{@src.get_constant_chain()}
  }
  #{@dst} = #{@src};
	      EOS
	    else
	      ret << <<-EOS
#{@src.get_constant_chain()}
  #{@dst} = #{@src};
	      EOS
	    end
	  end
	when GlobalVariable
	  bug() unless @dst.is_a?(TmpVariable)
	  ret << "  #{@dst} = rb_gvar_get(rb_global_entry(#{@translator.allocate_id(@src.id)}));"
	  ret << "  #{@src} = #{@dst};"
	when ClassVariable
	  bug() unless @dst.is_a?(TmpVariable)
	  ret << "  #{@dst} = rb_cvar_get(cast_off_get_cvar_base(), #{@translator.allocate_id(@src.id)});"
	  ret << "  #{@src} = #{@dst};"
	when InstanceVariable
	  bug() unless @dst.is_a?(TmpVariable)
	  # FIXME 間にメソッド呼び出しをはさんでいない場合は、読んだ結果をローカル変数(instance_id)にキャッシュする
	  if @translator.use_fast_ivar?
	    ret << "  #{@dst} = iv_table_ptr[#{@translator.get_ivar_index(@translator.allocate_id(@src.id), @src.to_name)}];"
	  else
	    ret << "  #{@dst} = vm_getivar(self, #{@translator.allocate_id(@src.id)}, &#{@translator.get_ic(@src.to_name)});"
	  end
	  ret << "  #{@src} = #{@dst};"
	else
	  case @dst
	  when Argument, ConstWrapper
	    bug()
	  when InstanceVariable
	    # FIXME 間にメソッド呼び出しをはさんでいない場合は、書いた結果をローカル変数(instance_id)にキャッシュする
	    if @translator.use_fast_ivar?
	      ret << "  iv_table_ptr[#{@translator.get_ivar_index(@translator.allocate_id(@dst.id), @dst.to_name)}] = #{@src};"
	    else
	      ret << "  vm_setivar(self, #{@translator.allocate_id(@dst.id)}, #{@src}, &#{@translator.get_ic(@dst.to_name)});"
	    end
	  when ClassVariable
	    ret << "  rb_cvar_set(cast_off_get_cvar_base(), #{@translator.allocate_id(@dst.id)}, #{@src});"
	  when GlobalVariable
	    ret << "  rb_gvar_set(rb_global_entry(#{@translator.allocate_id(@dst.id)}), #{@src});"
	  else
	    ret << "  #{@dst} = #{@src};"
	  end
	end
	ret.join("\n")
      end

      def type_propergation(defs)
	defs.type_resolve(@src) | @dst.union(@src)
      end

      def mark(defs)
	if @dst.is_a?(Pointer)
	  # read に関しては、使われてないなら行う必要はない
	  if !alive?
	    alive()
	    defs.mark(@src)
	    true
	  else
	    defs.mark(@src)
	  end
	else
	  alive? && defs.mark(@src)
	end
      end
    end
  end
end

