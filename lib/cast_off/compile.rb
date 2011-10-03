# coding=utf-8

module CastOff
  module Compiler
    include CastOff::Util

    DefaultSuggestionIO = Object.new
    DefaultSuggestionIO.extend(CastOff::Util)
    def DefaultSuggestionIO.puts(*msg)
      vlog(msg)
    end
    @@suggestion_io = DefaultSuggestionIO
    def set_suggestion_io(io)
      @@suggestion_io = io
    end

    @@loaded_binary = []

    @@blacklist = [
    ]

    @@autoload_proc = nil
    def autoload()
      return false if autocompile_running?
      if autoload_running?
	@@autoload_proc.call()
	return true 
      end
      return true if load()

      compiled = nil
      @@autoload_proc = lambda {
	compiled = CodeManager.load_autocompiled() unless compiled
	return false unless compiled
	fin = __load(compiled)
	hook_class_definition_end(nil) if fin
	fin
      }
      hook_class_definition_end(@@autoload_proc)
      true
    end

    def load()
      return @@autoload_proc.call() if autoload_running?
      compiled = CodeManager.load_autocompiled()
      return false unless compiled
      __load(compiled)
    end

    @@compilation_threshold = 100
    def compilation_threshold=(num)
      raise(ArgumentError.new("first argument should be Integer")) unless num.is_a?(Integer)
      raise(ArgumentError.new("threshold should be more than 0")) unless num >= 0
      @@compilation_threshold = num
    end

    @@autocompile_proc = nil
    def autocompile()
      return false if autoload_running?
      return true if autocompile_running?
      class_table = {}
      bind_table = {}
      location_table = {}
      cinfo_table = {}
      @@autocompile_proc = lambda {|event, file, line, mid, bind, klass, cinfo|
      #set_trace_func lambda {|event, file, line, mid, bind, klass|
	return unless file
	return if line < 0
	return if event != 'call'
	return if file =~ /\(/

	# TODO should handle singleton class

	# trace method invocation count
	method_table = class_table[klass]
	unless method_table
	  method_table = Hash.new(0) 
	  class_table[klass] = method_table
	end
	count = (method_table[mid] += 1)
	if count == 1
	  bind_table[[klass, mid]] = bind
	  location_table[[klass, mid]] = [File.expand_path(file), line]
	end
	if cinfo
	  table = (cinfo_table[[klass, mid]] ||= {})
	  table[cinfo] = true
	end
      }
      hook_method_invocation(@@autocompile_proc)
      at_exit do
	hook_method_invocation(nil) # clear trace
	#set_trace_func(nil) # clear trace
	targets = []
	class_table.each do |klass, method_table|
	  next unless klass.instance_of?(Class) || klass.instance_of?(Module) # FIXME
	  next if klass.name =~ /CastOff/ # ここで弾いておかないと、__compile の require で __load が走る。
					  # Namespace のほうはあらかじめ require しておくことで回避。
					  # Namespace 以外は CastOff を含むので問題無し。
	  method_table.each{|mid, count| targets << [klass, mid, count]}
	end
	targets = sort_targets(targets, cinfo_table)
	targets.each do |klass, mid, count|
	  dlog("#{count}: #{klass} #{mid}")
	end
	#targets = targets.sort{|v0, v1| v1.last <=> v0.last}
	compiled = []
	targets.each_with_index do |(klass, mid, count), index|
	  if klass.instance_methods(false).include?(mid) || klass.private_instance_methods(false).include?(mid)
	    singleton = false
	  else
	    next unless klass.singleton_methods(false).include?(mid)
	    singleton = true
	  end
	  next unless count >= @@compilation_threshold
	  begin
	    bind = bind_table[[klass, mid]]
	    if singleton
	      CastOff.compile_singleton_method(klass, mid, bind)
	    else
	      CastOff.compile(klass, mid, bind)
	    end
	    location = location_table[[klass, mid]]
	    compiled << ([klass, mid, singleton] + location + [Configuration::BindingWrapper.new(bind), count]) # klass, mid, file, line, binding
	    vlog("#{index}(#{count}): compile #{klass}#{singleton ? '.' : '#'}#{mid}")
	  rescue UnsupportedError => e
	    vlog("#{index}(#{count}): failed to compile #{klass}#{singleton ? '.' : '#'}#{mid} (#{e.message})")
	  end
	end
	CodeManager.dump_auto_compiled(compiled)
      end
      true
    end

    def compile_instance_methods(klass, bind = nil, skip = [])
      raise ArgumentError.new("first argument should be Class") unless klass.instance_of?(Class)
      raise ArgumentError.new("second argument should be Binding") unless !bind || bind.instance_of?(Binding)
      logger = self
      klass.class_eval do
	instance_methods(false).each_with_index do |mid, idx|
	  next if skip.include?(mid)
	  args = [klass, mid, bind]
	  begin
	    CastOff.compile(*args.compact())
	    logger.vlog("#{idx}: compile #{mid}")
	  rescue UnsupportedError => e
	    logger.vlog("#{idx}: failed to compile #{self}##{mid} (#{e.message})")
	  end
	end
      end
    end

    def compile(target, mid, bind_or_typemap = nil, typemap = nil)
      case target
      when Class, Module
	# ok
      else
	raise(ArgumentError.new("first argument should be class"))
      end
      mid, bind, typemap = parse_arguments(mid, bind_or_typemap, typemap)
      iseq = get_iseq(target, mid, false)
      manager, suggestion = compile_iseq(iseq, mid, typemap, false, bind)
      set_direct_call(target, mid, target.instance_of?(Class) ? :class : :module, manager)
      load_binary(manager, suggestion, iseq, bind)
      t = override_target(target, mid)
      dlog("override target of #{target}##{mid} is #{t}")
      __send__("register_method_#{manager.signiture}", t)
    end

    def compile_singleton_method(obj, mid, bind_or_typemap = nil, typemap = nil)
      mid, bind, typemap = parse_arguments(mid, bind_or_typemap, typemap)
      iseq = get_iseq(obj, mid, true)
      manager, suggestion = compile_iseq(iseq, mid, typemap, false, bind)
      set_direct_call(obj, mid, :singleton, manager)
      load_binary(manager, suggestion, iseq, bind)
      __send__("register_singleton_method_#{manager.signiture}", obj)
    end

    def execute(typemap = nil, &block)
      raise(ArgumentError.new('no block given')) unless block
      iseq = get_iseq_from_block(block)
      sign = gen_sign_from_iseq(iseq)
      if !@@loaded_binary.include?(sign)
	bind = block.binding
	manager, suggestion = compile_iseq(iseq, nil, typemap, false, bind)
	load_binary(manager, suggestion, iseq, bind)
	bug() unless sign == manager.signiture
	@@loaded_binary << sign
      end
      recv = get_caller()
      __send__(sign, recv)
    end

    private

    def execute_no_hook()
      bug() unless block_given?
      begin
	hook_m = hook_method_invocation(nil)
	hook_c = hook_class_definition_end(nil)
	yield
      ensure
	if hook_m
	  bug() unless autocompile_running?
	  hook_method_invocation(@@autocompile_proc)
	end
	if hook_c
	  bug() unless autoload_running?
	  hook_class_definition_end(@@autoload_proc)
	end
      end
    end

    def gen_sign_from_iseq(iseq)
      filepath, line_no = *iseq.to_a.slice(7, 2)
      "#{filepath}_#{line_no}".gsub(/\.|\/|-/, "_")
    end

    def compile_iseq(iseq, mid, typemap, is_proc, bind)
      filepath, line_no = *iseq.to_a.slice(7, 2)
      raise(UnsupportedError.new(<<-EOS)) unless filepath && File.exist?(filepath)

Currently, CastOff cannot compile method which source file is not exist.
#{filepath.nil? ? 'nil' : filepath} is not exist.
      EOS
      manager = CodeManager.new(filepath, line_no)
      suggestion = Suggestion.new(iseq, @@suggestion_io)
      execute_no_hook() do
	__compile(iseq, manager, typemap || {}, mid, is_proc, bind, suggestion)
      end
      [manager, suggestion]
    end

    def parse_arguments(mid, bind_or_typemap, typemap)
      case mid
      when Symbol
	# nothing to do
      when String
	mid = mid.intern
      else
	raise(ArgumentError.new('method name should be Symbol or String'))
      end
      case bind_or_typemap
      when Binding
	bind = bind_or_typemap
      when Hash
	raise(ArgumentError.new("Invalid arugments")) if typemap
	bind = nil
	typemap = bind_or_typemap
      when NilClass
	# nothing to do
	bind = nil
      else
	raise(ArgumentError.new("third argument should be Binding or Hash"))
      end
      [mid, bind, typemap]
    end

    def __select_configuration(current_specified_conf, manager)
      bug() unless current_specified_conf
      if current_specified_conf.use_profile_results? && manager.suggested_configuration_available?
	last_specified_conf = manager.load_last_specified_configuration()
	return current_specified_conf unless last_specified_conf
	dev = current_specified_conf.development?
	last_specified_conf.development(dev) # dev だけは揃える FIXME
	if current_specified_conf == last_specified_conf
	  # Configuration specified by user has not changed.
	  # Use configuration suggested by CastOff.
	  dlog("use suggested configuration")
	  suggested = manager.load_suggested_configuration(dev)
	  return suggested ? suggested : current_specified_conf
	end
      end
      # Use configuration specified by user.
      current_specified_conf
    end

    def select_configuration(current_specified_conf, manager)
      conf = __select_configuration(current_specified_conf, manager)
      if CastOff.clear_base_configuration?
	manager.clear_base_configuration()
      end
      if CastOff.use_base_configuration?
	u = manager.load_base_configuration()
	u ? conf.union(u) : vlog("failed to load base configuration")
      end
      conf
    end

    class ReCompilation < StandardError; end

    def __compile(iseq, manager, annotation, mid, is_proc, bind, suggestion)
      if reuse_compiled_binary? && !manager.target_file_updated?
	# already compiled
	if CastOff.development? || !CastOff.skip_configuration_check? || manager.last_used_configuration_enabled_development?
	  current_specified_conf = Configuration.new(annotation, bind)
	  conf = select_configuration(current_specified_conf, manager)
	  last_used_conf = manager.load_last_used_configuration()
	  if last_used_conf && conf == last_used_conf
	    dlog("reuse compiled binary")
	    manager.configure(last_used_conf)
	    return
	  end
	else
	  dlog("reuse compiled binary")
	  last_used_conf = manager.load_last_used_configuration()
	  if last_used_conf
	    manager.configure(last_used_conf)
	    return
	  end
	  current_specified_conf = Configuration.new(annotation, bind)
	  conf = select_configuration(current_specified_conf, manager)
	end
      else
	current_specified_conf = Configuration.new(annotation, bind)
	last_used_conf = nil
	conf = select_configuration(current_specified_conf, manager)
      end
      require 'cast_off/compile/namespace/uuid'
      require 'cast_off/compile/namespace/namespace'
      require 'cast_off/compile/instruction'
      require 'cast_off/compile/iseq'
      require 'cast_off/compile/ir/simple_ir'
      require 'cast_off/compile/ir/operand'
      require 'cast_off/compile/ir/sub_ir'
      require 'cast_off/compile/ir/jump_ir'
      require 'cast_off/compile/ir/param_ir'
      require 'cast_off/compile/ir/call_ir'
      require 'cast_off/compile/ir/return_ir'
      require 'cast_off/compile/ir/guard_ir'
      require 'cast_off/compile/translator'
      require 'cast_off/compile/cfg'
      require 'cast_off/compile/basicblock'
      require 'cast_off/compile/stack'
      require 'cast_off/compile/information'
      conf.validate()
      bug() unless current_specified_conf && conf
      dep = Dependency.new()
      block_inlining = true
      while true
	begin
	  translator = Translator.new(iseq, conf, mid, is_proc, block_inlining, suggestion, dep)
	  c_source = translator.to_c(manager.signiture)
	  break
	rescue ReCompilation
	  bug() unless block_inlining
	  block_inlining = false # FIXME get re-compilation type from exception object
	  dlog("failed to inline block...")
	end
      end
      conf.use_method_frame(!block_inlining)
      bug() unless c_source
      translator.suggest()
      manager.configure(conf)
      manager.compile_c_source(c_source, dep)
      if CastOff.update_base_configuration?
	vlog("update base configuration:\n#{conf}")
	manager.save_base_configuration(conf)
      end
      manager.dump_specified_configuration(current_specified_conf)
      manager.dump_development_mark()
    end

    def __load(compiled)
      begin
	compiled.dup.each do |entry|
	  klass, mid, singleton, file, line, bind, count = entry
	  if @@blacklist.include?(mid)
	    compiled.delete(entry)
	    next
	  end
	  bind = bind.bind if bind
	  entry.pop # release BindingWrapper
	  iseq = get_iseq(klass, mid, singleton)
	  f, l = *iseq.to_a.slice(7, 2)
	  if f == file && l == line
	    begin
	      if singleton
		CastOff.compile_singleton_method(klass, mid, bind)
	      else
		CastOff.compile(klass, mid, bind)
	      end
	      vlog("load #{klass}##{mid}")
	    rescue UnsupportedError
	      vlog("unsupported #{klass}##{mid}")
	    end
	  else
	    dlog("iseq.filepath = #{f}, file = #{file}\niseq.line = #{l}, line = #{line}")
	  end
	  compiled.delete(entry)
	end
	if compiled.empty?
	  vlog("---------- load finish ----------")
	  true
	else
	  false
	end
      rescue => e
	vlog("catch exception #{e.class}: #{e}\n#{e.backtrace.join("\n")}")
	false
      end
    end

    def autocompile_running?
      !!@@autocompile_proc
    end

    def autoload_running?
      !!@@autoload_proc
    end

    def __sort_targets(entry, targets, cinfo_table)
      result = []
      unless cinfo_table[entry]
	result << entry
	dlog("<< #{entry}: nil")
	return result # FIXME
      end

      targets.each do |te|
	bug() if entry == te
	next unless cinfo_table[te]
	next unless cinfo_table[te].keys.include?(entry) # entry calls te
	next if cinfo_table[entry].keys.include?(te) # cycle
	targets.delete(te)
	result += __sort_targets(te, targets, cinfo_table)
      end
      dlog("<< #{entry}: #{cinfo_table[entry].keys}")
      result << entry
      result
    end

    def sort_targets(targets, cinfo_table)
      result = []
      counts = {}
      targets = targets.sort{|v0, v1| v1.last <=> v0.last}
      targets.each{|klass, mid, count| counts[[klass, mid]] = count}
      targets = targets.map{|klass, mid, count| [klass, mid]}
      until targets.empty?
	entry = targets.shift
	result += __sort_targets(entry, targets, cinfo_table)
      end
      result.map!{|entry| entry + [counts[entry]]}
      bug() unless result.size == counts.size
      result
    end

    def set_sampling_table(suggestion, manager)
      if CastOff.development?
	h = Hash.new()
	__send__("register_sampling_table_#{manager.signiture}", h)
	suggestion.add_handler do
	  reciever_result = {}
	  return_value_result = {}
	  h.each do |(key0, val0)|
	    case key0
	    when Symbol
	      bug() unless val0.is_a?(Hash)
	      reciever_result[key0] = val0.keys
	    when Class
	      bug() unless val0.is_a?(Hash)
	      newval = {}
	      val0.each do |(key1, val1)|
		bug() unless key1.is_a?(Symbol)
		bug() unless val1.is_a?(Hash)
		newval[key1] = val1.keys
	      end
	      return_value_result[key0] = newval
	    else
	      bug("#{key0}, #{key0.class}")
	    end
	  end
	  if reciever_result.size > 0
	    msg = "These are unresolved local variables sampling results."
	    ary = []
	    reciever_result.each do |key0, val0|
	      bug() unless key0.is_a?(Symbol)
	      bug() unless val0.is_a?(Array)
	      val0.each do |t|
		ary << [key0.to_s, t.to_s]
	      end
	    end
	    suggestion.add_suggestion(msg, ["<Variable>", "<SamplingResultClass>"], ary)
	  end
	  if return_value_result.size > 0
	    msg = "These are unresolved method return values sampling results."
	    ary = []
	    return_value_result.each do |key0, val0|
	      bug() unless key0.is_a?(Class)
	      bug() unless val0.is_a?(Hash)
	      val0.each do |(mid, types)|
		types.each{|t| ary << ["#{key0}##{mid}", t.to_s]}
	      end
	    end
	    suggestion.add_suggestion(msg, ["<Method>", "<SamplingResultClass>"], ary)
	  end

	  conf = manager.adapted_configuration()
	  bug() unless conf
	  s0 = conf.to_s
	  bug() unless (reciever_result.keys & return_value_result.keys).empty?
	  update_p  = false
	  update_p |= conf.update_variable_configuration(reciever_result)
	  update_p |= conf.update_return_value_configuration(return_value_result)
	  s1 = conf.to_s
	  conf.compact()
	  s2 = conf.to_s
	  if update_p
	    bug() if s0 == s1
	  else
	    bug() if s0 != s1
	  end
	  manager.dump_suggested_configuration(conf)
	  if update_p
	    suggestion.add_suggestion("You specify following type map to CastOff", ["Your Annotation"], [[s0]], false)
	    suggestion.add_suggestion("CastOff suggests you to use following type map", ["CastOff Suggestion"], [[s2]], false)
	  end
	end
      end
    end

    def set_direct_call(obj, mid, type, manager)
      conf = manager.adapted_configuration
      bug() unless conf
      return if conf.use_method_frame?
      CastOff.should_be_call_directly(obj, mid, type)
    end

    def hook_method_override(manager, function_pointer_initializer)
      conf = manager.adapted_configuration
      bug() unless conf
      return unless conf.alert_override?
      dep = manager.load_dependency()
      dep.check(conf)
      dep.hook(function_pointer_initializer)
    end

    def load_binary(manager, suggestion, iseq, bind)
      execute_no_hook() do
	so = manager.compiled_binary
	sign = manager.signiture
	bug("#{so} is not exist") unless File.exist?(so)
	load_compiled_file(so)
	function_pointer_initializer = "initialize_fptr_#{sign}".intern
	hook_method_override(manager, function_pointer_initializer)
	__send__("register_iseq_#{sign}", iseq)
	__send__("register_ifunc_#{sign}")
	set_sampling_table(suggestion, manager)
	suggestion.dump_at_exit()
	__send__(function_pointer_initializer)
	__send__("prefetch_constants_#{sign}", bind) if bind
      end
    end
  end
end

