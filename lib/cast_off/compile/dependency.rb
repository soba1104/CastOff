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
        bug() unless obj.instance_of?(Class) || obj.instance_of?(Module)
        dep = @@singleton_method_dependency[obj]
        return false unless dep
        return false unless dep.include?(mid)
        bug() unless @@singleton_method_dependency_initializers[[obj, mid]]
        @@singleton_method_dependency_initializers[[obj, mid]]
      end

      def self.singleton_method_strongly_depend?(obj, mid)
        bug() unless obj.instance_of?(Class) || obj.instance_of?(Module)
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
        # TODO klass から、対象メソッドを定義しているクラスまでのメソッドの検索対象を全てフック
        bug() unless klass.instance_of?(ClassWrapper)
        targets = [klass]
        if not klass.singleton?
          c = klass.contain_class
          cm = CastOff.override_target(c, mid)
          case cm
          when Class
            targets << ClassWrapper.new(cm, true) if cm != c
          when Module
            targets << ModuleWrapper.new(cm)
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

      def self.hook(o)
        s = class << o
          self
        end
        s.class_eval do
          def override_singleton_method(obj, mid, flag)
            if initializers = Dependency.singleton_method_depend?(obj, mid)
              if Dependency.singleton_method_strongly_depend?(obj, mid)
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
            if initializers = Dependency.instance_method_depend?(obj, mid)
              if Dependency.instance_method_strongly_depend?(obj, mid)
                raise(ExecutionError.new("Should not be override #{obj}##{mid}"))
              end
              # TODO Array.each の上書きチェック
              initializers.each do |init|
                CastOff.dlog("update function pointer #{obj}##{mid}")
                CastOff.__send__(init)
              end
            end
          end

          define_method(:method_added) do |mid|
            if self == o && !Dependency.ignore_overridden?(self, mid)
              if Dependency.singleton_method_added?
                CastOff.dlog("singleton method added #{o}.#{mid}")
                CastOff.delete_original_singleton_method_iseq(self, mid)
                override_singleton_method(o, mid, :added) 
              else
                CastOff.dlog("method added #{o}##{mid}")
                CastOff.delete_original_instance_method_iseq(self, mid)
                override_method(o, mid, :added)
              end
            end
            super(mid) rescue NoMethodError
          end
          alias singleton_method_added method_added
          CastOff.dlog("hook #{o}")
        end
        @@singleton_method_dependency[o] ||= []
        @@singleton_method_dependency[o] |= [:method_added, :singleton_method_added]
        @@singleton_method_strong_dependency[o] ||= []
        @@singleton_method_strong_dependency[o] |= [:method_added]
        @@singleton_method_strong_dependency[o] |= [:singleton_method_added]
      end

      def hook(function_pointer_initializer)
        @dependency.keys.each do |klass|
          m = @dependency[klass]
          if klass.instance_of?(ClassWrapper) && klass.singleton?
            m.each{|mid| self.class.singleton_method_depend(klass, mid, function_pointer_initializer)}
            m.each{|mid| self.class.singleton_method_strongly_depend(klass, mid) if @strong_dependency.include?([klass, mid])}
            o = klass.contain_object
            bug() unless o.instance_of?(Class) || o.instance_of?(Module)
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

