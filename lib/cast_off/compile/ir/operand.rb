# coding=utf-8

module CastOff::Compiler
  module SimpleIR
    class TypeContainer
      include CastOff::Util

      undef_method(:==)
      undef_method(:eql?)
      undef_method(:hash)
      undef_method(:to_s)

      attr_reader :types, :state
      # state = :undefined || :initialized || :dynamic || :static

      # undefined   は、何と交わっても、交わった相手の状態に変わる
      # initialized は、dynamic と交わったときのみ、相手の状態に変わる
      # dynamic     は、何と交わっても dynamic のまま
      # static      は、何と交わっても static のまま

      # ignore に入っていたら @types に加えない
      # annotation に入っていたら dynamic にするときに、annotation で指定された型にする, ignore に含まれているものは加えない

      def initialize()
        @types = []
        @state = :undefined
        @annotation = []
        @ignore = []
        @unboxing_state = :undefined
        @negative_cond_value = false
      end

      ### unboxing begin ###
      def unbox()
        case @unboxing_state
        when :can_unbox
          @unboxing_state = :unboxed
          return true
        when :unboxed
          return false
        end
        bug()
      end

      def unboxed?
        @unboxing_state == :unboxed
      end

      def box()
        case @unboxing_state
        when :unboxed, :can_unbox, :can_not_unbox
          @unboxing_state = :boxed
          return true
        when :boxed
          return false
        end
        bug()
      end

      def boxed?
        @unboxing_state == :boxed
      end

      def can_unbox?
        if instance_of?(LocalVariable) || instance_of?(TmpVariable) || instance_of?(Literal)
          if dynamic? || @types.size != 1
            false
          else
            true
          end
        else
          # ConstWrapper, Self, Pointer, Argument, TmpBuffer
          false
        end
      end

      def can_not_unbox?
        @unboxing_state == :can_not_unbox
      end

      def can_unbox()
        bug() unless @unboxing_state == :undefined
        @unboxing_state = :can_unbox
      end

      def can_not_unbox()
        case @unboxing_state
        when :undefined, :can_unbox
          @unboxing_state = :can_not_unbox
          true
        when :can_not_unbox
          false
        else
          bug()
        end
      end

      def box_unbox_undefined?
        @unboxing_state == :undefined
      end
      ### unboxing end ###

      FloatWrapper = ClassWrapper.new(Float, true)
      FixnumWrapper = ClassWrapper.new(Fixnum, true)
      def declare_class()
        case @unboxing_state
        when :unboxed
          bug() if dynamic?
          bug() unless @types.size == 1
          c = @types[0]
          case c
          when FloatWrapper
            return :double
          when FixnumWrapper
            return :long
          end
        when :can_unbox, :can_not_unbox, :boxed
          return :VALUE
        end
        bug()
      end

      def declare()
        case declare_class()
        when :double
          return 'double'
        when :long
          return 'long'
        when :VALUE
          return 'VALUE'
        end
        bug()
      end

      def to_name()
        bug()
      end

      def to_debug_string()
        "#{self}(#{dynamic? ? 'dynamic' : @types.join(", ")})"
      end

      def to_s()
        case declare_class()
        when :double
          return "#{to_name()}_Float"
        when :long
          return "#{to_name()}_Fixnum"
        when :VALUE
          return to_name()
        end
        bug()
      end

      def class_exact?
        bug()
      end

      def is_class_exact()
        bug()
      end

      def reset()
        bug()
      end

      def not_initialized()
        # @ignore のせいで :undefined になっているものとしか交わらなかったため、initialize されなかったものがある。
        # そのため、@ignore が空のときに、ここに来る場合がある。
        @state = :dynamic
      end

      def is_not(types)
        bug() if @state == :static
        bug() unless (@types & @ignore).empty?
        bug() if types.empty?
        types = types.map{|t| convert(t)}
        if (types - @ignore).empty?
          false
        else
          @ignore |= types
          @types  -= types
          true
        end
      end

      def is_also(t)
        t = convert(t)
        return false if @ignore.include?(t)
        case @state
        when :undefined
          @state = :initialized
          bug() unless @types.empty?
          @types << t
          return true
        when :initialized
          bug() if @types.empty?
          if @types.include?(t)
            return false
          else
            @types << t
            return true
          end
        when :static
          bug() if @types.empty?
          bug() unless @types.include?(t)
          return false
        when :dynamic
          return false
        else
          bug()
        end
        bug()
      end

      def undefined?()
        @state == :undefined
      end

      def dynamic?()
        @state == :dynamic
      end

      def is_dynamic()
        return false if @state == :dynamic
        return false if @state == :static
        if annotated?
          if (@annotation - @ignore - @types).empty?
            return false
          else
            @state = :initialized
            @types |= (@annotation - @ignore)
            return true
          end
        else
          @state = :dynamic
          return true
        end
        bug()
      end

      def static?()
        @state == :static
      end

      def is_static(types)
        bug() if types.empty?
        types = types.map{|t| convert(t)}
        bug() unless (@ignore & types).empty?
        case @state
        when :undefined
          bug() unless @types.empty?
          @types = types
          @state = :static
          return true
        when :static
          bug() unless @types == types
          return false
        end
        bug()
      end

      def is_annotated(types)
        # 代入の対象となるような変数(local, instance, class, global variable)は、
        # static ではなく annotated とする。
        # initialized にしちゃうと、dynamic と union したときに、dynamic になってしまうのがもどかしい。
        bug() unless @state == :undefined
        bug() unless @annotation.empty?
        bug() unless @ignore.empty?
        bug() if types.empty?
        @annotation = types.map{|t| convert(t)}
        @annotation.freeze()
      end

      def is_just?(c)
        case c
        when Class, ClassWrapper
          return is_just_class(c)
        when Array
          return is_just_classes(c)
        end
        bug()
      end

      def is_also?(c)
        case c
        when Class, ClassWrapper
          return is_also_class(c)
        end
        bug()
      end

      def union(v)
        bug() if (v.types + @types).find{|t| not t.is_a?(ClassWrapper)}
        union_types = v.types - @ignore
        case @state
        when :undefined
          bug() unless @types.empty?
          case v.state
          when :undefined
            return false
          when :initialized, :static
            return false if union_types.empty?
            @state = :initialized
            @types |= union_types
            return true
          when :dynamic
            return is_dynamic()
          else
            bug()
          end
        when :initialized
          bug() if @types.empty?
          case v.state
          when :undefined
            return false
          when :initialized, :static
            if (union_types - @types).empty?
              return false
            else
              @types |= union_types
              return true
            end
          when :dynamic
            return is_dynamic()
          else
            bug()
          end
        when :static
          bug() if @types.empty?
          case v.state
          when :undefined, :dynamic
            return false
          when :initialized, :static
            bug() unless (union_types - @types).empty? || negative_cond_value?
            return false
          else
            bug()
          end
        when :dynamic
          return false
        else
          bug()
        end
        bug()
      end

      def is_negative_cond_value
        @negative_cond_value = true
      end

      private

      def negative_cond_value?
        @negative_cond_value
      end

      def is_just_classes(classes)
        classes = classes.map{|c| convert(c)}
        case @state
        when :undefined
          bug()
        when :initialized, :static
          bug() if @types.empty?
          bug() if classes.empty?
          return false unless (@types - classes).empty?
          return false unless (classes - @types).empty?
          return true
        when :dynamic
          return false
        end
        bug()
      end

      def is_just_class(klass)
        klass = convert(klass)
        case @state
        when :undefined
          bug()
        when :initialized, :static
          bug() if @types.empty?
          return false if @types.size != 1
          return false if @types[0] != klass
          return true
        when :dynamic
          return false
        end
        bug()
      end

      def is_also_class(klass)
        klass = convert(klass)
        case @state
        when :undefined
          bug()
        when :initialized, :static
          bug() if @types.empty?
          return @types.include?(klass)
        when :dynamic
          return false
        end
        bug()
      end

      def convert(t)
        case t
        when ClassWrapper
          # nothing to do
        when Class
          t = ClassWrapper.new(t, true)
        else
          bug()
        end
        t
      end

      def annotated?
        not @annotation.empty?
      end
    end

    class ConstWrapper < TypeContainer
      attr_reader :path

      def initialize(flag, *ids, translator)
        super()
        @chain = ids
        @flag = flag
        @path = "#{@flag ? '::' : nil}#{@chain.join("::")}"
        @translator = translator
        @name = @translator.allocate_name("const_#{@path}")
        @translator.declare_constant(@name)
        conf = @translator.configuration
        @cache_constant_p = @prefetch_constant_p = conf.prefetch_constant? && conf.has_binding?
        if prefetch?
          begin
            val = conf.evaluate_by_passed_binding(@path)
            c = ClassWrapper.new(val, false)
          rescue
            @prefetch_constant_p = false
            c = nil
          end
        else
          c = nil
        end
        if c && @translator.get_c_classname(c)
          is_static([c])
        else
          is_dynamic()
        end
      end

      def get_constant_chain
        ret = []
        ret << "  cast_off_tmp = #{@flag ? 'rb_cObject' : 'Qnil'};"
        @chain.each do |id|
          ret << "  cast_off_tmp = cast_off_get_constant(cast_off_tmp, #{@translator.allocate_id(id)});"
        end
        ret << "  #{@name} = cast_off_tmp;"
        ret.join("\n")
      end

      def cache?
        @cache_constant_p
      end

      def prefetch?
        @prefetch_constant_p
      end

      def class_exact?
        false
      end

      def to_name
        @name
      end

      def source
        @path
      end

      def eql?(v)
        return false unless v.is_a?(ConstWrapper)
        @path == v.path
      end

      def ==(v)
        eql?(v)
      end

      def hash
        @path.to_s.hash
      end
    end

    class Literal < TypeContainer
      include CastOff::Util

      attr_reader :val, :literal_value

      def initialize(val, translator)
        super()
        case val
        when NilClass
          @val = "Qnil"
          type = NilClass
          @literal_value = nil
        when Fixnum, Symbol, Bignum, Float, String, Regexp, Array, Range, TrueClass, FalseClass, Class
          @val = translator.allocate_object(val)
          type = val.class
          @literal_value = val
        else
          bug("unexpected object #{val}")
        end
        is_static([type])
      end

      def to_s()
        case declare_class()
        when :double, :long
          return "#{@literal_value}"
        when :VALUE
          return to_name()
        end
        bug()
      end

      def class_exact?
        true
      end

      def to_name
        @val
      end

      def source
        @literal_value.inspect
      end

      def eql?(v)
        return false unless v.is_a?(Literal)
        @literal_value == v.literal_value
      end

      def ==(v)
        eql?(v)
      end

      def hash()
        @literal_value.hash()
      end
    end

    class Variable < TypeContainer
      def initialize()
        super()
        @isclassexact = false
      end

      def class_exact?
        @isclassexact
      end

      def is_class_exact()
        bug() if @isclassexact
        @isclassexact = true
      end

      def has_undefined_path()
        # nothing to do
      end

      def declare?
        self.is_a?(LocalVariable) || self.is_a?(TmpVariable) || self.is_a?(Pointer)
      end

      def reset()
        @ignore.clear()
        case @state
        when :undefined
          bug()
        when :initialized, :dynamic
          @types = []
          @state = :undefined
        when :static
          # nothing to do
        else
          bug()
        end
      end
    end

    class Self < Variable
      include CastOff::Util

      attr_reader :iseq

      def initialize(translator, iseq)
        super()
        @iseq = iseq
        @translator = translator
        bug() unless @iseq.is_a?(Iseq)
        reciever_class = translator.reciever_class
        if reciever_class
          #is_static(reciever_class)
          reciever_class = [reciever_class] unless reciever_class.instance_of?(Array)
          reciever_class.each{|c| is_also(c)}
        else
          is_dynamic()
        end
      end

      def class_exact?
        false
      end

      def to_name
        "self"
      end

      def source
        "self"
      end

      def eql?(v)
        #v.is_a?(Self)
        return false unless v.is_a?(Self)
        return true if @translator.inline_block?
        @iseq == v.iseq
      end

      def ==(v)
        eql?(v)
      end

      def hash
        self.to_name.hash
      end

      def to_debug_string
        "#{super}(#{@iseq})"
      end

      def reset()
        # nothing to do
      end
    end

    class TmpVariable < Variable
      include CastOff::Util
      attr_reader :index

      def initialize(index)
        super()
        @index = index
      end

      def to_name
        "tmp#{@index}"
      end

      def source
        bug()
      end

      def eql?(v)
        return false unless v.is_a?(TmpVariable)
        @index == v.index
      end

      def ==(v)
        eql?(v)
      end

      def hash
        self.to_name.hash
      end

      def has_undefined_path()
        bug()
      end
    end

    class Pointer < Variable
      def initialize
        super()
      end
    end

    class InstanceVariable < Pointer
      attr_reader :id

      def initialize(id, types)
        super()
        @id = id
        @name = id.slice(1, id.size - 1)
        
        if types
          bug() unless types.is_a?(Array)
          is_annotated(types)
        end
      end

      def to_name
        "instance_#{@name}"
      end

      def source
        @id.to_s
      end

      def eql?(v)
        return false unless v.is_a?(InstanceVariable)
        @id == v.id
      end

      def ==(v)
        eql?(v)
      end

      def hash
        self.to_name.hash
      end
    end

    class ClassVariable < Pointer
      attr_reader :id

      def initialize(id, types)
        super()
        @id = id
        @name = id.slice(2, id.size - 2)
        
        if types
          bug() unless types.is_a?(Array)
          is_annotated(types)
        end
      end

      def to_name
        "class_#{@name}"
      end

      def source
        @id.to_s
      end

      def eql?(v)
        return false unless v.is_a?(ClassVariable)
        @id == v.id
      end

      def ==(v)
        eql?(v)
      end

      def hash
        self.to_name.hash
      end
    end

    class GlobalVariable < Pointer
      attr_reader :id

      def initialize(gentry, types, translator)
        super()
        @id = gentry
        @name = gentry.slice(1, gentry.size - 1)
        @name = translator.allocate_name(@name)
        
        if types
          bug() unless types.is_a?(Array)
          is_annotated(types)
        end
      end

      def to_name
        "global_#{@name}"
      end

      def source
        @id.to_s
      end

      def eql?(v)
        return false unless v.is_a?(GlobalVariable)
        @id == v.id
      end

      def ==(v)
        eql?(v)
      end

      def hash
        self.to_name.hash
      end
    end

    class DynamicVariable < Pointer
      attr_reader :index, :level

      def initialize(name, idx, op_idx, lv, types)
        super()
        @name = name
        @index = idx
        @op_idx = op_idx
        @level = lv

        if types
          bug() unless types.is_a?(Array)
          is_annotated(types)
        end
      end

      def to_name
        "dfp#{@level}[#{@op_idx}]"
      end

      def source
        @name.to_s
      end

      def eql?(v)
        return false unless v.is_a?(DynamicVariable)
        @index == v.index && @level == v.level
      end

      def ==(v)
        eql?(v)
      end

      def hash
        self.to_name.hash
      end

      def declare?
        false
      end
    end

    class Argument < Variable
      attr_reader :id, :lvar

      def initialize(name, id, op_idx, lv, types)
        super()
        @name = name
        @id = id
        @op_idx = op_idx
        @level = lv
        @lvar = "local#{@id}_#{@name}" # FIXME

        if types
          bug() unless types.is_a?(Array)
          is_static(types)
        end
      end

      def to_name
        "<Argument:#{@id}_#{@name}>"
      end

      def source
        bug()
      end

      def eql?(v)
        return false unless v.is_a?(Argument)
        @id == v.id
      end

      def ==(v)
        eql?(v)
      end

      def hash
        self.to_name.hash
      end
    end

    class LocalVariable < Variable
      attr_reader :id, :name

      def initialize(name, id, op_idx, lv, types)
        super()
        @name = name
        @id = id
        @op_idx = op_idx
        @level = lv

        if types
          bug() unless types.is_a?(Array)
          is_annotated(types)
        end
      end

      def to_name
        "local#{@id}_#{@name}"
      end

      def source
        @name.to_s
      end

      def eql?(v)
        return false unless v.is_a?(LocalVariable)
        @id == v.id
      end

      def ==(v)
        eql?(v)
      end

      def hash
        self.to_name.hash
      end

      def has_undefined_path()
        bug()
      end
    end

    class TmpBuffer < Variable
      attr_reader :index

      def initialize(index)
        super()
        @index = index
      end

      def to_name
        "cast_off_argv[#{@index}]"
      end

      def source
        bug()
      end

      def eql?(v)
        return false unless v.is_a?(TmpBuffer)
        @index == v.index
      end

      def ==(v)
        eql?(v)
      end

      def hash
        self.to_name.hash
      end
    end
  end
end

