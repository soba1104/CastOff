# coding=utf-8

module CastOff
module Compiler

  class SingletonClass
    def self.to_s
      "<< SINGLETON CLASS >>"
    end
  end

  class Configuration
    include CastOff::Util
    extend  CastOff::Util

    class InvalidConfigurationError < StandardError; end

    attr_reader :return_value_configuration
    attr_reader :ignore_configuration_of_return_values
    attr_reader :variable_configuration
    attr_reader :ignore_configuration_of_variables
    attr_reader :method_information_usage
    attr_reader :option_table_configuration
    attr_reader :bind

    class BindingWrapper
      include CastOff::Util

      attr_reader :bind, :nest

      def initialize(bind)
        bug() unless bind.instance_of?(Binding)
        @bind = bind
        nest = eval("Module.nesting", @bind)
        pre = ""
        @nest = nest.reverse.map{|n|
          n = n.to_s
          if n[pre]
            replen = pre.length
            replen += 2 unless pre.empty?
            pre = n
            n.slice(replen, n.length - replen)
          else
            n
          end
        }
        begin
          marshal_load(@nest) # validation
        rescue NameError => e
          raise(UnsupportedError.new(<<-EOS))

Failed to construct binding from Module.nesting result (#{nest}).
Currently, CastOff doesn't support binding which cannot construct from Module.nesting result.
CastOff constructs binding with the following process.

--- binding construction process ---
o = Object
#{@nest.map{|n| "o = o.const_get(:#{n})" }.join("\n")}

--- error message ---
#{e.message}
          EOS
        rescue => e
          bug("e = #{e}, @nest = #{@nest}, nest = #{nest}")
        end
      end

      def marshal_dump()
        @nest
      end

      def marshal_load(nest)
        o = Object
        ary = []
        nest.each do |n|
          n.split("::").each do |__n|
            o = o.const_get(__n)
          end
          ary << [n, o]
        end
        s0 = []
        s1 = []
        ary.each_with_index do |no, idx|
          n, o = no
          case o
          when Class
            decl = "class"
          when Module
            decl = "module"
          else
            bug("obj = #{o}")
          end
          indent = "  " * idx
          s0 << indent + "#{decl} #{n}"
          s1 << indent + "end"
        end
        indent = "  " * ary.size
        eval_str = s0.join("\n") + "\n#{indent}binding\n" + s1.reverse.join("\n")
        bind = eval(eval_str, TOPLEVEL_BINDING)
        bug() unless bind.instance_of?(Binding)
        @bind = bind
        @nest = nest
      end

      def eql?(other)
        return false unless other.instance_of?(BindingWrapper)
        @nest == other.nest
      end

      def ==(other)
        eql?(other)
      end

      def hash()
        BindingWrapper.hash
      end
    end

    def initialize(configuration, bind)
      @bind = bind ? BindingWrapper.new(bind) : nil
      @return_value_configuration = {}
      @variable_configuration = {}
      case configuration
      when Hash
        configuration.each do |(k, v)|
          case k
          when Array
            k.each do |var|
              invalid_configuration() unless var.is_a?(Symbol)
              case v
              when Class
                # [:var0, :var1, ...] => class
                a = @variable_configuration[var] || []
                a |= [ClassWrapper.new(v, true)]
                @variable_configuration[var] = a
              when Array
                # [:var0, :var1, ...] => [class0, class1, ...]
                v.each {|t| invalid_configuration() unless t.is_a?(Class)}
                a = @variable_configuration[var] || []
                a |= v.map{|t| ClassWrapper.new(t, true)}
                @variable_configuration[var] = a
              else
                invalid_configuration()
              end
            end
          when Symbol
            case v
            when Class
              # :var => class
              a = @variable_configuration[k] || []
              a |= [ClassWrapper.new(v, true)]
              @variable_configuration[k] = a
            when Array
              # :var => [class0, class1, ...]
              v.each {|t| invalid_configuration() unless t.is_a?(Class)}
              a = @variable_configuration[k] || []
              a |= v.map{|t| ClassWrapper.new(t, true)}
              @variable_configuration[k] = a
            else
              invalid_configuration("variable class should be specified by Class or Array")
            end
          when Class
            # class => {:method_name => class, ...}
            case v
            when Hash
              k = ClassWrapper.new(k, true)
              h = @return_value_configuration[k] || {}
              v.each do |(id, type)|
                invalid_configuration() unless id.is_a?(Symbol)
                case type
                when Class
                  a = h[id] || []
                  a |= [ClassWrapper.new(type, true)]
                  h[id] = a
                when Array
                  type.each {|t| invalid_configuration() unless t.is_a?(Class) }
                  a = h[id] || []
                  a |= type.map{|t| ClassWrapper.new(t, true)}
                  h[id] = a
                else
                  invalid_configuration()
                end
              end
              @return_value_configuration[k] = h
            else
              invalid_configuration()
            end
          end
        end
      else
        invalid_configuration()
      end
      @return_value_configuration.each do |(k, v)|
        bug() unless k.is_a?(ClassWrapper)
        v.each do |(mid, ary)|
          ary.each{|t| bug(t) unless t.is_a?(ClassWrapper)}
        end
      end
      @ignore_configuration_of_return_values = {}
      @variable_configuration.values.each do |ary|
        ary.each{|t| bug(t) unless t.is_a?(ClassWrapper)}
      end
      @ignore_configuration_of_variables = {}
      @method_information_usage = []
      @option_table_configuration = {}
      @use_method_frame = false
      OPTION_TABLE.each{|(cvar, val)| @option_table_configuration[cvar] = self.class.class_variable_get(cvar)}
      prefetch_constant(false) unless @bind
    end

    def use_method_frame(bool)
      @use_method_frame = !!bool
    end

    def use_method_frame?
      @use_method_frame
    end

    def class_of_variable(var)
      bug() unless var.is_a?(Symbol)
      @variable_configuration[var]
    end

    def return_value_class(c, m)
      bug() unless c.is_a?(ClassWrapper)
      bug() unless m.is_a?(Symbol)
      h = @return_value_configuration[c]
      h ? h[m] : nil
    end

    def has_binding?
      !!@bind
    end

    def evaluate_by_passed_binding(str)
      bug() unless @bind.instance_of?(BindingWrapper)
      bug() unless @bind.bind.instance_of?(Binding)
      begin
        eval(str, @bind.bind)
      rescue
        raise(CastOff::CompileError.new("Failed to evaluate < #{str} > with passed binding"))
      end
    end

    def union(conf)
      bug() unless conf.instance_of?(Configuration)
      conf.variable_configuration.each do |(sym, src)|
        bug() unless src.instance_of?(Array)
        dst = (@variable_configuration[sym] ||= [])
        (src + dst).each do |cw|
          bug() unless cw.instance_of?(ClassWrapper)
          bug() if !cw.singleton? && cw.contain_class == SingletonClass
        end
        @variable_configuration[sym] = (dst | src)
      end
      conf.ignore_configuration_of_variables.each do |(k, v)|
        bug() unless k.instance_of?(Symbol)
        bug() unless v == true
        @ignore_configuration_of_variables[k] = true
      end
      __ignore_configuration_of_variables(:union)

      conf.return_value_configuration.each do |(cw0, src0)|
        bug() unless src0.instance_of?(Hash)
        bug() unless cw0.instance_of?(ClassWrapper)
        bug() if !cw0.singleton? && cw0.contain_class == SingletonClass
        dst0 = (@return_value_configuration[cw0] ||= {})
        src0.each do |(sym, src1)|
          bug() unless src1.instance_of?(Array)
          dst1 = (dst0[sym] ||= [])
          (src1 + dst1).each do |cw1|
            bug() unless cw1.instance_of?(ClassWrapper)
            bug() if !cw1.singleton? && cw1.contain_class == SingletonClass
          end
          dst0[sym] = (dst1 | src1)
        end
      end
      conf.ignore_configuration_of_return_values.each do |(k, mids)|
        bug() if mids.find{|m| !m.instance_of?(Symbol)}
        @ignore_configuration_of_return_values[k] ||= []
        @ignore_configuration_of_return_values[k] |= mids
      end
      __ignore_configuration_of_return_values(:union)

      return if @bind
      return unless conf.bind
      bug() unless conf.bind.instance_of?(BindingWrapper)
      @bind = conf.bind
      prefetch_constant(true)
    end

    def update_variable_configuration(update_hash)
      update_p = false
      updates = []
      starts  = @variable_configuration.keys
      update_hash.each do |(k, v)|
        bug() unless k.instance_of?(Symbol)
        bug() unless v.instance_of?(Array)
        if v.map{|a| a.first }.include?(SingletonClass)
          update_p = true unless @ignore_configuration_of_variables[k]
          @ignore_configuration_of_variables[k] = true
        end
        next if @ignore_configuration_of_variables[k]
        # annotation of variables
        a0 = v
        a0 = a0.map{|(c, singleton_p)|
          bug(c) unless c.is_a?(Class) || (c.is_a?(Module) && singleton_p)
          bug()  unless c != SingletonClass
          if singleton_p
            wrapper = ClassWrapper.new(c, false)
            bug() unless wrapper.singleton?
          else
            wrapper = ClassWrapper.new(c, true)
          end
          wrapper
        }
        a1 = @variable_configuration[k] || []
        updates << k unless (a0 - a1).empty?
        a1 |= a0
        @variable_configuration[k] = a1
      end
      deletes = __ignore_configuration_of_variables(:update)
      inc_p = !(updates - deletes).empty?
      dec_p = !(starts & deletes).empty?
      inc_p | dec_p | update_p
    end

    def update_return_value_configuration(update_hash)
      update_p = false
      updates = []
      starts  = []
      @return_value_configuration.each do |klass, hash|
        bug() unless klass.instance_of?(ClassWrapper)
        bug() unless hash.instance_of?(Hash)
        hash.keys.each do |mid|
          bug() unless mid.instance_of?(Symbol)
          starts << [klass, mid]
        end
      end
      bug() unless update_hash.size == 2
      update_hash.each do |(sym, mtbl)|
        bug() unless sym == :singleton_methods || sym == :instance_methods
        bug() unless mtbl.is_a?(Hash)
        mtbl.each do |(k, v)|
          bug() unless k.instance_of?(Class) || (k.instance_of?(Module) && sym == :singleton_methods)
          bug() unless v.instance_of?(Hash)
          if k == SingletonClass
            bug() if sym == :singleton_methods
            ignore_targets = v.keys
            bug() if ignore_targets.find{|m| !m.instance_of?(Symbol)}
            @ignore_configuration_of_return_values[SingletonClass] ||= []
            update_p = true unless (ignore_targets - @ignore_configuration_of_return_values[SingletonClass]).empty?
            @ignore_configuration_of_return_values[SingletonClass] |= ignore_targets
            next
          end
          # annotation of return values
          h0 = v
          k  = ClassWrapper.new(k, sym == :instance_methods)
          h1 = @return_value_configuration[k] || {}
          h0.each do |(mid, klasses0)|
            ignore_p = false
            bug() unless klasses0.is_a?(Array)
            klasses0.each do |(c, singleton_p)|
              if c == SingletonClass
                bug() if singleton_p
                ignore_p = true
                break
              end
            end
            if ignore_p
              bug() unless k.instance_of?(ClassWrapper)
              ignore_targets = (@ignore_configuration_of_return_values[k] ||= [])
              unless ignore_targets.include?(mid)
                ignore_targets.push(mid)
                update_p = true 
              end
              next
            end
            next if @ignore_configuration_of_return_values[k] && @ignore_configuration_of_return_values[k].include?(mid)
            klasses0 = klasses0.map{|(c, singleton_p)|
              bug(c) unless c.is_a?(Class) || (c.is_a?(Module) && singleton_p)
              bug()  unless c != SingletonClass
              if singleton_p
                wrapper = ClassWrapper.new(c, false)
                bug() unless wrapper.singleton?
              else
                wrapper = ClassWrapper.new(c, true)
              end
              wrapper
            }
            klasses1 = h1[mid] || []
            updates |= [[k, mid]] unless (klasses0 - klasses1).empty?
            klasses1 |= klasses0
            h1[mid] = klasses1
          end
          @return_value_configuration[k] = h1
        end
      end
      deletes = __ignore_configuration_of_return_values(:update)
      inc_p = !(updates - deletes).empty?
      dec_p = !(starts & deletes).empty?
      bug() if updates.find{|(k, v)| !(k.instance_of?(ClassWrapper) && v.instance_of?(Symbol))}
      bug() if deletes.find{|(k, v)| !(k.instance_of?(ClassWrapper) && v.instance_of?(Symbol))}
      bug() if  starts.find{|(k, v)| !(k.instance_of?(ClassWrapper) && v.instance_of?(Symbol))}
      inc_p | dec_p | update_p
    end

    def compact()
      rejects0 = []
      @return_value_configuration.each do |(k0, v0)|
        rejects1 = []
        v0.each{|(k1, v1)| rejects1 << k1 if v1.size > 5}
        rejects1.each{|v| v0.delete(v)}
        rejects0 << k0 if v0.empty?
      end
      rejects0.each{|v| @return_value_configuration.delete(v)}
      rejects0 = []
      @variable_configuration.each do |(k0, v0)|
        rejects0 << k0 if v0.size > 5
      end
      rejects0.each{|v| @variable_configuration.delete(v)}
    end

    def validate()
      begin
        dump()
      rescue TypeError => e
        raise(UnsupportedError.new(<<-EOS))

Failed to marshal dump configuration.
Configuration object should be able to marshal dump.
Currently, CastOff doesn't support object, which cannot marshal dump (e.g. STDIN).
--- Marshal.dump error message ---
#{e.message}
        EOS
      end
    end

    def dump(io = nil)
      if io
        Marshal.dump(self, io)
      else
        Marshal.dump(self)
      end
    end

    def self.load(io)
      begin
        conf = Marshal.load(io)
      rescue NameError, ArgumentError
        return nil
      end
      bug() unless conf.instance_of?(Configuration)
      return nil unless conf.check_method_information_usage()
      conf
    end

    def eql?(other)
      return false if other.nil?
      bug() unless other.is_a?(Configuration)
      return false unless @variable_configuration == other.variable_configuration
      return false unless @return_value_configuration == other.return_value_configuration
      return false unless same_option?(other.option_table_configuration)
      return false unless @bind == other.bind
      true
    end

    def ==(other)
      eql?(other)
    end

    def to_s
      ary = []
      @variable_configuration.each do |(k, v)|
        bug() unless k.instance_of?(Symbol)
        ary << "#{k.inspect} => #{v.inspect}"
      end
      @return_value_configuration.each do |(k, v)|
        bug() unless k.instance_of?(ClassWrapper)
        ary << "#{k.inspect} => #{inspect_method_return_value(v)}"
      end
      "{#{ary.join(",\n ")}}"
    end

    def inspect_method_return_value(h)
      bug() unless h.instance_of?(Hash)
      '{' + h.map{|(mid, classes)|
        bug() unless mid.instance_of?(Symbol)
        bug() unless classes.instance_of?(Array)
        "#{mid.inspect} => #{classes.inspect}"
      }.join(', ') + '}'
    end

    DIRECT_CALL_TARGETS = [
      [BasicObject, :initialize, :class],
      [BasicObject, :==, :class],
      [BasicObject, :equal?, :class],
      [BasicObject, :!, :class],
      [BasicObject, :!=, :class],
      [BasicObject, :singleton_method_added, :class],
      [BasicObject, :singleton_method_removed, :class],
      [BasicObject, :singleton_method_undefined, :class],
      [Class, :inherited, :class],
      [Module, :included, :class],
      [Module, :extended, :class],
      [Module, :method_added, :class],
      [Module, :method_removed, :class],
      [Module, :method_undefined, :class],
      [Kernel, :nil?, :module],
      [Kernel, :===, :module],
      [Kernel, :=~, :module],
      [Kernel, :!~, :module],
      [Kernel, :eql?, :module],
      [Kernel, :hash, :module],
      [Kernel, :<=>, :module],
      [Kernel, :class, :module],
      [Kernel, :singleton_class, :module],
      [Kernel, :clone, :module],
      [Kernel, :dup, :module],
      [Kernel, :initialize_copy, :module],
      [Kernel, :initialize_dup, :module],
      [Kernel, :initialize_clone, :module],
      [Kernel, :taint, :module],
      [Kernel, :tainted?, :module],
      [Kernel, :untaint, :module],
      [Kernel, :untrust, :module],
      [Kernel, :untrusted?, :module],
      [Kernel, :trust, :module],
      [Kernel, :freeze, :module],
      [Kernel, :frozen?, :module],
      [Kernel, :to_s, :module],
      #[Kernel, :inspect, :module], #rb_exec_recursive => recursive_list_access
      [Kernel, :methods, :module],
      [Kernel, :singleton_methods, :module],
      [Kernel, :protected_methods, :module],
      [Kernel, :private_methods, :module],
      [Kernel, :public_methods, :module],
      [Kernel, :instance_variables, :module],
      [Kernel, :instance_variable_get, :module],
      [Kernel, :instance_variable_set, :module],
      [Kernel, :instance_variable_defined?, :module],
      [Kernel, :remove_instance_variable, :module],
      [Kernel, :instance_of?, :module],
      [Kernel, :kind_of?, :module],
      [Kernel, :is_a?, :module],
      [Kernel, :tap, :module],
      [Kernel, :sprintf, :module],
      [Kernel, :sprintf, :singleton],
      [Kernel, :format, :module],
      [Kernel, :format, :singleton],
      [Kernel, :Integer, :module],
      [Kernel, :Integer, :singleton],
      [Kernel, :Float, :module],
      [Kernel, :Float, :singleton],
      [Kernel, :String, :module],
      [Kernel, :String, :singleton],
      [Kernel, :Array, :module],
      [Kernel, :Array, :singleton],
      [NilClass, :to_i, :class],
      [NilClass, :to_f, :class],
      [NilClass, :to_s, :class],
      [NilClass, :to_a, :class],
      [NilClass, :inspect, :class],
      [NilClass, :&, :class],
      [NilClass, :|, :class],
      [NilClass, :^, :class],
      [NilClass, :nil?, :class],
      [Module, :freeze, :class],
      [Module, :===, :class],
      [Module, :==, :class],
      [Module, :<=>, :class],
      [Module, :<, :class],
      [Module, :<=, :class],
      [Module, :>, :class],
      [Module, :>=, :class],
      [Module, :initialize_copy, :class],
      [Module, :to_s, :class],
      [Module, :included_modules, :class],
      [Module, :include?, :class],
      [Module, :name, :class],
      [Module, :ancestors, :class],
      [Module, :attr, :class],
      [Module, :attr_reader, :class],
      [Module, :attr_writer, :class],
      [Module, :attr_accessor, :class],
      #[Module, :initialize, :class], #rb_mod_initialize => rb_block_given_p
      [Module, :instance_methods, :class],
      [Module, :public_instance_methods, :class],
      [Module, :protected_instance_methods, :class],
      [Module, :private_instance_methods, :class],
      [Module, :constants, :class],
      [Module, :const_get, :class],
      [Module, :const_set, :class],
      [Module, :const_defined?, :class],
      [Module, :remove_const, :class],
      [Module, :const_missing, :class],
      [Module, :class_variables, :class],
      [Module, :remove_class_variable, :class],
      [Module, :class_variable_get, :class],
      [Module, :class_variable_set, :class],
      [Module, :class_variable_defined?, :class],
      [Module, :public_constant, :class],
      [Module, :private_constant, :class],
      [Class, :allocate, :class],
      [Class, :new, :class],
      #[Class, :initialize, :class], #rb_class_initialize => rb_mod_initialize => rb_block_given_p
      [Class, :initialize_copy, :class],
      [Class, :superclass, :class],
      [TrueClass, :to_s, :class],
      [TrueClass, :&, :class],
      [TrueClass, :|, :class],
      [TrueClass, :^, :class],
      [FalseClass, :to_s, :class],
      [FalseClass, :&, :class],
      [FalseClass, :|, :class],
      [FalseClass, :^, :class],
      [Encoding, :to_s, :class],
      [Encoding, :inspect, :class],
      [Encoding, :name, :class],
      [Encoding, :names, :class],
      [Encoding, :dummy?, :class],
      [Encoding, :ascii_compatible?, :class],
      [Encoding, :replicate, :class],
      [Encoding, :list, :singleton],
      [Encoding, :name_list, :singleton],
      [Encoding, :aliases, :singleton],
      [Encoding, :find, :singleton],
      [Encoding, :compatible?, :singleton],
      [Encoding, :_dump, :class],
      [Encoding, :_load, :singleton],
      [Encoding, :default_external, :singleton],
      [Encoding, :default_external=, :singleton],
      [Encoding, :default_internal, :singleton],
      [Encoding, :default_internal=, :singleton],
      [Encoding, :locale_charmap, :singleton],
      [Comparable, :==, :module],
      [Comparable, :>, :module],
      [Comparable, :>=, :module],
      [Comparable, :<, :module],
      [Comparable, :<=, :module],
      [Comparable, :between?, :module],
      [Enumerable, :to_a, :module],
      [Enumerable, :entries, :module],
      [Enumerable, :sort, :module],
      #[Enumerable, :sort_by, :module], #enum_sort_by
      #[Enumerable, :grep, :module], #enum_grep => rb_block_given_p
      #[Enumerable, :count, :module], #enum_count => rb_block_given_p
      #[Enumerable, :find, :module], #enum_find
      #[Enumerable, :detect, :module], #enum_find
      #[Enumerable, :find_index, :module], #enum_find_index => rb_block_given_p
      #[Enumerable, :find_all, :module], #enum_find_all
      #[Enumerable, :select, :module], #enum_find_all
      #[Enumerable, :reject, :module], #enum_reject
      #[Enumerable, :collect, :module], #enum_collect
      #[Enumerable, :map, :module], #enum_collect
      #[Enumerable, :flat_map, :module], #enum_flat_map
      #[Enumerable, :collect_concat, :module], #enum_flat_map
      #[Enumerable, :inject, :module], #enum_inject => rb_block_given_p
      #[Enumerable, :reduce, :module], #enum_inject => rb_block_given_p
      #[Enumerable, :partition, :module], #enum_partition
      #[Enumerable, :group_by, :module], #enum_group_by
      [Enumerable, :first, :module],
      [Enumerable, :all?, :module],
      [Enumerable, :any?, :module],
      [Enumerable, :one?, :module],
      [Enumerable, :none?, :module],
      #[Enumerable, :min, :module], #enum_min => rb_block_given_p
      #[Enumerable, :max, :module], #enum_max => rb_block_given_p
      #[Enumerable, :minmax, :module], #enum_minmax => rb_block_given_p
      #[Enumerable, :min_by, :module], #enum_min_by
      #[Enumerable, :max_by, :module], #enum_max_by
      #[Enumerable, :minmax_by, :module], #enum_minmax_by
      [Enumerable, :member?, :module],
      [Enumerable, :include?, :module],
      #[Enumerable, :each_with_index, :module], #enum_each_with_index
      #[Enumerable, :reverse_each, :module], #enum_reverse_each
      #[Enumerable, :each_entry, :module], #enum_each_entry
      #[Enumerable, :each_slice, :module], #enum_each_slice
      #[Enumerable, :each_cons, :module], #enum_each_cons
      #[Enumerable, :each_with_object, :module], #enum_each_with_object
      #[Enumerable, :zip, :module], #enum_zip => rb_block_given_p
      [Enumerable, :take, :module],
      #[Enumerable, :take_while, :module], #enum_take_while
      [Enumerable, :drop, :module],
      #[Enumerable, :drop_while, :module], #enum_drop_while
      #[Enumerable, :cycle, :module], #enum_cycle
      #[Enumerable, :chunk, :module], #enum_chunk => rb_block_given_p
      #[Enumerable, :slice_before, :module], #enum_slice_before => rb_block_given_p
      [String, :try_convert, :singleton],
      [String, :initialize, :class],
      [String, :initialize_copy, :class],
      [String, :<=>, :class],
      [String, :==, :class],
      [String, :===, :class],
      [String, :eql?, :class],
      [String, :hash, :class],
      [String, :casecmp, :class],
      [String, :+, :class],
      [String, :*, :class],
      [String, :%, :class],
      [String, :[], :class],
      [String, :[]=, :class],
      [String, :insert, :class],
      [String, :length, :class],
      [String, :size, :class],
      [String, :bytesize, :class],
      [String, :empty?, :class],
      [String, :=~, :class],
      #[String, :match, :class], #rb_str_match_m => rb_block_given_p
      [String, :succ, :class],
      [String, :succ!, :class],
      [String, :next, :class],
      [String, :next!, :class],
      #[String, :upto, :class], #rb_str_upto
      [String, :index, :class],
      [String, :rindex, :class],
      [String, :replace, :class],
      [String, :clear, :class],
      [String, :chr, :class],
      [String, :getbyte, :class],
      [String, :setbyte, :class],
      [String, :byteslice, :class],
      [String, :to_i, :class],
      [String, :to_f, :class],
      [String, :to_s, :class],
      [String, :to_str, :class],
      [String, :inspect, :class],
      [String, :dump, :class],
      [String, :upcase, :class],
      [String, :downcase, :class],
      [String, :capitalize, :class],
      [String, :swapcase, :class],
      [String, :upcase!, :class],
      [String, :downcase!, :class],
      [String, :capitalize!, :class],
      [String, :swapcase!, :class],
      [String, :hex, :class],
      [String, :oct, :class],
      [String, :split, :class],
      #[String, :lines, :class], #rb_str_each_line
      #[String, :bytes, :class], #rb_str_each_byte
      #[String, :chars, :class], #rb_str_each_char
      #[String, :codepoints, :class], #rb_str_each_codepoint
      [String, :reverse, :class],
      [String, :reverse!, :class],
      [String, :concat, :class],
      [String, :<<, :class],
      [String, :prepend, :class],
      [String, :crypt, :class],
      [String, :intern, :class],
      [String, :to_sym, :class],
      [String, :ord, :class],
      [String, :include?, :class],
      [String, :start_with?, :class],
      [String, :end_with?, :class],
      #[String, :scan, :class], #rb_str_scan => rb_block_given_p
      [String, :ljust, :class],
      [String, :rjust, :class],
      [String, :center, :class],
      #[String, :sub, :class], #rb_str_sub_bang => rb_block_given_p
      #[String, :gsub, :class], #str_gsub
      [String, :chop, :class],
      [String, :chomp, :class],
      [String, :strip, :class],
      [String, :lstrip, :class],
      [String, :rstrip, :class],
      #[String, :sub!, :class], #rb_str_sub_bang => rb_block_given_p
      #[String, :gsub!, :class], #str_gsub
      [String, :chop!, :class],
      [String, :chomp!, :class],
      [String, :strip!, :class],
      [String, :lstrip!, :class],
      [String, :rstrip!, :class],
      [String, :tr, :class],
      [String, :tr_s, :class],
      [String, :delete, :class],
      [String, :squeeze, :class],
      [String, :count, :class],
      [String, :tr!, :class],
      [String, :tr_s!, :class],
      [String, :delete!, :class],
      [String, :squeeze!, :class],
      #[String, :each_line, :class], #rb_str_each_line
      #[String, :each_byte, :class], #rb_str_each_byte
      #[String, :each_char, :class], #rb_str_each_char
      #[String, :each_codepoint, :class], #rb_str_each_codepoint
      [String, :sum, :class],
      [String, :slice, :class],
      [String, :slice!, :class],
      [String, :partition, :class],
      [String, :rpartition, :class],
      [String, :encoding, :class],
      [String, :force_encoding, :class],
      [String, :valid_encoding?, :class],
      [String, :ascii_only?, :class],
      [Symbol, :all_symbols, :singleton],
      [Symbol, :==, :class],
      [Symbol, :===, :class],
      [Symbol, :inspect, :class],
      [Symbol, :to_s, :class],
      [Symbol, :id2name, :class],
      [Symbol, :intern, :class],
      [Symbol, :to_sym, :class],
      [Symbol, :to_proc, :class],
      [Symbol, :succ, :class],
      [Symbol, :next, :class],
      [Symbol, :<=>, :class],
      [Symbol, :casecmp, :class],
      [Symbol, :=~, :class],
      [Symbol, :[], :class],
      [Symbol, :slice, :class],
      [Symbol, :length, :class],
      [Symbol, :size, :class],
      [Symbol, :empty?, :class],
      [Symbol, :match, :class],
      [Symbol, :upcase, :class],
      [Symbol, :downcase, :class],
      [Symbol, :capitalize, :class],
      [Symbol, :swapcase, :class],
      [Symbol, :encoding, :class],
      [Exception, :exception, :singleton],
      [Exception, :exception, :class],
      [Exception, :initialize, :class],
      [Exception, :==, :class],
      [Exception, :to_s, :class],
      [Exception, :message, :class],
      [Exception, :inspect, :class],
      [Exception, :backtrace, :class],
      [Exception, :set_backtrace, :class],
      #[SystemExit, :initialize, :class], #rb_call_super => vm_call_super
      [SystemExit, :status, :class],
      [SystemExit, :success?, :class],
      #[NameError, :initialize, :class], #rb_call_super => vm_call_super
      [NameError, :name, :class],
      [NameError, :to_s, :class],
      #[NameError::message, :==, :class],
      #[NameError::message, :to_str, :class],
      #[NameError::message, :_dump, :class],
      #[NoMethodError, :initialize, :class], #rb_call_super => vm_call_super
      [NoMethodError, :args, :class],
      #[SystemCallError, :initialize, :class], #rb_call_super => vm_call_super
      [SystemCallError, :errno, :class],
      [SystemCallError, :===, :singleton],
      [Kernel, :warn, :module],
      [Kernel, :warn, :singleton],
      [Kernel, :raise, :module],
      [Kernel, :raise, :singleton],
      [Kernel, :fail, :module],
      [Kernel, :fail, :singleton],
      [Kernel, :global_variables, :module],
      [Kernel, :global_variables, :singleton],
      [Kernel, :__method__, :module],
      [Kernel, :__method__, :singleton],
      [Kernel, :__callee__, :module],
      [Kernel, :__callee__, :singleton],
      [Module, :append_features, :class],
      [Module, :extend_object, :class],
      [Module, :include, :class],
      [Kernel, :eval, :module],
      [Kernel, :eval, :singleton],
      [Kernel, :local_variables, :module],
      [Kernel, :local_variables, :singleton],
      [Kernel, :iterator?, :module],
      [Kernel, :iterator?, :singleton],
      [Kernel, :block_given?, :module],
      [Kernel, :block_given?, :singleton],
      [Kernel, :catch, :module],
      [Kernel, :catch, :singleton],
      [Kernel, :throw, :module],
      [Kernel, :throw, :singleton],
      #[Kernel, :loop, :module], #rb_f_loop
      #[Kernel, :loop, :singleton], #rb_f_loop
      [BasicObject, :instance_eval, :class],
      [BasicObject, :instance_exec, :class],
      [BasicObject, :method_missing, :class],
      [Kernel, :public_send, :module],
      [Module, :module_exec, :class],
      [Module, :class_exec, :class],
      [Module, :module_eval, :class],
      [Module, :class_eval, :class],
      [Kernel, :caller, :module],
      [Kernel, :caller, :singleton],
      [Kernel, :respond_to?, :module],
      [Kernel, :respond_to_missing?, :module],
      [Module, :remove_method, :class],
      [Module, :undef_method, :class],
      [Module, :alias_method, :class],
      [Module, :public, :class],
      [Module, :protected, :class],
      [Module, :private, :class],
      [Module, :module_function, :class],
      [Module, :method_defined?, :class],
      [Module, :public_method_defined?, :class],
      [Module, :private_method_defined?, :class],
      [Module, :protected_method_defined?, :class],
      [Module, :public_class_method, :class],
      [Module, :private_class_method, :class],
      [Module, :nesting, :singleton],
      [Module, :constants, :singleton],
      [Kernel, :extend, :module],
      [Kernel, :trace_var, :module],
      [Kernel, :trace_var, :singleton],
      [Kernel, :untrace_var, :module],
      [Kernel, :untrace_var, :singleton],
      #[Kernel, :at_exit, :module], #rb_f_at_exit
      #[Kernel, :at_exit, :singleton], #rb_f_at_exit
      [Numeric, :singleton_method_added, :class],
      [Numeric, :initialize_copy, :class],
      [Numeric, :coerce, :class],
      [Numeric, :i, :class],
      [Numeric, :+@, :class],
      [Numeric, :-@, :class],
      [Numeric, :<=>, :class],
      [Numeric, :eql?, :class],
      [Numeric, :quo, :class],
      [Numeric, :fdiv, :class],
      [Numeric, :div, :class],
      [Numeric, :divmod, :class],
      [Numeric, :%, :class],
      [Numeric, :modulo, :class],
      [Numeric, :remainder, :class],
      [Numeric, :abs, :class],
      [Numeric, :magnitude, :class],
      [Numeric, :to_int, :class],
      [Numeric, :real?, :class],
      [Numeric, :integer?, :class],
      [Numeric, :zero?, :class],
      [Numeric, :nonzero?, :class],
      [Numeric, :floor, :class],
      [Numeric, :ceil, :class],
      [Numeric, :round, :class],
      [Numeric, :truncate, :class],
      #[Numeric, :step, :class], #num_step
      [Integer, :integer?, :class],
      [Integer, :odd?, :class],
      [Integer, :even?, :class],
      #[Integer, :upto, :class], #int_upto
      #[Integer, :downto, :class], #int_downto
      #[Integer, :times, :class], #int_dotimes
      [Integer, :succ, :class],
      [Integer, :next, :class],
      [Integer, :pred, :class],
      [Integer, :chr, :class],
      [Integer, :ord, :class],
      [Integer, :to_i, :class],
      [Integer, :to_int, :class],
      [Integer, :floor, :class],
      [Integer, :ceil, :class],
      [Integer, :truncate, :class],
      [Integer, :round, :class],
      [Fixnum, :to_s, :class],
      [Fixnum, :-@, :class],
      [Fixnum, :+, :class],
      [Fixnum, :-, :class],
      [Fixnum, :*, :class],
      [Fixnum, :/, :class],
      [Fixnum, :div, :class],
      [Fixnum, :%, :class],
      [Fixnum, :modulo, :class],
      [Fixnum, :divmod, :class],
      [Fixnum, :fdiv, :class],
      [Fixnum, :**, :class],
      [Fixnum, :abs, :class],
      [Fixnum, :magnitude, :class],
      [Fixnum, :==, :class],
      [Fixnum, :===, :class],
      [Fixnum, :<=>, :class],
      [Fixnum, :>, :class],
      [Fixnum, :>=, :class],
      [Fixnum, :<, :class],
      [Fixnum, :<=, :class],
      [Fixnum, :~, :class],
      [Fixnum, :&, :class],
      [Fixnum, :|, :class],
      [Fixnum, :^, :class],
      [Fixnum, :[], :class],
      [Fixnum, :<<, :class],
      [Fixnum, :>>, :class],
      [Fixnum, :to_f, :class],
      [Fixnum, :size, :class],
      [Fixnum, :zero?, :class],
      [Fixnum, :odd?, :class],
      [Fixnum, :even?, :class],
      [Fixnum, :succ, :class],
      [Float, :to_s, :class],
      [Float, :coerce, :class],
      [Float, :-@, :class],
      [Float, :+, :class],
      [Float, :-, :class],
      [Float, :*, :class],
      [Float, :/, :class],
      [Float, :quo, :class],
      [Float, :fdiv, :class],
      [Float, :%, :class],
      [Float, :modulo, :class],
      [Float, :divmod, :class],
      [Float, :**, :class],
      [Float, :==, :class],
      [Float, :===, :class],
      [Float, :<=>, :class],
      [Float, :>, :class],
      [Float, :>=, :class],
      [Float, :<, :class],
      [Float, :<=, :class],
      [Float, :eql?, :class],
      [Float, :hash, :class],
      [Float, :to_f, :class],
      [Float, :abs, :class],
      [Float, :magnitude, :class],
      [Float, :zero?, :class],
      [Float, :to_i, :class],
      [Float, :to_int, :class],
      [Float, :floor, :class],
      [Float, :ceil, :class],
      [Float, :round, :class],
      [Float, :truncate, :class],
      [Float, :nan?, :class],
      [Float, :infinite?, :class],
      [Float, :finite?, :class],
      [Bignum, :to_s, :class],
      [Bignum, :coerce, :class],
      [Bignum, :-@, :class],
      [Bignum, :+, :class],
      [Bignum, :-, :class],
      [Bignum, :*, :class],
      [Bignum, :/, :class],
      [Bignum, :%, :class],
      [Bignum, :div, :class],
      [Bignum, :divmod, :class],
      [Bignum, :modulo, :class],
      [Bignum, :remainder, :class],
      [Bignum, :fdiv, :class],
      [Bignum, :**, :class],
      [Bignum, :&, :class],
      [Bignum, :|, :class],
      [Bignum, :^, :class],
      [Bignum, :~, :class],
      [Bignum, :<<, :class],
      [Bignum, :>>, :class],
      [Bignum, :[], :class],
      [Bignum, :<=>, :class],
      [Bignum, :==, :class],
      [Bignum, :>, :class],
      [Bignum, :>=, :class],
      [Bignum, :<, :class],
      [Bignum, :<=, :class],
      [Bignum, :===, :class],
      [Bignum, :eql?, :class],
      [Bignum, :hash, :class],
      [Bignum, :to_f, :class],
      [Bignum, :abs, :class],
      [Bignum, :magnitude, :class],
      [Bignum, :size, :class],
      [Bignum, :odd?, :class],
      [Bignum, :even?, :class],
      [Array, :[], :singleton],
      [Array, :try_convert, :singleton],
      #[Array, :initialize, :class], #rb_ary_initialize => rb_block_given_p
      [Array, :initialize_copy, :class],
      #[Array, :inspect, :class], #rb_exec_recursive => recursive_list_access
      [Array, :to_a, :class],
      [Array, :to_ary, :class],
      [Array, :frozen?, :class],
      #[Array, :==, :class], #rb_exec_recursive => recursive_list_access
      #[Array, :eql?, :class], #rb_exec_recursive => recursive_list_access
      #[Array, :hash, :class], #rb_exec_recursive_outer => recursive_list_access
      [Array, :[], :class],
      [Array, :[]=, :class],
      [Array, :at, :class],
      #[Array, :fetch, :class], #rb_ary_fetch => rb_block_given_p
      [Array, :first, :class],
      [Array, :last, :class],
      [Array, :concat, :class],
      [Array, :<<, :class],
      [Array, :push, :class],
      [Array, :pop, :class],
      [Array, :shift, :class],
      [Array, :unshift, :class],
      [Array, :insert, :class],
      #[Array, :each, :class], #rb_ary_each
      #[Array, :each_index, :class], #rb_ary_each_index
      #[Array, :reverse_each, :class], #rb_ary_reverse_each
      [Array, :length, :class],
      [Array, :empty?, :class],
      #[Array, :find_index, :class], #rb_ary_index => rb_block_given_p
      #[Array, :index, :class], #rb_ary_index => rb_block_given_p
      #[Array, :rindex, :class], #rb_ary_rindex => rb_block_given_p
      #[Array, :join, :class], #rb_exec_recursive => recursive_list_access
      [Array, :reverse, :class],
      [Array, :reverse!, :class],
      [Array, :rotate, :class],
      [Array, :rotate!, :class],
      #[Array, :sort, :class], #rb_ary_sort_bang => rb_block_given_p
      #[Array, :sort!, :class], #rb_ary_sort_bang => rb_block_given_p
      #[Array, :sort_by!, :class], #rb_ary_sort_by_bang
      #[Array, :collect, :class], #rb_ary_collect
      #[Array, :collect!, :class], #rb_ary_collect_bang
      #[Array, :map, :class], #rb_ary_collect
      #[Array, :map!, :class], #rb_ary_collect_bang
      #[Array, :select, :class], #rb_ary_select
      #[Array, :select!, :class], #rb_ary_select_bang
      #[Array, :keep_if, :class], #rb_ary_keep_if
      [Array, :values_at, :class],
      #[Array, :delete, :class], #rb_ary_delete => rb_block_given_p
      [Array, :delete_at, :class],
      #[Array, :delete_if, :class], #rb_ary_delete_if
      #[Array, :reject, :class], #rb_ary_reject
      #[Array, :reject!, :class], #rb_ary_reject_bang
      #[Array, :zip, :class], #rb_ary_zip => rb_block_given_p
      [Array, :transpose, :class],
      [Array, :replace, :class],
      [Array, :clear, :class],
      #[Array, :fill, :class], #rb_ary_fill => rb_block_given_p
      [Array, :include?, :class],
      #[Array, :<=>, :class], #rb_exec_recursive => recursive_list_access
      [Array, :slice, :class],
      [Array, :slice!, :class],
      [Array, :assoc, :class],
      [Array, :rassoc, :class],
      [Array, :+, :class],
      [Array, :*, :class],
      [Array, :-, :class],
      [Array, :&, :class],
      [Array, :|, :class],
      #[Array, :uniq, :class], #rb_ary_uniq => rb_block_given_p
      #[Array, :uniq!, :class], #rb_ary_uniq_bang => rb_block_given_p
      [Array, :compact, :class],
      [Array, :compact!, :class],
      [Array, :flatten, :class],
      [Array, :flatten!, :class],
      #[Array, :count, :class], #rb_ary_count => rb_block_given_p
      [Array, :shuffle!, :class],
      [Array, :shuffle, :class],
      [Array, :sample, :class],
      #[Array, :cycle, :class], #rb_ary_cycle
      #[Array, :permutation, :class], #rb_ary_permutation
      #[Array, :combination, :class], #rb_ary_combination
      #[Array, :repeated_permutation, :class], #rb_ary_repeated_permutation
      #[Array, :repeated_combination, :class], #rb_ary_repeated_combination
      #[Array, :product, :class], #rb_ary_product => rb_block_given_p
      [Array, :take, :class],
      #[Array, :take_while, :class], #rb_ary_take_while
      [Array, :drop, :class],
      #[Array, :drop_while, :class], #rb_ary_drop_while
      [Hash, :[], :singleton],
      [Hash, :try_convert, :singleton],
      #[Hash, :initialize, :class], #rb_hash_initialize => rb_block_given_p
      [Hash, :initialize_copy, :class],
      [Hash, :rehash, :class],
      [Hash, :to_hash, :class],
      [Hash, :to_a, :class],
      #[Hash, :inspect, :class], #rb_exec_recursive => recursive_list_access
      #[Hash, :==, :class], #rb_exec_recursive_paired => recursive_list_access
      [Hash, :[], :class],
      #[Hash, :hash, :class], #rb_exec_recursive_outer => recursive_list_access
      #[Hash, :eql?, :class], #rb_exec_recursive_paired => recursive_list_access
      #[Hash, :fetch, :class], #rb_hash_fetch_m => rb_block_given_p
      [Hash, :[]=, :class],
      [Hash, :store, :class],
      [Hash, :default, :class],
      [Hash, :default=, :class],
      [Hash, :default_proc, :class],
      [Hash, :default_proc=, :class],
      [Hash, :key, :class],
      [Hash, :index, :class],
      [Hash, :size, :class],
      [Hash, :length, :class],
      [Hash, :empty?, :class],
      #[Hash, :each_value, :class], #rb_hash_each_value
      #[Hash, :each_key, :class], #rb_hash_each_key
      #[Hash, :each_pair, :class], #rb_hash_each_pair
      #[Hash, :each, :class], #rb_hash_each_pair
      [Hash, :keys, :class],
      [Hash, :values, :class],
      [Hash, :values_at, :class],
      [Hash, :shift, :class],
      #[Hash, :delete, :class], #rb_hash_delete => rb_block_given_p
      #[Hash, :delete_if, :class], #rb_hash_delete_if
      #[Hash, :keep_if, :class], #rb_hash_keep_if
      #[Hash, :select, :class], #rb_hash_select
      #[Hash, :select!, :class], #rb_hash_select_bang
      #[Hash, :reject, :class], #rb_hash_reject => rb_hash_delete_if
      #[Hash, :reject!, :class], #rb_hash_reject_bang
      [Hash, :clear, :class],
      [Hash, :invert, :class],
      #[Hash, :update, :class], #rb_hash_update => rb_block_given_p
      [Hash, :replace, :class],
      #[Hash, :merge!, :class], #rb_hash_update => rb_block_given_p
      #[Hash, :merge, :class], #rb_hash_merge => rb_hash_update => rb_block_given_p
      [Hash, :assoc, :class],
      [Hash, :rassoc, :class],
      [Hash, :flatten, :class],
      [Hash, :include?, :class],
      [Hash, :member?, :class],
      [Hash, :has_key?, :class],
      [Hash, :has_value?, :class],
      [Hash, :key?, :class],
      [Hash, :value?, :class],
      [Hash, :compare_by_identity, :class],
      [Hash, :compare_by_identity?, :class],
      #[Struct, :new, :singleton], #rb_struct_s_def => rb_block_given_p
      [Struct, :initialize, :class],
      [Struct, :initialize_copy, :class],
      #[Struct, :==, :class], #rb_exec_recursive_paired => recursive_list_access
      #[Struct, :eql?, :class], #rb_exec_recursive_paired => recursive_list_access
      #[Struct, :hash, :class], #rb_exec_recursive_outer => recursive_list_access
      #[Struct, :inspect, :class], #rb_exec_recursive => recursive_list_access
      [Struct, :to_a, :class],
      [Struct, :values, :class],
      [Struct, :size, :class],
      [Struct, :length, :class],
      #[Struct, :each, :class], #rb_struct_each
      #[Struct, :each_pair, :class], #rb_struct_each_pair
      [Struct, :[], :class],
      [Struct, :[]=, :class],
      #[Struct, :select, :class], #rb_struct_select
      [Struct, :values_at, :class],
      [Struct, :members, :class],
      [Regexp, :compile, :singleton],
      [Regexp, :quote, :singleton],
      [Regexp, :escape, :singleton],
      [Regexp, :union, :singleton],
      [Regexp, :last_match, :singleton],
      [Regexp, :try_convert, :singleton],
      [Regexp, :initialize, :class],
      [Regexp, :initialize_copy, :class],
      [Regexp, :hash, :class],
      [Regexp, :eql?, :class],
      [Regexp, :==, :class],
      [Regexp, :=~, :class],
      [Regexp, :===, :class],
      [Regexp, :~, :class],
      #[Regexp, :match, :class], #rb_reg_match_m => rb_block_given_p
      [Regexp, :to_s, :class],
      [Regexp, :inspect, :class],
      [Regexp, :source, :class],
      [Regexp, :casefold?, :class],
      [Regexp, :options, :class],
      [Regexp, :encoding, :class],
      [Regexp, :fixed_encoding?, :class],
      [Regexp, :names, :class],
      [Regexp, :named_captures, :class],
      [MatchData, :initialize_copy, :class],
      [MatchData, :regexp, :class],
      [MatchData, :names, :class],
      [MatchData, :size, :class],
      [MatchData, :length, :class],
      [MatchData, :offset, :class],
      [MatchData, :begin, :class],
      [MatchData, :end, :class],
      [MatchData, :to_a, :class],
      [MatchData, :[], :class],
      [MatchData, :captures, :class],
      [MatchData, :values_at, :class],
      [MatchData, :pre_match, :class],
      [MatchData, :post_match, :class],
      [MatchData, :to_s, :class],
      [MatchData, :inspect, :class],
      [MatchData, :string, :class],
      [MatchData, :hash, :class],
      [MatchData, :eql?, :class],
      [MatchData, :==, :class],
      [Array, :pack, :class],
      #[String, :unpack, :class], #pack_unpack => rb_block_given_p
      [String, :encode, :class],
      [String, :encode!, :class],
      [Encoding::Converter, :initialize, :class],
      [Encoding::Converter, :inspect, :class],
      [Encoding::Converter, :convpath, :class],
      [Encoding::Converter, :source_encoding, :class],
      [Encoding::Converter, :destination_encoding, :class],
      [Encoding::Converter, :primitive_convert, :class],
      [Encoding::Converter, :convert, :class],
      [Encoding::Converter, :finish, :class],
      [Encoding::Converter, :primitive_errinfo, :class],
      [Encoding::Converter, :insert_output, :class],
      [Encoding::Converter, :putback, :class],
      [Encoding::Converter, :last_error, :class],
      [Encoding::Converter, :replacement, :class],
      [Encoding::Converter, :replacement=, :class],
      [Encoding::UndefinedConversionError, :source_encoding_name, :class],
      [Encoding::UndefinedConversionError, :destination_encoding_name, :class],
      [Encoding::UndefinedConversionError, :source_encoding, :class],
      [Encoding::UndefinedConversionError, :destination_encoding, :class],
      [Encoding::UndefinedConversionError, :error_char, :class],
      [Encoding::InvalidByteSequenceError, :source_encoding_name, :class],
      [Encoding::InvalidByteSequenceError, :destination_encoding_name, :class],
      [Encoding::InvalidByteSequenceError, :source_encoding, :class],
      [Encoding::InvalidByteSequenceError, :destination_encoding, :class],
      [Encoding::InvalidByteSequenceError, :error_bytes, :class],
      [Encoding::InvalidByteSequenceError, :readagain_bytes, :class],
      [Encoding::InvalidByteSequenceError, :incomplete_input?, :class],
      [Marshal, :dump, :module],
      [Marshal, :dump, :singleton],
      [Marshal, :load, :module],
      [Marshal, :load, :singleton],
      [Marshal, :restore, :module],
      [Marshal, :restore, :singleton],
      [Range, :initialize, :class],
      [Range, :initialize_copy, :class],
      #[Range, :==, :class], #rb_exec_recursive_paired => recursive_list_access
      [Range, :===, :class],
      #[Range, :eql?, :class], #rb_exec_recursive_paired => recursive_list_access
      #[Range, :hash, :class], #rb_exec_recursive_outer => recursive_list_access
      #[Range, :each, :class], #range_each
      #[Range, :step, :class], #range_step
      [Range, :begin, :class],
      [Range, :end, :class],
      [Range, :first, :class],
      [Range, :last, :class],
      #[Range, :min, :class], #rb_call_super => vm_call_super, range_min => rb_block_given_p
      #[Range, :max, :class], #rb_call_super => vm_call_super, range_max => rb_block_given_p
      [Range, :to_s, :class],
      #[Range, :inspect, :class], #rb_exec_recursive => recursive_list_access
      [Range, :exclude_end?, :class],
      #[Range, :member?, :class], #rb_call_super => vm_call_super
      #[Range, :include?, :class], #rb_call_super => vm_call_super
      [Range, :cover?, :class],
      [Kernel, :syscall, :module],
      [Kernel, :syscall, :singleton],
      #[Kernel, :open, :module], #rb_f_open => rb_block_given_p
      #[Kernel, :open, :singleton], #rb_f_open => rb_block_given_p
      [Kernel, :printf, :module],
      [Kernel, :printf, :singleton],
      [Kernel, :print, :module],
      [Kernel, :print, :singleton],
      [Kernel, :putc, :module],
      [Kernel, :putc, :singleton],
      #[Kernel, :puts, :module], #rb_io_puts => rb_exec_recursive => recursive_list_access
      #[Kernel, :puts, :singleton], #rb_io_puts => rb_exec_recursive => recursive_list_access
      [Kernel, :gets, :module],
      [Kernel, :gets, :singleton],
      [Kernel, :readline, :module],
      [Kernel, :readline, :singleton],
      [Kernel, :select, :module],
      [Kernel, :select, :singleton],
      [Kernel, :readlines, :module],
      [Kernel, :readlines, :singleton],
      [Kernel, :`, :module],
      [Kernel, :`, :singleton],
      [Kernel, :p, :module],
      [Kernel, :p, :singleton],
      [Kernel, :display, :module],
      #[IO, :new, :singleton], #rb_io_s_new => rb_block_given_p
      #[IO, :open, :singleton], #rb_io_s_open => rb_block_given_p
      [IO, :sysopen, :singleton],
      [IO, :for_fd, :singleton],
      #[IO, :popen, :singleton],  #rb_io_s_popen => rb_block_given_p
      #[IO, :foreach, :singleton], #rb_io_s_foreach
      [IO, :readlines, :singleton],
      [IO, :read, :singleton],
      [IO, :binread, :singleton],
      [IO, :write, :singleton],
      [IO, :binwrite, :singleton],
      [IO, :select, :singleton],
      #[IO, :pipe, :singleton], #rb_io_s_pipe => rb_block_given_p
      [IO, :try_convert, :singleton],
      [IO, :copy_stream, :singleton],
      [IO, :initialize, :class],
      [IO, :initialize_copy, :class],
      [IO, :reopen, :class],
      [IO, :print, :class],
      [IO, :putc, :class],
      #[IO, :puts, :class], #rb_exec_recursive => recursive_list_access
      [IO, :printf, :class],
      #[IO, :each, :class], #rb_io_each_line
      #[IO, :each_line, :class], #rb_io_each_line
      #[IO, :each_byte, :class], #rb_io_each_byte
      #[IO, :each_char, :class], #rb_io_each_char
      #[IO, :each_codepoint, :class], #rb_io_each_codepoint
      #[IO, :lines, :class], #rb_io_each_line
      #[IO, :bytes, :class], #rb_io_each_byte
      #[IO, :chars, :class], #rb_io_each_char
      #[IO, :codepoints, :class], #rb_io_each_codepoint
      [IO, :syswrite, :class],
      [IO, :sysread, :class],
      [IO, :fileno, :class],
      [IO, :to_io, :class],
      [IO, :fsync, :class],
      [IO, :fdatasync, :class],
      [IO, :sync, :class],
      [IO, :sync=, :class],
      [IO, :lineno, :class],
      [IO, :lineno=, :class],
      [IO, :readlines, :class],
      [IO, :read_nonblock, :class],
      [IO, :write_nonblock, :class],
      [IO, :readpartial, :class],
      [IO, :read, :class],
      [IO, :write, :class],
      [IO, :gets, :class],
      [IO, :readline, :class],
      [IO, :getc, :class],
      [IO, :getbyte, :class],
      [IO, :readchar, :class],
      [IO, :readbyte, :class],
      [IO, :ungetbyte, :class],
      [IO, :ungetc, :class],
      [IO, :<<, :class],
      [IO, :flush, :class],
      [IO, :tell, :class],
      [IO, :seek, :class],
      [IO, :rewind, :class],
      [IO, :pos, :class],
      [IO, :pos=, :class],
      [IO, :eof, :class],
      [IO, :eof?, :class],
      [IO, :close_on_exec?, :class],
      [IO, :close_on_exec=, :class],
      [IO, :close, :class],
      [IO, :closed?, :class],
      [IO, :close_read, :class],
      [IO, :close_write, :class],
      [IO, :isatty, :class],
      [IO, :tty?, :class],
      [IO, :binmode, :class],
      [IO, :binmode?, :class],
      [IO, :sysseek, :class],
      [IO, :advise, :class],
      [IO, :ioctl, :class],
      [IO, :fcntl, :class],
      [IO, :pid, :class],
      [IO, :inspect, :class],
      [IO, :external_encoding, :class],
      [IO, :internal_encoding, :class],
      [IO, :set_encoding, :class],
      [IO, :autoclose?, :class],
      [IO, :autoclose=, :class],
      #[ARGF, :initialize, :class], 
      #[ARGF, :initialize_copy, :class],
      #[ARGF, :to_s, :class],
      #[ARGF, :argv, :class],
      #[ARGF, :fileno, :class], #argf_fileno
      #[ARGF, :to_i, :class],
      #[ARGF, :to_io, :class], #argf_to_io
      #[ARGF, :to_write_io, :class],
      #[ARGF, :each, :class], #argf_each_line
      #[ARGF, :each_line, :class], #argf_each_line
      #[ARGF, :each_byte, :class], #argf_each_byte
      #[ARGF, :each_char, :class], #argf_each_char
      #[ARGF, :lines, :class], #argf_each_line
      #[ARGF, :bytes, :class], #argf_each_byte
      #[ARGF, :chars, :class], #argf_each_char
      #[ARGF, :read, :class], #argf_read
      #[ARGF, :readpartial, :class], #argf_readpartial
      #[ARGF, :read_nonblock, :class], #argf_read_nonblock
      #[ARGF, :readlines, :class],
      #[ARGF, :to_a, :class],
      #[ARGF, :gets, :class],
      #[ARGF, :readline, :class], #argf_readline
      #[ARGF, :getc, :class],
      #[ARGF, :getbyte, :class],
      #[ARGF, :readchar, :class],
      #[ARGF, :readbyte, :class], #argf_readbyte
      #[ARGF, :tell, :class], #argf_tell
      #[ARGF, :seek, :class], #argf_seek_m
      #[ARGF, :rewind, :class], #argf_rewind
      #[ARGF, :pos, :class], #argf_tell
      #[ARGF, :pos=, :class], #argf_set_pos
      #[ARGF, :eof, :class], #argf_eof
      #[ARGF, :eof?, :class], #argf_eof
      #[ARGF, :binmode, :class], #argf_binmode_m
      #[ARGF, :binmode?, :class],
      #[ARGF, :write, :class],
      #[ARGF, :print, :class],
      #[ARGF, :putc, :class],
      #[ARGF, :puts, :class], #rb_exec_recursive => recursive_list_access
      #[ARGF, :printf, :class],
      #[ARGF, :filename, :class],
      #[ARGF, :path, :class],
      #[ARGF, :file, :class],
      #[ARGF, :skip, :class],
      #[ARGF, :close, :class],
      #[ARGF, :closed?, :class], #argf_closed
      #[ARGF, :lineno, :class],
      #[ARGF, :lineno=, :class],
      #[ARGF, :inplace_mode, :class],
      #[ARGF, :inplace_mode=, :class],
      #[ARGF, :external_encoding, :class],
      #[ARGF, :internal_encoding, :class],
      #[ARGF, :set_encoding, :class],
      [FileTest, :directory?, :module],
      [FileTest, :directory?, :singleton],
      [File, :directory?, :singleton],
      [FileTest, :exist?, :module],
      [FileTest, :exist?, :singleton],
      [File, :exist?, :singleton],
      [FileTest, :exists?, :module],
      [FileTest, :exists?, :singleton],
      [File, :exists?, :singleton],
      [FileTest, :readable?, :module],
      [FileTest, :readable?, :singleton],
      [File, :readable?, :singleton],
      [FileTest, :readable_real?, :module],
      [FileTest, :readable_real?, :singleton],
      [File, :readable_real?, :singleton],
      [FileTest, :world_readable?, :module],
      [FileTest, :world_readable?, :singleton],
      [File, :world_readable?, :singleton],
      [FileTest, :writable?, :module],
      [FileTest, :writable?, :singleton],
      [File, :writable?, :singleton],
      [FileTest, :writable_real?, :module],
      [FileTest, :writable_real?, :singleton],
      [File, :writable_real?, :singleton],
      [FileTest, :world_writable?, :module],
      [FileTest, :world_writable?, :singleton],
      [File, :world_writable?, :singleton],
      [FileTest, :executable?, :module],
      [FileTest, :executable?, :singleton],
      [File, :executable?, :singleton],
      [FileTest, :executable_real?, :module],
      [FileTest, :executable_real?, :singleton],
      [File, :executable_real?, :singleton],
      [FileTest, :file?, :module],
      [FileTest, :file?, :singleton],
      [File, :file?, :singleton],
      [FileTest, :zero?, :module],
      [FileTest, :zero?, :singleton],
      [File, :zero?, :singleton],
      [FileTest, :size?, :module],
      [FileTest, :size?, :singleton],
      [File, :size?, :singleton],
      [FileTest, :size, :module],
      [FileTest, :size, :singleton],
      [File, :size, :singleton],
      [FileTest, :owned?, :module],
      [FileTest, :owned?, :singleton],
      [File, :owned?, :singleton],
      [FileTest, :grpowned?, :module],
      [FileTest, :grpowned?, :singleton],
      [File, :grpowned?, :singleton],
      [FileTest, :pipe?, :module],
      [FileTest, :pipe?, :singleton],
      [File, :pipe?, :singleton],
      [FileTest, :symlink?, :module],
      [FileTest, :symlink?, :singleton],
      [File, :symlink?, :singleton],
      [FileTest, :socket?, :module],
      [FileTest, :socket?, :singleton],
      [File, :socket?, :singleton],
      [FileTest, :blockdev?, :module],
      [FileTest, :blockdev?, :singleton],
      [File, :blockdev?, :singleton],
      [FileTest, :chardev?, :module],
      [FileTest, :chardev?, :singleton],
      [File, :chardev?, :singleton],
      [FileTest, :setuid?, :module],
      [FileTest, :setuid?, :singleton],
      [File, :setuid?, :singleton],
      [FileTest, :setgid?, :module],
      [FileTest, :setgid?, :singleton],
      [File, :setgid?, :singleton],
      [FileTest, :sticky?, :module],
      [FileTest, :sticky?, :singleton],
      [File, :sticky?, :singleton],
      [FileTest, :identical?, :module],
      [FileTest, :identical?, :singleton],
      [File, :identical?, :singleton],
      [File, :stat, :singleton],
      [File, :lstat, :singleton],
      [File, :ftype, :singleton],
      [File, :atime, :singleton],
      [File, :mtime, :singleton],
      [File, :ctime, :singleton],
      [File, :utime, :singleton],
      [File, :chmod, :singleton],
      [File, :chown, :singleton],
      [File, :lchmod, :singleton],
      [File, :lchown, :singleton],
      [File, :link, :singleton],
      [File, :symlink, :singleton],
      [File, :readlink, :singleton],
      [File, :unlink, :singleton],
      [File, :delete, :singleton],
      [File, :rename, :singleton],
      [File, :umask, :singleton],
      [File, :truncate, :singleton],
      [File, :expand_path, :singleton],
      [File, :absolute_path, :singleton],
      [File, :realpath, :singleton],
      [File, :realdirpath, :singleton],
      [File, :basename, :singleton],
      [File, :dirname, :singleton],
      [File, :extname, :singleton],
      [File, :path, :singleton],
      [File, :split, :singleton],
      #[File, :join, :singleton], #rb_exec_recursive => recursive_list_access
      [IO, :stat, :class],
      [File, :lstat, :class],
      [File, :atime, :class],
      [File, :mtime, :class],
      [File, :ctime, :class],
      [File, :size, :class],
      [File, :chmod, :class],
      [File, :chown, :class],
      [File, :truncate, :class],
      [File, :flock, :class],
      [File, :path, :class],
      [File, :to_path, :class],
      [Kernel, :test, :module],
      [Kernel, :test, :singleton],
      [File::Stat, :initialize, :class],
      [File::Stat, :initialize_copy, :class],
      [File::Stat, :<=>, :class],
      [File::Stat, :dev, :class],
      [File::Stat, :dev_major, :class],
      [File::Stat, :dev_minor, :class],
      [File::Stat, :ino, :class],
      [File::Stat, :mode, :class],
      [File::Stat, :nlink, :class],
      [File::Stat, :uid, :class],
      [File::Stat, :gid, :class],
      [File::Stat, :rdev, :class],
      [File::Stat, :rdev_major, :class],
      [File::Stat, :rdev_minor, :class],
      [File::Stat, :size, :class],
      [File::Stat, :blksize, :class],
      [File::Stat, :blocks, :class],
      [File::Stat, :atime, :class],
      [File::Stat, :mtime, :class],
      [File::Stat, :ctime, :class],
      [File::Stat, :inspect, :class],
      [File::Stat, :ftype, :class],
      [File::Stat, :directory?, :class],
      [File::Stat, :readable?, :class],
      [File::Stat, :readable_real?, :class],
      [File::Stat, :world_readable?, :class],
      [File::Stat, :writable?, :class],
      [File::Stat, :writable_real?, :class],
      [File::Stat, :world_writable?, :class],
      [File::Stat, :executable?, :class],
      [File::Stat, :executable_real?, :class],
      [File::Stat, :file?, :class],
      [File::Stat, :zero?, :class],
      [File::Stat, :size?, :class],
      [File::Stat, :owned?, :class],
      [File::Stat, :grpowned?, :class],
      [File::Stat, :pipe?, :class],
      [File::Stat, :symlink?, :class],
      [File::Stat, :socket?, :class],
      [File::Stat, :blockdev?, :class],
      [File::Stat, :chardev?, :class],
      [File::Stat, :setuid?, :class],
      [File::Stat, :setgid?, :class],
      [File::Stat, :sticky?, :class],
      [File, :initialize, :class],
      #[Dir, :open, :singleton], #dir_s_open => rb_block_given_p
      #[Dir, :foreach, :singleton], #dir_foreach
      [Dir, :entries, :singleton],
      [Dir, :initialize, :class],
      [Dir, :path, :class],
      [Dir, :to_path, :class],
      [Dir, :inspect, :class],
      [Dir, :read, :class],
      #[Dir, :each, :class], #dir_each
      [Dir, :rewind, :class],
      [Dir, :tell, :class],
      [Dir, :seek, :class],
      [Dir, :pos, :class],
      [Dir, :pos=, :class],
      [Dir, :close, :class],
      #[Dir, :chdir, :singleton], #dir_s_chdir => rb_block_given_p
      [Dir, :getwd, :singleton],
      [Dir, :pwd, :singleton],
      [Dir, :chroot, :singleton],
      [Dir, :mkdir, :singleton],
      [Dir, :rmdir, :singleton],
      [Dir, :delete, :singleton],
      [Dir, :unlink, :singleton],
      [Dir, :home, :singleton],
      #[Dir, :glob, :singleton], #dir_s_glob => rb_block_given_p
      [Dir, :[], :singleton],
      [Dir, :exist?, :singleton],
      [Dir, :exists?, :singleton],
      [File, :fnmatch, :singleton],
      [File, :fnmatch?, :singleton],
      [Time, :now, :singleton],
      [Time, :at, :singleton],
      [Time, :utc, :singleton],
      [Time, :gm, :singleton],
      [Time, :local, :singleton],
      [Time, :mktime, :singleton],
      [Time, :to_i, :class],
      [Time, :to_f, :class],
      [Time, :to_r, :class],
      [Time, :<=>, :class],
      [Time, :eql?, :class],
      [Time, :hash, :class],
      [Time, :initialize, :class],
      [Time, :initialize_copy, :class],
      [Time, :localtime, :class],
      [Time, :gmtime, :class],
      [Time, :utc, :class],
      [Time, :getlocal, :class],
      [Time, :getgm, :class],
      [Time, :getutc, :class],
      [Time, :ctime, :class],
      [Time, :asctime, :class],
      [Time, :to_s, :class],
      [Time, :inspect, :class],
      [Time, :to_a, :class],
      [Time, :+, :class],
      [Time, :-, :class],
      [Time, :succ, :class],
      [Time, :round, :class],
      [Time, :sec, :class],
      [Time, :min, :class],
      [Time, :hour, :class],
      [Time, :mday, :class],
      [Time, :day, :class],
      [Time, :mon, :class],
      [Time, :month, :class],
      [Time, :year, :class],
      [Time, :wday, :class],
      [Time, :yday, :class],
      [Time, :isdst, :class],
      [Time, :dst?, :class],
      [Time, :zone, :class],
      [Time, :gmtoff, :class],
      [Time, :gmt_offset, :class],
      [Time, :utc_offset, :class],
      [Time, :utc?, :class],
      [Time, :gmt?, :class],
      [Time, :sunday?, :class],
      [Time, :monday?, :class],
      [Time, :tuesday?, :class],
      [Time, :wednesday?, :class],
      [Time, :thursday?, :class],
      [Time, :friday?, :class],
      [Time, :saturday?, :class],
      [Time, :tv_sec, :class],
      [Time, :tv_usec, :class],
      [Time, :usec, :class],
      [Time, :tv_nsec, :class],
      [Time, :nsec, :class],
      [Time, :subsec, :class],
      [Time, :strftime, :class],
      [Time, :_dump, :class],
      [Time, :_load, :singleton],
      [Kernel, :srand, :module],
      [Kernel, :srand, :singleton],
      [Kernel, :rand, :module],
      [Kernel, :rand, :singleton],
      [Random, :initialize, :class],
      [Random, :rand, :class],
      [Random, :bytes, :class],
      [Random, :seed, :class],
      [Random, :initialize_copy, :class],
      [Random, :marshal_dump, :class],
      [Random, :marshal_load, :class],
      [Random, :state, :class],
      [Random, :left, :class],
      [Random, :==, :class],
      [Random, :srand, :singleton],
      [Random, :rand, :singleton],
      [Random, :new_seed, :singleton],
      [Random, :state, :singleton],
      [Random, :left, :singleton],
      [Kernel, :trap, :module],
      [Kernel, :trap, :singleton],
      [Signal, :trap, :module],
      [Signal, :trap, :singleton],
      [Signal, :list, :module],
      [Signal, :list, :singleton],
      #[SignalException, :initialize, :class], #rb_call_super => vm_call_super
      [SignalException, :signo, :class],
      #[Interrupt, :initialize, :class], #rb_call_super => vm_call_super
      [Kernel, :exec, :module],
      [Kernel, :exec, :singleton],
      #[Kernel, :fork, :module], #rb_f_fork => rb_block_given_p
      #[Kernel, :fork, :singleton], #rb_f_fork => rb_block_given_p
      [Kernel, :exit!, :module],
      [Kernel, :exit!, :singleton],
      [Kernel, :system, :module],
      [Kernel, :system, :singleton],
      [Kernel, :spawn, :module],
      [Kernel, :spawn, :singleton],
      [Kernel, :sleep, :module],
      [Kernel, :sleep, :singleton],
      [Kernel, :exit, :module],
      [Kernel, :exit, :singleton],
      [Kernel, :abort, :module],
      [Kernel, :abort, :singleton],
      [Process, :exec, :singleton],
      #[Process, :fork, :singleton], #rb_f_fork => rb_block_given_p
      [Process, :spawn, :singleton],
      [Process, :exit!, :singleton],
      [Process, :exit, :singleton],
      [Process, :abort, :singleton],
      [Process, :kill, :module],
      [Process, :kill, :singleton],
      [Process, :wait, :module],
      [Process, :wait, :singleton],
      [Process, :wait2, :module],
      [Process, :wait2, :singleton],
      [Process, :waitpid, :module],
      [Process, :waitpid, :singleton],
      [Process, :waitpid2, :module],
      [Process, :waitpid2, :singleton],
      [Process, :waitall, :module],
      [Process, :waitall, :singleton],
      [Process, :detach, :module],
      [Process, :detach, :singleton],
      [Process::Status, :==, :class],
      [Process::Status, :&, :class],
      [Process::Status, :>>, :class],
      [Process::Status, :to_i, :class],
      [Process::Status, :to_s, :class],
      [Process::Status, :inspect, :class],
      [Process::Status, :pid, :class],
      [Process::Status, :stopped?, :class],
      [Process::Status, :stopsig, :class],
      [Process::Status, :signaled?, :class],
      [Process::Status, :termsig, :class],
      [Process::Status, :exited?, :class],
      [Process::Status, :exitstatus, :class],
      [Process::Status, :success?, :class],
      [Process::Status, :coredump?, :class],
      [Process, :pid, :module],
      [Process, :pid, :singleton],
      [Process, :ppid, :module],
      [Process, :ppid, :singleton],
      [Process, :getpgrp, :module],
      [Process, :getpgrp, :singleton],
      [Process, :setpgrp, :module],
      [Process, :setpgrp, :singleton],
      [Process, :getpgid, :module],
      [Process, :getpgid, :singleton],
      [Process, :setpgid, :module],
      [Process, :setpgid, :singleton],
      [Process, :setsid, :module],
      [Process, :setsid, :singleton],
      [Process, :getpriority, :module],
      [Process, :getpriority, :singleton],
      [Process, :setpriority, :module],
      [Process, :setpriority, :singleton],
      [Process, :getrlimit, :module],
      [Process, :getrlimit, :singleton],
      [Process, :setrlimit, :module],
      [Process, :setrlimit, :singleton],
      [Process, :uid, :module],
      [Process, :uid, :singleton],
      [Process, :uid=, :module],
      [Process, :uid=, :singleton],
      [Process, :gid, :module],
      [Process, :gid, :singleton],
      [Process, :gid=, :module],
      [Process, :gid=, :singleton],
      [Process, :euid, :module],
      [Process, :euid, :singleton],
      [Process, :euid=, :module],
      [Process, :euid=, :singleton],
      [Process, :egid, :module],
      [Process, :egid, :singleton],
      [Process, :egid=, :module],
      [Process, :egid=, :singleton],
      [Process, :initgroups, :module],
      [Process, :initgroups, :singleton],
      [Process, :groups, :module],
      [Process, :groups, :singleton],
      [Process, :groups=, :module],
      [Process, :groups=, :singleton],
      [Process, :maxgroups, :module],
      [Process, :maxgroups, :singleton],
      [Process, :maxgroups=, :module],
      [Process, :maxgroups=, :singleton],
      [Process, :daemon, :module],
      [Process, :daemon, :singleton],
      [Process, :times, :module],
      [Process, :times, :singleton],
      [Struct::Tms, :utime, :class],
      [Struct::Tms, :utime=, :class],
      [Struct::Tms, :stime, :class],
      [Struct::Tms, :stime=, :class],
      [Struct::Tms, :cutime, :class],
      [Struct::Tms, :cutime=, :class],
      [Struct::Tms, :cstime, :class],
      [Struct::Tms, :cstime=, :class],
      [Process::UID, :rid, :module],
      [Process::GID, :rid, :module],
      [Process::UID, :eid, :module],
      [Process::GID, :eid, :module],
      [Process::UID, :change_privilege, :module],
      [Process::GID, :change_privilege, :module],
      [Process::UID, :grant_privilege, :module],
      [Process::GID, :grant_privilege, :module],
      [Process::UID, :re_exchange, :module],
      [Process::GID, :re_exchange, :module],
      [Process::UID, :re_exchangeable?, :module],
      [Process::GID, :re_exchangeable?, :module],
      [Process::UID, :sid_available?, :module],
      [Process::GID, :sid_available?, :module],
      #[Process::UID, :switch, :module], #p_uid_switch => rb_block_given_p
      #[Process::GID, :switch, :module], #p_gid_switch => rb_block_given_p
      [Process::Sys, :getuid, :module],
      [Process::Sys, :geteuid, :module],
      [Process::Sys, :getgid, :module],
      [Process::Sys, :getegid, :module],
      [Process::Sys, :setuid, :module],
      [Process::Sys, :setgid, :module],
      [Process::Sys, :setruid, :module],
      [Process::Sys, :setrgid, :module],
      [Process::Sys, :seteuid, :module],
      [Process::Sys, :setegid, :module],
      [Process::Sys, :setreuid, :module],
      [Process::Sys, :setregid, :module],
      [Process::Sys, :setresuid, :module],
      [Process::Sys, :setresgid, :module],
      [Process::Sys, :issetugid, :module],
      [Kernel, :load, :module],
      [Kernel, :load, :singleton],
      [Kernel, :require, :module],
      [Kernel, :require, :singleton],
      [Kernel, :require_relative, :module],
      [Kernel, :require_relative, :singleton],
      [Module, :autoload, :class],
      [Module, :autoload?, :class],
      [Kernel, :autoload, :module],
      [Kernel, :autoload, :singleton],
      [Kernel, :autoload?, :module],
      [Kernel, :autoload?, :singleton],
      [Proc, :new, :singleton],
      #[Proc, :call, :class], #proc_call => rb_block_given_p
      #[Proc, :[], :class], #proc_call => rb_block_given_p
      #[Proc, :===, :class], #proc_call => rb_block_given_p
      #[Proc, :yield, :class], #proc_call => rb_block_given_p
      [Proc, :to_proc, :class],
      [Proc, :arity, :class],
      [Proc, :clone, :class],
      [Proc, :dup, :class],
      [Proc, :==, :class],
      [Proc, :eql?, :class],
      [Proc, :hash, :class],
      [Proc, :to_s, :class],
      [Proc, :lambda?, :class],
      [Proc, :binding, :class],
      [Proc, :curry, :class],
      [Proc, :source_location, :class],
      [Proc, :parameters, :class],
      [LocalJumpError, :exit_value, :class],
      [LocalJumpError, :reason, :class],
      [Kernel, :proc, :module],
      [Kernel, :proc, :singleton],
      [Kernel, :lambda, :module],
      [Kernel, :lambda, :singleton],
      [Method, :==, :class],
      [Method, :eql?, :class],
      [Method, :hash, :class],
      [Method, :clone, :class],
      [Method, :call, :class],
      [Method, :[], :class],
      [Method, :arity, :class],
      [Method, :inspect, :class],
      [Method, :to_s, :class],
      [Method, :to_proc, :class],
      [Method, :receiver, :class],
      [Method, :name, :class],
      [Method, :owner, :class],
      [Method, :unbind, :class],
      [Method, :source_location, :class],
      [Method, :parameters, :class],
      [Kernel, :method, :module],
      [Kernel, :public_method, :module],
      [UnboundMethod, :==, :class],
      [UnboundMethod, :eql?, :class],
      [UnboundMethod, :hash, :class],
      [UnboundMethod, :clone, :class],
      [UnboundMethod, :arity, :class],
      [UnboundMethod, :inspect, :class],
      [UnboundMethod, :to_s, :class],
      [UnboundMethod, :name, :class],
      [UnboundMethod, :owner, :class],
      [UnboundMethod, :bind, :class],
      [UnboundMethod, :source_location, :class],
      [UnboundMethod, :parameters, :class],
      [Module, :instance_method, :class],
      [Module, :public_instance_method, :class],
      [Module, :define_method, :class],
      [Kernel, :define_singleton_method, :module],
      [Binding, :clone, :class],
      [Binding, :dup, :class],
      [Binding, :eval, :class],
      [Kernel, :binding, :module],
      [Kernel, :binding, :singleton],
      [Math, :atan2, :module],
      [Math, :atan2, :singleton],
      [Math, :cos, :module],
      [Math, :cos, :singleton],
      [Math, :sin, :module],
      [Math, :sin, :singleton],
      [Math, :tan, :module],
      [Math, :tan, :singleton],
      [Math, :acos, :module],
      [Math, :acos, :singleton],
      [Math, :asin, :module],
      [Math, :asin, :singleton],
      [Math, :atan, :module],
      [Math, :atan, :singleton],
      [Math, :cosh, :module],
      [Math, :cosh, :singleton],
      [Math, :sinh, :module],
      [Math, :sinh, :singleton],
      [Math, :tanh, :module],
      [Math, :tanh, :singleton],
      [Math, :acosh, :module],
      [Math, :acosh, :singleton],
      [Math, :asinh, :module],
      [Math, :asinh, :singleton],
      [Math, :atanh, :module],
      [Math, :atanh, :singleton],
      [Math, :exp, :module],
      [Math, :exp, :singleton],
      [Math, :log, :module],
      [Math, :log, :singleton],
      [Math, :log2, :module],
      [Math, :log2, :singleton],
      [Math, :log10, :module],
      [Math, :log10, :singleton],
      [Math, :sqrt, :module],
      [Math, :sqrt, :singleton],
      [Math, :cbrt, :module],
      [Math, :cbrt, :singleton],
      [Math, :frexp, :module],
      [Math, :frexp, :singleton],
      [Math, :ldexp, :module],
      [Math, :ldexp, :singleton],
      [Math, :hypot, :module],
      [Math, :hypot, :singleton],
      [Math, :erf, :module],
      [Math, :erf, :singleton],
      [Math, :erfc, :module],
      [Math, :erfc, :singleton],
      [Math, :gamma, :module],
      [Math, :gamma, :singleton],
      [Math, :lgamma, :module],
      [Math, :lgamma, :singleton],
      [GC, :start, :singleton],
      [GC, :enable, :singleton],
      [GC, :disable, :singleton],
      [GC, :stress, :singleton],
      [GC, :stress=, :singleton],
      [GC, :count, :singleton],
      [GC, :stat, :singleton],
      [GC, :garbage_collect, :module],
      #[ObjectSpace, :each_object, :module], #os_each_obj
      #[ObjectSpace, :each_object, :singleton], #os_each_obj
      [ObjectSpace, :garbage_collect, :module],
      [ObjectSpace, :garbage_collect, :singleton],
      [ObjectSpace, :define_finalizer, :module],
      [ObjectSpace, :define_finalizer, :singleton],
      [ObjectSpace, :undefine_finalizer, :module],
      [ObjectSpace, :undefine_finalizer, :singleton],
      [ObjectSpace, :_id2ref, :module],
      [ObjectSpace, :_id2ref, :singleton],
      [BasicObject, :__id__, :class],
      [Kernel, :object_id, :module],
      [ObjectSpace, :count_objects, :module],
      [ObjectSpace, :count_objects, :singleton],
      [Kernel, :to_enum, :module],
      [Kernel, :enum_for, :module],
      #[Enumerator, :initialize, :class], #enumerator_initialize => rb_block_given_p
      [Enumerator, :initialize_copy, :class],
      #[Enumerator, :each, :class], #enumerator_each => rb_block_given_p
      #[Enumerator, :each_with_index, :class], #enumerator_each_with_index => enumerator_with_index
      #[Enumerator, :each_with_object, :class], #enumerator_with_object
      #[Enumerator, :with_index, :class], #enumerator_with_index
      #[Enumerator, :with_object, :class], #enumerator_with_object
      [Enumerator, :next_values, :class],
      [Enumerator, :peek_values, :class],
      [Enumerator, :next, :class],
      [Enumerator, :peek, :class],
      [Enumerator, :feed, :class],
      [Enumerator, :rewind, :class],
      #[Enumerator, :inspect, :class], #rb_exec_recursive => recursive_list_access
      [StopIteration, :result, :class],
      #[Enumerator::Generator, :initialize, :class], #generator_initialize => rb_block_given_p
      [Enumerator::Generator, :initialize_copy, :class],
      [Enumerator::Generator, :each, :class],
      [Enumerator::Yielder, :initialize, :class],
      [Enumerator::Yielder, :yield, :class],
      [Enumerator::Yielder, :<<, :class],
      [RubyVM::InstructionSequence, :inspect, :class],
      [RubyVM::InstructionSequence, :disasm, :class],
      [RubyVM::InstructionSequence, :disassemble, :class],
      [RubyVM::InstructionSequence, :to_a, :class],
      [RubyVM::InstructionSequence, :eval, :class],
      [Thread, :new, :singleton],
      [Thread, :start, :singleton],
      [Thread, :fork, :singleton],
      [Thread, :main, :singleton],
      [Thread, :current, :singleton],
      [Thread, :stop, :singleton],
      [Thread, :kill, :singleton],
      [Thread, :exit, :singleton],
      [Thread, :pass, :singleton],
      [Thread, :list, :singleton],
      [Thread, :abort_on_exception, :singleton],
      [Thread, :abort_on_exception=, :singleton],
      #[Thread, :initialize, :class], #thread_initialize => rb_block_given_p
      [Thread, :raise, :class],
      [Thread, :join, :class],
      [Thread, :value, :class],
      [Thread, :kill, :class],
      [Thread, :terminate, :class],
      [Thread, :exit, :class],
      [Thread, :run, :class],
      [Thread, :wakeup, :class],
      [Thread, :[], :class],
      [Thread, :[]=, :class],
      [Thread, :key?, :class],
      [Thread, :keys, :class],
      [Thread, :priority, :class],
      [Thread, :priority=, :class],
      [Thread, :status, :class],
      [Thread, :alive?, :class],
      [Thread, :stop?, :class],
      [Thread, :abort_on_exception, :class],
      [Thread, :abort_on_exception=, :class],
      [Thread, :safe_level, :class],
      [Thread, :group, :class],
      [Thread, :backtrace, :class],
      [Thread, :inspect, :class],
      [ThreadGroup, :list, :class],
      [ThreadGroup, :enclose, :class],
      [ThreadGroup, :enclosed?, :class],
      [ThreadGroup, :add, :class],
      [Mutex, :initialize, :class],
      [Mutex, :locked?, :class],
      [Mutex, :try_lock, :class],
      [Mutex, :lock, :class],
      [Mutex, :unlock, :class],
      [Mutex, :sleep, :class],
      [Kernel, :set_trace_func, :module],
      [Kernel, :set_trace_func, :singleton],
      [Thread, :set_trace_func, :class],
      [Thread, :add_trace_func, :class],
      [Fiber, :yield, :singleton],
      [Fiber, :initialize, :class],
      [Fiber, :resume, :class],
      [Kernel, :Rational, :module],
      [Kernel, :Rational, :singleton],
      [Rational, :numerator, :class],
      [Rational, :denominator, :class],
      [Rational, :+, :class],
      [Rational, :-, :class],
      [Rational, :*, :class],
      [Rational, :/, :class],
      [Rational, :quo, :class],
      [Rational, :fdiv, :class],
      [Rational, :**, :class],
      [Rational, :<=>, :class],
      [Rational, :==, :class],
      [Rational, :coerce, :class],
      [Rational, :floor, :class],
      [Rational, :ceil, :class],
      [Rational, :truncate, :class],
      [Rational, :round, :class],
      [Rational, :to_i, :class],
      [Rational, :to_f, :class],
      [Rational, :to_r, :class],
      [Rational, :rationalize, :class],
      [Rational, :hash, :class],
      [Rational, :to_s, :class],
      [Rational, :inspect, :class],
      [Rational, :marshal_dump, :class],
      [Rational, :marshal_load, :class],
      [Integer, :gcd, :class],
      [Integer, :lcm, :class],
      [Integer, :gcdlcm, :class],
      [Numeric, :numerator, :class],
      [Numeric, :denominator, :class],
      [Integer, :numerator, :class],
      [Integer, :denominator, :class],
      #[Float, :numerator, :class], #rb_call_super => vm_call_super
      #[Float, :denominator, :class], #rb_call_super => vm_call_super
      [NilClass, :to_r, :class],
      [NilClass, :rationalize, :class],
      [Integer, :to_r, :class],
      [Integer, :rationalize, :class],
      [Float, :to_r, :class],
      [Float, :rationalize, :class],
      [String, :to_r, :class],
      [Rational, :convert, :singleton],
      [Complex, :rectangular, :singleton],
      [Complex, :rect, :singleton],
      [Complex, :polar, :singleton],
      [Kernel, :Complex, :module],
      [Kernel, :Complex, :singleton],
      [Complex, :real, :class],
      [Complex, :imaginary, :class],
      [Complex, :imag, :class],
      [Complex, :-@, :class],
      [Complex, :+, :class],
      [Complex, :-, :class],
      [Complex, :*, :class],
      [Complex, :/, :class],
      [Complex, :quo, :class],
      [Complex, :fdiv, :class],
      [Complex, :**, :class],
      [Complex, :==, :class],
      [Complex, :coerce, :class],
      [Complex, :abs, :class],
      [Complex, :magnitude, :class],
      [Complex, :abs2, :class],
      [Complex, :arg, :class],
      [Complex, :angle, :class],
      [Complex, :phase, :class],
      [Complex, :rectangular, :class],
      [Complex, :rect, :class],
      [Complex, :polar, :class],
      [Complex, :conjugate, :class],
      [Complex, :conj, :class],
      [Complex, :real?, :class],
      [Complex, :numerator, :class],
      [Complex, :denominator, :class],
      [Complex, :hash, :class],
      [Complex, :eql?, :class],
      [Complex, :to_s, :class],
      [Complex, :inspect, :class],
      [Complex, :marshal_dump, :class],
      [Complex, :marshal_load, :class],
      [Complex, :to_i, :class],
      [Complex, :to_f, :class],
      [Complex, :to_r, :class],
      [Complex, :rationalize, :class],
      [NilClass, :to_c, :class],
      [Numeric, :to_c, :class],
      [String, :to_c, :class],
      [Complex, :convert, :singleton],
      [Numeric, :real, :class],
      [Numeric, :imaginary, :class],
      [Numeric, :imag, :class],
      [Numeric, :abs2, :class],
      [Numeric, :arg, :class],
      [Numeric, :angle, :class],
      [Numeric, :phase, :class],
      [Numeric, :rectangular, :class],
      [Numeric, :rect, :class],
      [Numeric, :polar, :class],
      [Numeric, :conjugate, :class],
      [Numeric, :conj, :class],
      [Float, :arg, :class],
      [Float, :angle, :class],
      [Float, :phase, :class],
    ]
    DIRECT_CALL_TARGETS.map! do |(obj, mid, t)|
      begin
        case t
        when :class
          bug() unless obj.instance_of?(Class)
          MethodWrapper.new(ClassWrapper.new(obj, true), mid)
        when :module
          bug() unless obj.instance_of?(Module)
          MethodWrapper.new(ModuleWrapper.new(obj), mid)
        when :singleton
          MethodWrapper.new(ClassWrapper.new(obj, false), mid)
        else
          bug()
        end
      rescue CompileError # method not found
        vlog("method not found #{obj} #{mid}")
      end
    end
    DIRECT_CALL_TARGETS.compact!

    def should_be_call_directly?(klass, mid)
      bug() unless klass.is_a?(ClassWrapper)
      DIRECT_CALL_TARGETS.include?(MethodWrapper.new(klass, mid))
    end

    CastOff::Compiler.class_eval do
      def should_be_call_directly(obj, mid, type)
        case type
        when :class
          bug() unless obj.instance_of?(Class)
          w = ClassWrapper.new(obj, true)
        when :module
          bug() unless obj.instance_of?(Module)
          w = ModuleWrapper.new(obj)
        when :singleton
          w = ClassWrapper.new(obj, false)
        else
          bug()
        end
        DIRECT_CALL_TARGETS.push(MethodWrapper.new(w, mid))
      end
    end

    def side_effect?(klass, mid)
      # TODO override check
      bug() unless klass.is_a?(ClassWrapper)
      bug() unless mid.is_a?(Symbol)
      begin
        me = MethodWrapper.new(klass, mid)
      rescue CompileError
        return true
      end
      me = MethodInformations[me]
      return true unless me
      bug() unless me.instance_of?(MethodInformation)
      return true if me.side_effect?
      bug() if me.destroy_reciever? || me.destroy_arguments?
      false
    end

    def harmless?(klass, mid, recv_p)
      bug() unless klass.is_a?(ClassWrapper)
      bug() unless mid.is_a?(Symbol)
      begin
        me = MethodWrapper.new(klass, mid)
      rescue CompileError
        return false
      end
      me = MethodInformations[me]
      return false unless me
      bug() unless me.instance_of?(MethodInformation)
      if recv_p
        return false if me.destroy_reciever?
        return false if me.escape_reciever?
      else
        return false if me.destroy_arguments?
        return false if me.escape_arguments?
      end
      true
    end

    OPTION_TABLE = {
      # class_variable => [default_value, compare_target, define_extra_reader]
      :@@enable_inline_api                       => [true,  true,  false],
      :@@inject_guard                            => [true,  true,  false],
      :@@array_conservative                      => [true,  true,  false],
      :@@reuse_compiled_code                     => [true,  false, true],
      :@@allow_builtin_variable_incompatibility  => [false, true,  false],
      :@@prefetch_constant                       => [true,  true,  false],
      :@@deoptimize                              => [true,  true,  true],
      :@@development                             => [false, true,  true],
      :@@alert_override                          => [true,  true,  false],
      :@@skip_configuration_check                => [false, false, true],

      # For base configuration
      :@@use_base_configuration                  => [true,  false, true],

      # For experiment
      :@@force_dispatch_method                   => [false, true,  false],
      :@@force_duplicate_literal                 => [false, true,  false],
      :@@force_inline_block                      => [false, true,  false],

      # Not implemented
      :@@enable_trace                            => [false, true,  false],
    }
    OPTION_TABLE.dup.each do |(cvar, val)|
      OPTION_TABLE[cvar] = {
        :default_value       => val[0],
        :compare_target      => val[1],
        :define_extra_reader => val[2],
      }
    end
    OPTION_TABLE.freeze()

    def same_option?(other_option)
      return false unless @option_table_configuration.size == other_option.size
      @option_table_configuration.each do |(cvar, val)|
        return false unless OPTION_TABLE.include?(cvar)
        return false unless other_option.include?(cvar)
        compare_target = OPTION_TABLE[cvar][:compare_target]
        bug() if compare_target.nil?
        next unless compare_target
        return false unless val == other_option[cvar]
      end
      true
    end

    CastOff::Compiler.__send__(:define_method, :clear_settings) do
      OPTION_TABLE.each do |(cvar, val)|
        CastOff::Compiler::Configuration.class_variable_set(cvar, val[:default_value])
      end
    end

    OPTION_TABLE.each do|(cvar, val)|
      mid = cvar.slice(2, cvar.size - 2)
      CastOff::Compiler.__send__(:define_method, mid) do |bool|
        CastOff::Compiler::Configuration.class_variable_set(cvar, bool)
      end

      define_method(mid) do |val|
        @option_table_configuration[cvar] = val
      end

      define_method("#{mid}?") do
        @option_table_configuration[cvar]
      end

      next unless val[:define_extra_reader]

      CastOff::Compiler.__send__(:define_method, "#{mid}?") do
        CastOff::Compiler::Configuration.class_variable_get(cvar)
      end
    end

    MethodInformations = {}
    CastOff::Compiler.module_eval do
      def use_default_configuration()
        MethodInformation.use_builtin_library_information()
      end

      def set_method_information(km, mid, type, info)
        case type
        when :class
          raise(ArgumentError.new("invalid first argument #{km}")) unless km.is_a?(Class)
          w = ClassWrapper.new(km, true)
        when :module
          raise(ArgumentError.new("invalid first argument #{km}")) unless km.is_a?(Module)
          w = ModuleWrapper.new(km)
        when :singleton
          w = ClassWrapper.new(km, false)
        else
          raise(ArgumentError.new("invalid argument"))
        end
        begin
          me = MethodWrapper.new(w, mid)
        rescue CompileError => e
          raise(ArgumentError.new(e.message))
        end
        MethodInformations[me] = MethodInformation.new(me, info)
      end
    end

    def check_method_information_usage()
      @method_information_usage.each do |me0|
        me1 = MethodInformations[me0.method]
        return false unless me1
        return false unless me0 == me1
      end
      true
    end

    def use_method_information(klass, mid)
      bug() unless klass.is_a?(ClassWrapper)
      bug() unless mid.is_a?(Symbol)
      begin
        me = MethodWrapper.new(klass, mid)
      rescue CompileError
        return false
      end
      me = MethodInformations[me]
      return false unless me
      bug() unless me.instance_of?(MethodInformation)
      @method_information_usage |= [me]
      true
    end

    private

    def __ignore_configuration_of_variables(sign)
      deletes = []
      @ignore_configuration_of_variables.each do |(k, v)|
        bug() unless k.instance_of?(Symbol)
        bug() unless v == true
        next unless @variable_configuration[k]
        bug() if @variable_configuration[k].empty?
        vlog("(#{sign}): ignore #{k} => #{@variable_configuration[k]}")
        @variable_configuration.delete(k)
        deletes |= [k]
      end
      deletes
    end

    def __ignore_configuration_of_return_values(sign)
      deletes = []
      @ignore_configuration_of_return_values.each do |(k, mids)|
        bug() if mids.find{|m| !m.instance_of?(Symbol)}
        if k.instance_of?(ClassWrapper)
          h = @return_value_configuration[k]
          next  unless h
          bug() unless h.instance_of?(Hash)
          kh = {k => h}
        else
          bug() unless k == SingletonClass
          kh = @return_value_configuration.dup
        end
        kh.each do |(k, h)|
          h.keys.each do |m|
            bug() unless m.instance_of?(Symbol)
            if mids.include?(m)
              vlog("(#{sign}): ignore #{k}#{k.singleton? ? '.' : '#'}#{m} => #{h[m]}")
              h.delete(m)
              @return_value_configuration.delete(k) if h.empty?
              deletes |= [[k, m]]
            end
          end
        end
      end
      deletes
    end

    def invalid_configuration(message = "Invalid configuration")
      raise(InvalidConfigurationError, message)
    end
  end
end
end

