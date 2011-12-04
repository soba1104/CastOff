module CastOff
  module Compiler
    class Dependency
      extend  CastOff::Util
      include CastOff::Util

      def initialize
        @dependency = {}
        @strong_dependency = []
      end

      @@instance_method_dependency = {}
      @@instance_method_dependency_initializers = {}
      @@singleton_method_dependency = {}
      @@singleton_method_dependency_initializers = {}
      @@instance_method_strong_dependency = {}
      @@singleton_method_strong_dependency = {}

      def self.get_class_or_module(km)
        case km
        when ClassWrapper
          bug() if  km.singleton?
          return km.contain_class
        when ModuleWrapper
          return km.contain_module
        end
        bug()
      end

      def self.instance_method_depend(klass, mid, function_pointer_initializer)
        c = get_class_or_module(klass)
        a = (@@instance_method_dependency[c] ||= [])
        a << mid unless a.include?(mid)
        b = (@@instance_method_dependency_initializers[[c, mid]] ||= [])
        b << function_pointer_initializer unless b.include?(function_pointer_initializer)
      end

      def self.instance_method_strongly_depend(klass, mid)
        c = get_class_or_module(klass)
        @@instance_method_strong_dependency[c] ||= []
        a = @@instance_method_strong_dependency[c]
        a << mid unless a.include?(mid)
      end

      def self.instance_method_depend?(klass, mid)
        bug() unless klass.instance_of?(Class) || klass.instance_of?(Module)
        dep = @@instance_method_dependency[klass]
        return false unless dep
        return false unless dep.include?(mid)
        bug() unless @@instance_method_dependency_initializers[[klass, mid]]
        @@instance_method_dependency_initializers[[klass, mid]]
      end

      def self.instance_method_strongly_depend?(obj, mid)
        bug() unless obj.instance_of?(Class) || obj.instance_of?(Module)
        dep = @@instance_method_strong_dependency[obj]
        dep.instance_of?(Array) ? dep.include?(mid) : false
      end

      def self.singleton_method_depend(klass, mid, function_pointer_initializer)
        bug() unless klass.instance_of?(ClassWrapper)
        bug() unless klass.singleton?
        o = klass.contain_object
        a = (@@singleton_method_dependency[o] ||= [])
        a << mid unless a.include?(mid)
        b = (@@singleton_method_dependency_initializers[[o, mid]] ||= [])
        b << function_pointer_initializer unless b.include?(function_pointer_initializer)
      end

      def self.singleton_method_strongly_depend(klass, mid)
        bug() unless klass.instance_of?(ClassWrapper)
        bug() unless klass.singleton?
        o = klass.contain_object
        @@singleton_method_strong_dependency[o] ||= []
        a = @@singleton_method_strong_dependency[o]
        a << mid unless a.include?(mid)
      end

      def self.singleton_method_depend?(obj, mid)
        bug() unless ClassWrapper.support?(obj, false)
        dep = @@singleton_method_dependency[obj]
        return false unless dep
        return false unless dep.include?(mid)
        unless @@singleton_method_dependency_initializers[[obj, mid]]
          if mid == :method_added || mid == :singleton_method_added
            return []
          else
            bug()
          end
        end
        @@singleton_method_dependency_initializers[[obj, mid]]
      end

      def self.singleton_method_strongly_depend?(obj, mid)
        bug() unless ClassWrapper.support?(obj, false)
        dep = @@singleton_method_strong_dependency[obj]
        dep.instance_of?(Array) ? dep.include?(mid) : false
      end

      def dump(io)
        begin
          Marshal.dump(self, io)
        rescue TypeError => e
          raise(UnsupportedError.new(<<-EOS))

