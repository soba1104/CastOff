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

    def verbose(b)
      CastOff::Util.set_verbose_mode(b)
    end

    def clear()
      CodeManager.clear()
    end

    @@blacklist = [
    ]

    @@autoload_proc = nil
    def autoload()
      return false if autocompile_running?
      if autoload_running?
        @@autoload_proc.call()
        return true 
      end

      # Marshal.load で定数を参照したときに、クラス定義が走る可能性があるので、
      # @@autoload_proc を定義する前に、Marshal.load を呼び出しておく。
      compiled = CodeManager.load_autocompiled()
      @@autoload_proc = lambda {
        compiled = CodeManager.load_autocompiled() unless compiled
        return false unless compiled
        fin = __load(compiled)
        hook_class_definition_end(nil) if fin
        fin
      }
      hook_class_definition_end(@@autoload_proc) if RUBY_VERSION == "1.9.3"
      @@autoload_proc.call()
      true
    end

    def load(force = false)
      return @@autoload_proc.call() if autoload_running? && !force
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
    case RUBY_VERSION
    when "1.9.3"
      @@compile_auto_incremental = true
    when "1.9.2"
      @@compile_auto_incremental = false
    else
      bug()
    end

    def autocompile()
      return false if autoload_running?
      return true if autocompile_running?
      class_table = {}
      bind_table = {}
      location_table = {}
      cinfo_table = {}
      compiled = []
      @@autocompile_proc = lambda {|event, file, line, mid, bind, klass, cinfo|
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
        if count == @@compilation_threshold && @@compile_auto_incremental
          compiled << __autocompile(klass, mid, bind_table, location_table, compiled.size)
        end
      }
      hook_method_invocation(@@autocompile_proc)
      at_exit do
        hook_method_invocation(nil) # clear trace
        unless @@compile_auto_incremental
          targets = []
          class_table.each do |klass, method_table|
            method_table.each do |mid, count|
              next unless count >= @@compilation_threshold
              targets << [klass, mid, count]
            end
          end
          targets = sort_targets(targets, cinfo_table)
          targets.each_with_index do |(klass, mid, count), index|
            dlog("#{count}: #{klass} #{mid}")
            compiled << __autocompile(klass, mid, bind_table, location_table, index)
          end
        end
        compiled.compact!
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

    @@original_instance_method_iseq = {}
    def delete_original_instance_method_iseq(target, mid)
      t = override_target(target, mid)
      @@original_instance_method_iseq.delete([t, mid])
    end

    def compile(target, mid, bind_or_typemap = nil, typemap = nil)
      execute_no_hook() do
        case target
        when Class, Module
          # ok
        else
          raise(ArgumentError.new("first argument should be Class or Module"))
        end
        mid, bind, typemap = parse_arguments(mid, bind_or_typemap, typemap)
        t = override_target(target, mid)
        iseq = @@original_instance_method_iseq[[t, mid]] || get_iseq(target, mid, false)
        manager, configuration, suggestion = compile_iseq(iseq, mid, typemap, false, bind)
        manager.compilation_target_is_a(t, mid, false)
        set_direct_call(target, mid, target.instance_of?(Class) ? :class : :module, manager, configuration)
        load_binary(manager, configuration, suggestion, iseq, bind)
        t = override_target(target, mid)
        dlog("override target of #{target}##{mid} is #{t}")
        __send__("register_method_#{manager.signiture}", t)
        @@original_instance_method_iseq[[t, mid]] = iseq
        @@manager_table[manager.signiture] = manager
      end
      true
    end

    @@original_singleton_method_iseq = {}
    def delete_original_singleton_method_iseq(obj, mid)
      @@original_singleton_method_iseq.delete([obj, mid])
    end

    def compile_singleton_method(obj, mid, bind_or_typemap = nil, typemap = nil)
      execute_no_hook() do
        mid, bind, typemap = parse_arguments(mid, bind_or_typemap, typemap)
        iseq = @@original_singleton_method_iseq[[obj, mid]] || get_iseq(obj, mid, true)
        manager, configuration, suggestion = compile_iseq(iseq, mid, typemap, false, bind)
        manager.compilation_target_is_a(obj, mid, true)
        set_direct_call(obj, mid, :singleton, manager, configuration)
        load_binary(manager, configuration, suggestion, iseq, bind)
        __send__("register_singleton_method_#{manager.signiture}", obj)
        @@original_singleton_method_iseq[[obj, mid]] = iseq
        @@manager_table[manager.signiture] = manager
      end
      true
    end

    @@loaded_binary = {}
    def execute(typemap = nil, &block)
      raise(ArgumentError.new('no block given')) unless block
      iseq = get_iseq_from_block(block)
      key = iseq.__id__
      if !@@loaded_binary[key]
        execute_no_hook() do
          bind = block.binding
          manager, configuration, suggestion = compile_iseq(iseq, nil, typemap, false, bind)
          load_binary(manager, configuration, suggestion, iseq, bind)
          @@loaded_binary[key] = manager.signiture
        end
      end
      sign = @@loaded_binary[key]
      recv = get_caller()
      __send__(sign, recv)
    end

    def autocompile_running?
      !!@@autocompile_proc
    end

    def autoload_running?
      !!@@autoload_proc
    end

    def compiler_running?
      !!Thread.current[COMPILER_RUNNING_KEY]
    end

    private

    COMPILER_RUNNING_KEY = :CastOffCompilerRunning
    def compiler_running(bool)
      Thread.current[COMPILER_RUNNING_KEY] = bool
    end

    def execute_no_hook()
      bug() unless block_given?
      begin
        compiler_running(true)
        hook_m = hook_method_invocation(nil)
        hook_c = hook_class_definition_end(nil)
        yield
      ensure
        compiler_running(false)
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

    def compile_iseq(iseq, mid, typemap, is_proc, bind)
      filepath, line_no = *iseq.to_a.slice(7, 2)
      raise(UnsupportedError.new(<<-EOS)) unless filepath && File.exist?(filepath)