Failed to marshal dump method dependency.
Dependency object should be able to marshal dump.
Currently, CastOff doesn't support object, which cannot marshal dump (e.g. STDIN).
--- Marshal.dump error message ---
#{e.message}
          EOS
        end
      end

      def self.load(str)
        dep = Marshal.load(str)
        bug() unless dep.instance_of?(Dependency)
        dep
      end

      def marshal_dump()
        [@dependency, @strong_dependency]
      end

      def marshal_load(obj)
        @dependency, @strong_dependency = obj
      end

      def add(klass, mid, strong_p)
        bug() unless klass.instance_of?(ClassWrapper)
        targets = [klass]
        klass.each_method_search_target(mid) do |cm|
          next if klass.singleton? ? (cm == klass) : (cm == klass.contain_class)
          case cm
          when Class
            targets << ClassWrapper.new(cm, true)
          when Module
            targets << ModuleWrapper.new(cm)
          when ClassWrapper
            bug() unless cm.singleton?
            targets << cm
          else
            bug()
          end
        end
        targets.each do |t|
          @dependency[t] ||= []
          @dependency[t] |= [mid]
          @strong_dependency |= [[t, mid]] if strong_p
        end
      end

      def check_failed(msg = '')
        raise(LoadError.new("failed to check method dependency: #{msg}"))
      end

      def check(configuration)
        @dependency.each do |(klass, mids)|
          bug() unless klass.instance_of?(ClassWrapper) || klass.instance_of?(ModuleWrapper)
          # TODO ブロックインライニングしたメソッドに対して
          #      コンパイル時のメソッドと等しいものかどうかをチェック
        end
      end

      def self.copy(dst, src, singleton_p)
        bug() unless dst.is_a?(Module)
        dst = ModuleWrapper.new(dst)
        deps  = singleton_p ? @@singleton_method_dependency : @@instance_method_dependency
        funcs = singleton_p ? @@singleton_method_dependency_initializers : @@instance_method_dependency_initializers
        (deps[src] || []).each do |mid|
          finits = funcs[[src, mid]]
          if finits && !finits.empty?
            finits.each{|f| instance_method_depend(dst, mid, f)}
          else
            bug() unless singleton_p
            case mid
            when :singleton_method_added, :method_added, :include, :extend
              # nothing to do
            else
              bug()
            end
          end
        end
      end

      def self.hook(o)
        s = class << o
          self
        end
        s.class_eval do
          def override_singleton_method(obj, mid, flag)
            CastOff.dlog("singleton method added #{obj}.#{mid}")
            CastOff.delete_original_singleton_method_iseq(self, mid)
            if initializers = Dependency.singleton_method_depend?(obj, mid)
              if Dependency.singleton_method_strongly_depend?(obj, mid) && !CastOff.method_replacing?
                raise(ExecutionError.new("Should not be override #{obj}.#{mid}"))
              end
              # TODO Array.each の上書きチェック
              initializers.each do |init|
                CastOff.dlog("update function pointer #{obj}.#{mid}")
                CastOff.__send__(init)
              end
            end
          end

          def override_method(obj, mid, flag)
            CastOff.dlog("method added #{obj}##{mid}")
            CastOff.delete_original_instance_method_iseq(self, mid)
            if initializers = Dependency.instance_method_depend?(obj, mid)
              if Dependency.instance_method_strongly_depend?(obj, mid) && !CastOff.method_replacing?
                raise(ExecutionError.new("Should not be override #{obj}##{mid}"))
              end
              # TODO Array.each の上書きチェック
              initializers.each do |init|
                CastOff.dlog("update function pointer #{obj}##{mid}")
                CastOff.__send__(init)
              end
            end
          end

          begin
            singleton_method_added = o.method(:singleton_method_added).unbind
          rescue NameError
            singleton_method_added = nil
          end

          begin
            method_added = o.method(:method_added).unbind
          rescue NameError
            method_added = nil
          end

          begin
            m_include = o.method(:include).unbind
            m_extend  = o.method(:extend).unbind
          rescue NameError
            raise(ExecutionError.new("#{o}: include or extend not defined"))
          end

          define_method(:method_added) do |*args|
            ignore_overridden_p = Dependency.ignore_overridden?
            current_mid = CastOff.current_method_id
            case current_mid
            when :extend, :include
              mods = args
              extend_p = current_mid == :extend
              CastOff.dlog("#{self} #{extend_p ? 'extends' : 'includes'} #{mods}")
              bug() unless m_include && m_extend
              m = extend_p ? m_extend : m_include
              # include, extend の対象は self なので、self 以外が include, extend することはない。
              m.bind(self).call(*mods)
              return unless o == self
              mods.each do |mod|
                next unless mod.is_a?(Module)
                Dependency.copy(mod, self, extend_p)
                Dependency.hook(mod) unless mod.singleton_methods(false).include?(:override_singleton_method)
                methods = mod.instance_methods(false) + mod.private_instance_methods(false)
                override_callback = extend_p ? :override_singleton_method : :override_method
                methods.each{|mid| o.__send__(override_callback, o, mid, extend_p ? :extend : :include)}
              end
            when :singleton_method_added
              mid = args.first
              CastOff.bug() unless mid.instance_of?(Symbol)
              if self == o && !ignore_overridden_p
                override_singleton_method(o, mid, :added) 
                singleton_method_added.bind(self).call(mid) if singleton_method_added
              elsif o == Module && singleton_method_added
                singleton_method_added.bind(self).call(mid)
              end
              super(mid) rescue NoMethodError
            when :method_added
              mid = args.first
              CastOff.bug() unless mid.instance_of?(Symbol)
              if self == o && !ignore_overridden_p
                override_method(o, mid, :added)
                method_added.bind(self).call(mid) if method_added
              elsif o == Module && method_added
                method_added.bind(self).call(mid)
              end
              super(mid) rescue NoMethodError
            else
              raise(ExecutionError.new("CastOff expected include, extend, method_added or singleton_method_added but #{current_mid} was called"))
            end
          end
          alias extend method_added
          alias include method_added
          alias singleton_method_added method_added
          CastOff.dlog("hook #{o}")
        end
        @@singleton_method_dependency[o] ||= []
        @@singleton_method_dependency[o] |= [:method_added, :singleton_method_added, :include, :extend]
        @@singleton_method_strong_dependency[o] ||= []
        @@singleton_method_strong_dependency[o] |= [:method_added, :singleton_method_added, :include, :extend]
      end

      def hook(function_pointer_initializer)
        @dependency.keys.each do |klass|
          m = @dependency[klass]
          if klass.instance_of?(ClassWrapper) && klass.singleton?
            m.each{|mid| self.class.singleton_method_depend(klass, mid, function_pointer_initializer)}
            m.each{|mid| self.class.singleton_method_strongly_depend(klass, mid) if @strong_dependency.include?([klass, mid])}
            o = klass.contain_object
            bug() unless ClassWrapper.support?(o, false)
          else
            m.each{|mid| self.class.instance_method_depend(klass, mid, function_pointer_initializer)}
            m.each{|mid| self.class.instance_method_strongly_depend(klass, mid) if @strong_dependency.include?([klass, mid])}
            case klass
            when ClassWrapper
              o = klass.contain_class
            when ModuleWrapper
              o = klass.contain_module
            else
              bug()
            end
          end
          next if o.singleton_methods(false).include?(:override_singleton_method)
          Dependency.hook(o)
        end
      end
    end
  end
end