Currently, CastOff cannot compile method which source file is not exist.
#{filepath.nil? ? 'nil' : filepath} is not exist.
      EOS
      manager = CodeManager.new(filepath, line_no)
      suggestion = Suggestion.new(iseq, @@suggestion_io)
      configuration = nil
      manager.do_atomically() do
        configuration = __compile(iseq, manager, typemap || {}, mid, is_proc, bind, suggestion)
      end
      bug() unless configuration.instance_of?(Configuration)
      [manager, configuration, suggestion]
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

    def union_base_configuration(conf, manager)
      if CastOff.use_base_configuration?
        u = manager.load_base_configuration()
        unless u
          bind = conf.bind
          u = Configuration.new({}, bind ? bind.bind : nil)
          manager.save_base_configuration(u)
        end
        conf.union(u)
      end
    end

    @@manager_table = {}
    def re_compile(signiture, sampling_table)
      manager = @@manager_table[signiture]
      return false unless manager
      bug() unless manager.instance_of?(CodeManager)
      reciever_result, return_value_result = parse_sampling_table(sampling_table)
      update_p = update_base_configuration(manager, reciever_result, return_value_result)
      compilation_target = manager.compilation_target
      bug() unless compilation_target
      target = compilation_target.target_object
      mid = compilation_target.method_id
      singleton = compilation_target.singleton_method?
      vlog("re-compile(#{target}#{singleton ? '.' : '#'}#{mid}): update_p = #{update_p}, reciever_result = #{reciever_result}, return_value_result = #{return_value_result}")
      return false unless update_p
      ann = manager.load_annotation() || {}
      bug() unless ann.instance_of?(Hash)
      manager.version_up()
      begin
        __send__(singleton ? 'compile_singleton_method' : 'compile', target, mid, ann)
      rescue => e
        vlog("re-compilation failed: #{target}#{singleton ? '.' : '#'}#{mid}")
      end
      true
    end

    class ReCompilation < StandardError; end

    def __compile(iseq, manager, annotation, mid, is_proc, bind, suggestion)
      if reuse_compiled_code? && !manager.target_file_updated?
        # already compiled
        if CastOff.development? || !CastOff.skip_configuration_check? || manager.last_configuration_enabled_development?
          conf = Configuration.new(annotation, bind)
          union_base_configuration(conf, manager)
          last_conf = manager.load_last_configuration()
          if last_conf && conf == last_conf
            dlog("reuse compiled binary")
            return last_conf
          end
        else
          dlog("reuse compiled binary")
          last_conf = manager.load_last_configuration()
          if last_conf
            return last_conf
          end
          conf = Configuration.new(annotation, bind)
          union_base_configuration(conf, manager)
        end
      else
        conf = Configuration.new(annotation, bind)
        union_base_configuration(conf, manager)
      end
      vlog("use configuration #{conf}")

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
      bug() unless conf
      dep = Dependency.new()
      block_inlining = true
      while true
        begin
          translator = Translator.new(iseq, conf, mid, is_proc, block_inlining, suggestion, dep, manager)
          c_source = translator.to_c()
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
      manager.compile_c_source(c_source, conf, dep)
      manager.save_annotation(annotation)
      manager.dump_development_mark(conf)
      conf
    end

    @@skipped = []
    def __load(compiled)
      begin
        (@@skipped + compiled.dup).each do |entry|
          klass, mid, singleton, file, line, bind = entry
          if @@blacklist.include?(mid)
            compiled.delete(entry)
            next
          end
          bind = bind.bind if bind
          skip = false
          if singleton
            iseq = @@original_singleton_method_iseq[[klass, mid]] || get_iseq(klass, mid, true)
          else
            begin
              t = override_target(klass, mid)
              iseq = @@original_instance_method_iseq[[t, mid]] || get_iseq(klass, mid, false)
            rescue CompileError, UnsupportedError
              @@skipped |= [entry]
              dlog("skip: entry = #{entry}")
              skip = true
            end
          end
          f, l = *iseq.to_a.slice(7, 2) unless skip
          if !skip && f == file && l == line
            begin
              @@skipped.delete(entry)
              if singleton
                CastOff.compile_singleton_method(klass, mid, bind)
              else
                CastOff.compile(klass, mid, bind)
              end
              vlog("load #{klass}##{mid}")
            rescue ArgumentError => e
              # dependency の Marshal.load に失敗
              vlog("skip: entry = #{entry[0]}#{entry[2] ? '.' : '#'}#{entry[1]}, #{e}")
              CodeManager.delete_from_compiled(entry)
            rescue UnsupportedError => e
              vlog("unsupported #{klass}##{mid} => #{e}")
              CodeManager.delete_from_compiled(entry)
            end
          else
            dlog("iseq.filepath = #{f}, file = #{file}\niseq.line = #{l}, line = #{line}")
          end
          compiled.delete(entry)
        end
        if compiled.empty?
          vlog("---------- load finish ----------") if @@skipped.empty?
          true
        else
          false
        end
      rescue => e
        vlog("catch exception #{e.class}: #{e}\n#{e.backtrace.join("\n")}")
        false
      end
    end

    s = class << BasicObject
      self
    end
    continue_load = RUBY_VERSION != "1.9.3"
    s.class_eval do
      define_method(:method_added) do |mid|
        if CastOff.autoload_running? && (!@@skipped.empty? || continue_load) && !CastOff.compiler_running?
          continue_load &= !@@autoload_proc.call()
        end
      end
    end

    def __autocompile(klass, mid, bind_table, location_table, index)
      return nil unless klass.instance_of?(Class) || klass.instance_of?(Module) # FIXME
      return nil if klass.name =~ /CastOff/ # ここで弾いておかないと、__compile の require で __load が走る。
                                            # Namespace のほうはあらかじめ require しておくことで回避。
                                            # Namespace 以外は CastOff を含むので問題無し。
      return nil if mid == :method_added || mid == :singleton_method_added
      if klass.instance_methods(false).include?(mid) || klass.private_instance_methods(false).include?(mid)
        singleton = false
      else
        return nil unless klass.singleton_methods(false).include?(mid)
        singleton = true
      end
      begin
        bind = bind_table[[klass, mid]]
        if singleton
          CastOff.compile_singleton_method(klass, mid, bind)
        else
          CastOff.compile(klass, mid, bind)
        end
        location = location_table[[klass, mid]]
        begin
          Marshal.dump(klass)
        rescue TypeError => e
          vlog("failed to marshal dump #{klass}: #{e.message}")
          return nil
        end
        vlog("#{index}: compile #{klass}#{singleton ? '.' : '#'}#{mid}")
        [klass, mid, singleton] + location + [Configuration::BindingWrapper.new(bind)] # klass, mid, file, line, binding
      rescue UnsupportedError => e
        vlog("#{index}: failed to compile #{klass}#{singleton ? '.' : '#'}#{mid} (#{e.message})")
        nil
      end
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

    def parse_sampling_table(sampling_table)
      reciever_result = {}
      return_value_result = {}
      sampling_table.each do |(key0, val0)|
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
      bug() unless (reciever_result.keys & return_value_result.keys).empty?
      [reciever_result, return_value_result]
    end

    def update_configuration(configuration, reciever_result, return_value_result)
      update_p  = false
      update_p |= configuration.update_variable_configuration(reciever_result)
      update_p |= configuration.update_return_value_configuration(return_value_result)
      update_p
    end

    def update_base_configuration(manager, reciever_result, return_value_result)
      base_configuration = manager.load_base_configuration()
      unless base_configuration
        last = manager.load_last_configuration()
        bind = last ? (last.bind ? last.bind.bind : nil) : nil
        base_configuration = Configuration.new({}, bind)
      end
      bug() unless base_configuration.instance_of?(Configuration)
      update_p = update_configuration(base_configuration, reciever_result, return_value_result)
      return false unless update_p
      manager.save_base_configuration(base_configuration)
      true
    end

    def set_sampling_table(suggestion, manager, configuration)
      if CastOff.development?
        h = Hash.new()
        __send__("register_sampling_table_#{manager.signiture}", h)
        suggestion.add_handler do
          reciever_result, return_value_result = parse_sampling_table(h)
          update_base_configuration(manager, reciever_result, return_value_result)
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

          bug() unless configuration
          s0 = configuration.to_s
          update_p = update_configuration(configuration, reciever_result, return_value_result)
          s1 = configuration.to_s
          configuration.compact()
          s2 = configuration.to_s
          if update_p
            bug() if s0 == s1
          else
            bug() if s0 != s1
          end
          if update_p
            suggestion.add_suggestion("You specify following type map to CastOff", ["Your Annotation"], [[s0]], false)
            suggestion.add_suggestion("CastOff suggests you to use following type map", ["CastOff Suggestion"], [[s2]], false)
          end
        end
      end
    end

    def set_direct_call(obj, mid, type, manager, configuration)
      bug() unless configuration
      return if configuration.use_method_frame?
      CastOff.should_be_call_directly(obj, mid, type)
    end

    def hook_method_override(manager, configuration, function_pointer_initializer)
      bug() unless configuration
      return unless configuration.alert_override?
      dep = manager.load_dependency()
      dep.check(configuration)
      dep.hook(function_pointer_initializer)
    end

    def load_binary(manager, configuration, suggestion, iseq, bind)
      so = manager.compiled_binary
      sign = manager.signiture
      bug("#{so} is not exist") unless File.exist?(so)
      load_compiled_file(so)
      function_pointer_initializer = "initialize_fptr_#{sign}".intern
      hook_method_override(manager, configuration, function_pointer_initializer)
      __send__("register_iseq_#{sign}", iseq)
      __send__("register_ifunc_#{sign}")
      set_sampling_table(suggestion, manager, configuration)
      suggestion.dump_at_exit()
      __send__(function_pointer_initializer)
      __send__("prefetch_constants_#{sign}", bind) if bind
    end

    def capture_instruction()
      a = [] # setlocal
      a[0] = a # getlocal, setn, pop, leave
    end
  end
end

