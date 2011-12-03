# coding=utf-8

module CastOff
  module Compiler
  module SimpleIR
    class CallIR < IR
      include Instruction

      attr_reader :argc, :return_value, :variables_without_result, :variables, :result_variable, :values

      def initialize(param, argc, return_value, insn, cfg)
        super(insn, cfg)
        @argc = argc
        bug() unless return_value.is_a?(TmpVariable)
        @return_value = return_value
        bug() unless param.is_a?(Array)
        bug() unless param.size == @argc
        @param = param
        @sampling_return_value = false
        @values = [@return_value]
        @variables = []
        @variables_without_result = []
        @variables << @return_value
        @result_variable = @return_value
        @source = @insn.source
        @source = @source.empty? ? nil : @source
        @source_line = @insn.line.to_s
      end

      def propergate_guard_usage()
        bug()
      end

      ### unboxing begin ###
      def unboxing_prelude()
        can_not_unbox()
      end

      def propergate_boxed_value(defs)
        # nothing to do
        false
      end

      def can_not_unbox()
        params = param_variables()
        params.each{|p| p.box()}
        @return_value.box()
      end
      ### unboxing end ###

      def propergate_exact_class(defs)
        false
      end

      def sampling_return_value()
        @sampling_return_value = true
      end

      def sampling_return_value?
        @sampling_return_value
      end

      def param_irs()
        @param.dup()
      end

      def param_variables()
        @param.map{|p| p.param_value}
      end

      def to_c(params)
        param = []
        ret = []
        @argc.times do
          bug() if params.empty?
          param.unshift(params.pop)
        end
        s = sampling_variable()
        ret << s if s
        bug() unless param_variables() == param
        bug() unless @param.size() == @argc
        ret.join("\n")
      end

      def type_propergation()
        bug()
      end

      def harmless?(recv_p)
        bug("#{self}, #{self.class}")
      end

      def side_effect?
        bug()
      end

      def should_be_alive?
        bug()
      end

      def mark(defs)
        param = param_irs()
        if should_be_alive?
          if !alive?
            alive()
            param.each{|p| p.alive()}
            true
          else
            false
          end
        else
          alive? ? param.inject(false){|change, p| p.alive() || change} : false
        end
      end
    end

    class VMInsnIR < CallIR
      attr_reader :argv

      def initialize(param, argc, return_value, insn, cfg)
        bug() unless insn.is_a?(InsnInfo)
        super(param, argc, return_value, insn, cfg)
        @opecode = insn.op
        @operands = insn.argv
      end

      def propergate_guard_usage()
        bug()
      end

      def to_c(params)
        case @opecode
        when :putstring, :newarray, :newhash, :duparray, :tostring, :toregexp, :concatstrings, :concatarray, \
             :newrange, :opt_regexpmatch1, :opt_regexpmatch2, :getconstant, :getspecial, :expandarray_pre, \
             :expandarray_loop, :expandarray_splat, :expandarray_post_loop, :expandarray_post_splat, :splatarray, \
             :checkincludearray_pre, :checkincludearray_case, :checkincludearray_when, :cast_off_fetch_args, :defined
          # nothing to do
        else
          bug("unexpected instruction #{@opecode}")
        end
        super(params)
      end

      def dont_duplicate_if_harmless(obj)
        return nil if @configuration.force_duplicate_literal?
        usage = get_usage()
        harmless = true
        if usage[:escape]
          harmless = false
        else
          usage.each do |(u, recv_p)|
            u_recv, u_ir = u
            unless u_ir.harmless?(recv_p)
              harmless = false
              break
            end
          end
        end
        if harmless
          return "  #{@return_value} = #{obj};"
        else
          if @configuration.development?
            if usage[:escape]
              u = usage[:escape]
              msg = "escape to #{u.is_a?(ReturnIR) ? 'caller' : 'pointer'}"
            else
              msg = usage.keys.map {|(u_recv, u_ir)|
                bug(u_ir) unless u_ir.is_a?(CallIR)
                if u_ir.dispatch_method?
                  "used by #{u_ir.to_verbose_string}"
                else
                  s = u_ir.insn.source
                  s.empty? ? nil : "used by #{s}"
                end
              }.compact.join("\n")
            end
            @translator.add_literal_suggestion([get_definition_str(obj), msg, @source_line, @source]) if @source
          end
          return nil
        end
        bug()
      end

      def type_propergation()
        super()
      end

      def side_effect?
        bug()
      end

      def should_be_alive?
        side_effect?
      end
    end

    class Putstring < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
        bug() unless @argc == 1
        bug() unless @param[0].param_value.is_a?(Literal)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def propergate_exact_class(defs)
        @return_value.class_exact? ? false : @return_value.is_class_exact()
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        str = param.shift
        bug() unless str.is_a?(Literal)
        code = dont_duplicate_if_harmless(str)
        code = "  #{@return_value} = rb_str_resurrect(#{str});" unless code
        ret << code
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([String])
      end

      def harmless?(recv_p)
        true
      end

      def side_effect?
        false
      end
    end

    class Newarray < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      ### unboxing begin ###
      def unboxing_prelude()
        params = param_variables()
        params.each{|p| p.box()}
        @return_value.box() unless @return_value.can_unbox?
      end
      ### unboxing end ###

      def propergate_exact_class(defs)
        @return_value.class_exact? ? false : @return_value.is_class_exact()
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        if @argc == 0
          ret << "  #{@return_value} = rb_ary_new2(0);"
        else
          c_ary = @insn.iseq.use_temporary_c_ary(@argc)
          @argc.times{|i| ret << "  #{c_ary}[#{i}] = #{param.shift};"}
          ret << "  #{@return_value} = rb_ary_new4((long)#{@argc}, #{c_ary});"
        end
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([Array])
      end

      def harmless?(recv_p)
        false
      end

      def side_effect?
        false
      end
    end

    class Newhash < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def propergate_exact_class(defs)
        @return_value.class_exact? ? false : @return_value.is_class_exact()
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        ret << "  cast_off_tmp = rb_hash_new();"
        bug() unless @argc % 2 == 0
        (@argc / 2).times{ ret << "  rb_hash_aset(cast_off_tmp, #{param.shift}, #{param.shift});"}
        ret << "  #{@return_value} = cast_off_tmp;"
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([Hash])
      end

      def harmless?(recv_p)
        false
      end

      def side_effect?
        false
      end
    end

    class Duparray < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
        bug() unless @argc == 1
        bug() unless @param[0].param_value.is_a?(Literal)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def propergate_exact_class(defs)
        @return_value.class_exact? ? false : @return_value.is_class_exact()
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        ary = param.shift
        bug() unless ary.is_a?(Literal)
        code = dont_duplicate_if_harmless(ary)
        code = "  #{@return_value} = rb_ary_resurrect(#{ary});" unless code
        ret << code
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([Array])
      end

      def side_effect?
        false
      end
    end

    class Tostring < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
        bug() unless @param.size() == 1
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(true)}
      end

      def propergate_exact_class(defs)
        @return_value.class_exact? ? false : @return_value.is_class_exact()
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        obj = param.shift
        if obj.is_just?(String)
          ret << "  #{@return_value} = #{obj};"
        else
          ret << "  #{@return_value} = rb_obj_as_string(#{obj});"
        end
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([String])
      end

      def harmless?(recv_p)
        @param[0].param_value.is_just?(String)
      end

      def side_effect?
        # FIXME return false when reciever class to_s method is no-side-effect.
        true
      end
    end

    class Toregexp < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def propergate_exact_class(defs)
        @return_value.class_exact? ? false : @return_value.is_class_exact()
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        # ruby doesn't export rb_reg_new_ary, so use rb_str_new, rb_str_append, and rb_reg_new_str
        opt = @operands[0]
        base = param.shift
        bug() unless base.class_exact? && base.is_just?(String)
        ret << "  cast_off_tmp = rb_str_dup(#{base});"
        until param.empty?
          ret << "  rb_str_append(cast_off_tmp, #{param.shift});"
        end
        ret << "  #{@return_value} = rb_reg_new_str(cast_off_tmp, (int)#{opt});"
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([Regexp])
      end

      def harmless?(recv_p)
        true
      end

      def side_effect?
        true
      end
    end

    class Concatstrings < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def propergate_exact_class(defs)
        @return_value.class_exact? ? false : @return_value.is_class_exact()
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        ret << "  cast_off_tmp = rb_str_new(0, 0);"
        @argc.times{ret << "  rb_str_append(cast_off_tmp, #{param.shift});"}
        ret << "  #{@return_value} = cast_off_tmp;"
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([String])
      end

      def harmless?(recv_p)
        true
      end

      def side_effect?
        false
      end
    end

    class Concatarray < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def propergate_exact_class(defs)
        @return_value.class_exact? ? false : @return_value.is_class_exact()
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        ary1 = param.shift
        ary2 = param.shift
        # FIXME C のヘッダに記述
        c_ary = @insn.iseq.use_temporary_c_ary(2)
        ret << <<-EOS
  #{c_ary}[0] = rb_check_convert_type(#{ary1}, T_ARRAY, "Array", "to_a");
  #{c_ary}[1] = rb_check_convert_type(#{ary2}, T_ARRAY, "Array", "to_a");
  if (NIL_P(#{c_ary}[0])) #{c_ary}[0] = rb_ary_new3(1, #{ary1});
  if (NIL_P(#{c_ary}[1])) #{c_ary}[1] = rb_ary_new3(1, #{ary2});
  if (#{c_ary}[0] == #{ary1}) #{c_ary}[0] = rb_ary_dup(#{ary1});
  #{@return_value} = rb_ary_concat(#{c_ary}[0], #{c_ary}[1]);
        EOS
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([Array])
      end

      def harmless?(recv_p)
        false # can be call to_a method
      end

      def side_effect?
        true
      end
    end

    class Newrange < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def propergate_exact_class(defs)
        @return_value.class_exact? ? false : @return_value.is_class_exact()
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        low = param.shift
        high = param.shift
        ret << "  #{@return_value} = rb_range_new(#{low}, #{high}, (int)#{@operands[0]});"
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([Range])
      end

      def harmless?(recv_p)
        false
      end

      def side_effect?
        false
      end
    end

    class OptRegexpmatch1 < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        r = param.shift
        obj = param.shift
        ret << "  #{@return_value} = rb_reg_match(#{r}, #{obj});"
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_dynamic()
      end

      def harmless?(recv_p)
        true
      end

      def side_effect?
        true
      end
    end

    class OptRegexpmatch2 < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(true)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        # FIXME 型を見て string だった場合は、分岐を消す
        obj2 = param.shift
        obj1 = param.shift
        if obj2.is_just?(String)
          ret << "  #{@return_value} = rb_reg_match(#{obj1}, #{obj2});"
        else
          id = @translator.allocate_id("=~".intern)
          ret << <<-EOS
  if (TYPE(#{obj2}) == T_STRING) {
      #{@return_value} = rb_reg_match(#{obj1}, #{obj2});
  }
  else {
      #{@return_value} = rb_funcall(#{obj2}, #{id}, 1, #{obj1});
  }
          EOS
        end
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_dynamic()
      end

      def harmless?(recv_p)
        true
      end

      def side_effect?
        true
      end
    end

    class Getspecial < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        key, type = *@operands
        if type == 0
          bug()
        else
          if @configuration.allow_builtin_variable_incompatibility?
            if type & 0x01 != 0
              case (type >> 1).chr
              when '&'
                ret << "  #{@return_value} = rb_reg_last_match(rb_backref_get());"
              when '`'
                ret << "  #{@return_value} = rb_reg_match_pre(rb_backref_get());"
              when '\''
                ret << "  #{@return_value} = rb_reg_match_post(rb_backref_get());"
              when '+'
                ret << "  #{@return_value} = rb_reg_match_last(rb_backref_get());"
              else
                bug()
              end
            else
              ret << "  #{@return_value} = rb_reg_nth_match((int)(#{type >> 1}), rb_backref_get());"
            end
          else
            bug()
          end
        end
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_dynamic()
      end

      def side_effect?
        false
      end
    end

    class ExpandarrayPre < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        # このチェックがなくならないことを前提に、この命令に対するガードを削除したので、
        # このチェックは削除しないこと
        ary = param.shift
        ret << "  if (TYPE(#{ary}) != T_ARRAY) #{@return_value} = rb_ary_to_ary(#{ary});"
        bug() unless param.empty?
        ret.join("\n")
      end

      def harmless?(recv_p)
        false # can be return self
      end

      def type_propergation(defs)
        @return_value.is_static([Array])
      end

      def side_effect?
        true
      end
    end

    class ExpandarrayLoop < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        index = @operands[0]
        ary = param.shift
        ret << <<-EOS
  if (RARRAY_LEN(#{ary}) > #{index}) {
    #{@return_value} = RARRAY_PTR(#{ary})[#{index}];
  } else {
    #{@return_value} = Qnil;
  }
        EOS
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_dynamic()
      end

      def side_effect?
        false
      end
    end

    class ExpandarraySplat < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        num = @operands[0]
        ary = param.shift
        ret << <<-EOS
  if (#{num} > RARRAY_LEN(#{ary})) {
    #{@return_value} = rb_ary_new();
  } else {
    #{@return_value} = rb_ary_new4(RARRAY_LEN(#{ary}) - #{num}, RARRAY_PTR(#{ary}) + #{num});
  }
        EOS
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([Array])
      end

      def side_effect?
        false
      end
    end

    class ExpandarrayPostLoop < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        num = @operands[0]
        index = @operands[1]
        ary = param.shift
        ret << <<-EOS
  if (RARRAY_LEN(#{ary}) < #{num - index}) {
    #{@return_value} = Qnil;
  } else {
    #{@return_value} = RARRAY_PTR(#{ary})[RARRAY_LEN(#{ary}) - #{num - index - 1}];
  }
        EOS
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_dynamic()
      end

      def side_effect?
        false
      end
    end

    class ExpandarrayPostSplat < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        num = @operands[0]
        ary = param.shift
        ret << <<-EOS
  if (RARRAY_LEN(#{ary}) < #{num}) {
    #{@return_value} = rb_ary_new4(1, RARRAY_PTR(#{ary}));
  } else {
    #{@return_value} = rb_ary_new4(RARRAY_LEN(#{ary}) - #{num - 1}, RARRAY_PTR(#{ary}));
  }
        EOS
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([Array])
      end

      def side_effect?
        false
      end
    end

    class Splatarray < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        ary = param.shift
        # FIXME ary の型を考慮
        # Nil にならないと分かっていたら、nil かどうかの確認は消せる
        ret << <<-EOS
  cast_off_tmp = rb_check_convert_type(#{ary}, T_ARRAY, "Array", "to_a");
  if (NIL_P(cast_off_tmp)) cast_off_tmp = rb_ary_new3(1, #{ary});
  #{@return_value} = cast_off_tmp;
        EOS
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([Array])
      end

      def harmless?(recv_p)
        false # can be return self
      end

      def side_effect?
        true
      end
    end

    class CheckincludearrayPre < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        ary = param.shift
        # このチェックがなくならないことを前提に、この命令に対するガードを削除したので、
        # このチェックは削除しないこと
        ret << "  if (TYPE(#{ary}) != T_ARRAY) #{@return_value} = rb_Array(#{ary});"
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([Array])
      end

      def side_effect?
        true
      end
    end

    class CheckincludearrayCase < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        ary = param.shift
        obj = param.shift
        ret << <<-EOS
  cast_off_tmp = Qfalse;
  {
    int i;
    for (i = 0; i < RARRAY_LEN(#{ary}); i++) {
      if (RTEST(rb_funcall2(RARRAY_PTR(#{ary})[i], idEqq, 1, &#{obj}))) {
        cast_off_tmp = Qtrue;
        break;
      }
    }
  }
  #{@return_value} = cast_off_tmp;
        EOS
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([TrueClass, FalseClass])
      end

      def harmless?(recv_p)
        false
      end

      def side_effect?
        true
      end
    end

    class CheckincludearrayWhen < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        ary = param.shift
        ret << <<-EOS
  cast_off_tmp = Qfalse;
  {
    int i;
    for (i = 0; i < RARRAY_LEN(#{ary}); i++) {
      if (RTEST(RARRAY_PTR(#{ary})[i])) {
        cast_off_tmp = Qtrue;
        break;
      }
    }
  }
  #{@return_value} = cast_off_tmp;
        EOS
        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        @return_value.is_static([TrueClass, FalseClass])
      end

      def side_effect?
        false
      end
    end

    class Defined < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
        argv = insn.argv
        @defined_t = argv[0]
        sym = argv[1]
        bug() unless sym.instance_of?(Symbol)
        @id = @translator.allocate_id(sym)
        @needstr = argv[2]    # Qtrue or Qfalse
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        val = param.pop()

        case @defined_t
        when DEFINED_IVAR
          ret << <<-EOS
  if (rb_ivar_defined(self, #{@id})) {
    #{@return_value} = #{@needstr ? 'rb_str_new2("instance-variable")' : 'Qtrue'};
  } else {
    #{@return_value} = Qnil;
  }
          EOS
        when DEFINED_GVAR
          ret << <<-EOS
  if (rb_gvar_defined(rb_global_entry(#{@id}))) {
    #{@return_value} = #{@needstr ? 'rb_str_new2("global-variable")' : 'Qtrue'};
  } else {
    #{@return_value} = Qnil;
  }
          EOS
        when DEFINED_FUNC
          ret << <<-EOS
  if (rb_method_boundp(rb_class_of(#{val}), #{@id}, 0)) {
    #{@return_value} = #{@needstr ? 'rb_str_new2("method")' : 'Qtrue'};
  } else {
    #{@return_value} = Qnil;
  }
          EOS
        when DEFINED_CONST
          ret << <<-EOS
  if (cast_off_const_defined(#{val}, #{@id})) {
    #{@return_value} = #{@needstr ? 'rb_str_new2("constant")' : 'Qtrue'};
  } else {
    #{@return_value} = Qnil;
  }
          EOS
        else
          bug()
        end

        bug() unless param.empty?
        ret.join("\n")
      end

      def type_propergation(defs)
        if @needstr
          @return_value.is_static([NilClass, String])
        else
          @return_value.is_static([NilClass, TrueClass])
        end
      end

      def harmless?(recv_p)
        true
      end

      def should_be_alive?
        false
      end

      def side_effect?
        false
      end
    end

    class CastOffFetchArgs < VMInsnIR
      def initialize(param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        argv = @operands
        if argv[0]
          # root iseq
          must, opt, rest, post, block, args = *argv[0]
          ret << <<-EOS
  {
    int num = rb_scan_args(argc, argv, \"#{must}#{opt}#{rest}#{post}#{block}\", &#{args.join(", &")});
    #{@return_value} = INT2FIX(num);
  }
          EOS
        else
          # child iseq
          bug() if @translator.inline_block?
          ret << "  #{@return_value} = INT2FIX(num);"
        end
        bug() unless param.empty?
        ret.join("\n")
      end
      
      def type_propergation(defs)
        @return_value.is_static([Fixnum])
      end

      def side_effect?
        true
      end
    end

    class LoopIR < CallIR
      attr_reader :loopkey, :loop_phase

      def initialize(loopkey, phase, param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
        @loop_phase = phase
        @loopkey = loopkey
      end

      def propergate_guard_usage()
        params = param_irs()
        return if params.empty?
        recv = params.shift()
        recv.need_guard(true)
        params.each{|p| p.need_guard(false)}
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        recv, *rest = *param
        s_param = rest.empty? ? nil : ", #{rest.join(", ")}"
        case @loop_phase
        when :cast_off_prep
          if @translator.inline_block?
            unless @loopkey.resolved?
              @translator.unsupported_or_re_compilation(<<-EOS)

<<< Failed to resolve iterater reciever type >>>
You should specify iterator reciever type, method name = #{@loopkey.id}.
-------------------------------------------------------------------------
Target file is (#{@translator.target_name()}).
Call site is (#{@insn}).
              EOS
            end
            @dependency.add(@loopkey.klass, @loopkey.id, true)
            ret << "  #{@return_value} = #{@loopkey.prep_func}(&#{@loopkey}, #{recv}, #{@argc - 1}#{s_param});"
          else
            ret << <<-EOS
  cast_off_set_block(#{@loopkey.block_iseq.block_generator()}(self));
  #{@return_value} = rb_funcall(#{recv}, #{@translator.allocate_id(@loopkey.id)}, #{@argc - 1}#{s_param});
#{@insn.iseq.update_dfp()}
            EOS
          end
        when :cast_off_loop
          if @translator.inline_block?
            bug() unless param.size == 1
            ret << "  #{@return_value} = #{@loopkey.loop_func}(&#{@loopkey}, #{param[0]}, #{@loopkey.argc}, cast_off_argv, #{@loopkey.splat? ? 1 : 0}, #{@loopkey.arg_argc}, #{@loopkey.arg_post_len}, #{@loopkey.arg_post_start}, #{@loopkey.arg_rest_index});"
          end
        when :cast_off_finl
          if @translator.inline_block?
            bug() unless param.empty?
            ret << "  #{@return_value} = #{@loopkey.finl_func}(&#{@loopkey});"
          end
        else
          bug()
        end
        ret.join("\n")
      end

      def type_propergation(defs)
        if @loop_phase == :cast_off_prep
          recv = @param[0].param_value
          @loopkey.resolve(recv.types) unless recv.undefined? || recv.dynamic?
        end

        case @loop_phase
        when :cast_off_prep
          return @return_value.is_dynamic()
        when :cast_off_loop
          return @return_value.is_static([TrueClass, FalseClass])
        when :cast_off_finl
          return @return_value.is_dynamic()
        end
        bug()
      end

      def harmless?(recv_p)
        false
      end

      def should_be_alive?
        true
      end

      def to_verbose_string()
        recv = param_variables()[0]
        "[#{recv.dynamic? ? "dynamic" : recv.types.join(", ")}]##{@loopkey.id}"
      end
    end

    SupportLoopInstruction = {
      MethodWrapper.new(ClassWrapper.new(Array, true),  :map)   => 'Array_map',
      MethodWrapper.new(ClassWrapper.new(Array, true),  :map!)  => 'Array_map_bang',
      MethodWrapper.new(ClassWrapper.new(Array, true),  :each)  => 'Array_each',
      MethodWrapper.new(ClassWrapper.new(Fixnum, true), :times) => 'Fixnum_times',
    }

    class LoopKey
      include CastOff::Util

      attr_reader :id, :key, :argc, :klass
      attr_accessor :block_iseq

      def initialize(id, key, args, insn, translator)
        @id = id          # method name
        @key = key          # loop number
        @args = args
        @argc = args.size

        @translator = translator
        @insn = insn

        @signiture = nil
        @klass = nil
      end

      def resolved?
        !!@signiture
      end

      def resolve(classes)
        classes.each do |c|
          bug() unless c.is_a?(ClassWrapper)
          # method exist
          begin
            sign = SupportLoopInstruction[MethodWrapper.new(c, @id)]
          rescue CompileError
            sign = nil
          end
          if @translator.inline_block? && !sign
            @translator.unsupported_or_re_compilation("Unsupported loop method: #{c}##{@id}")
          end
          @translator.unsupported_or_re_compilation(<<-EOS) if @signiture && @signiture != sign && @translator.inline_block?

Currently, CastOff doesn't support a method invocation which target is not single and which takes a block.
#{@klass}##{@id} and #{c}##{@id} are different methods.
----------------------------------------------------------------------------------------------------------
Target file is (#{@translator.target_name()}).
Call site is (#{@insn}).
          EOS
          @signiture = sign
          @klass = c
        end
        bug() if @translator.inline_block? && !resolved?
      end

      def to_s
        (resolved? && @signiture) ? "cast_off_#{@signiture}_#{@key}" : "unresolved"
      end

      def splat?
        bug() unless @block_iseq
        @block_iseq.args.splat?
      end

      def arg_argc
        bug() unless @block_iseq
        @block_iseq.args.argc
      end

      def arg_post_len
        bug() unless @block_iseq
        @block_iseq.args.post_len
      end

      def arg_post_start
        bug() unless @block_iseq
        @block_iseq.args.post_start
      end

      def arg_rest_index
        bug() unless @block_iseq
        @block_iseq.args.rest_index
      end

      def decl?
        resolved?
      end

      def decl
        bug() unless resolved?
        bug() unless @signiture
        "cast_off_#{@signiture}_t #{self.to_s}"
      end

      def prep_func
        bug() unless resolved?
        bug() unless @signiture
        "cast_off_#{@signiture}_prep"
      end

      def loop_func
        bug() unless resolved?
        bug() unless @signiture
        "cast_off_#{@signiture}_loop"
      end

      def finl_func
        bug() unless resolved?
        bug() unless @signiture
        "cast_off_#{@signiture}_finl"
      end

      def dopt_func
        bug() unless resolved?
        bug() unless @signiture
        "cast_off_#{@signiture}_construct_frame"
      end
    end

    SPLATCALL_LIMIT = 25
    class YieldIR < CallIR
      def initialize(flags, param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
        @flags = flags
      end

      def propergate_guard_usage()
        params = param_irs()
        params.each{|p| p.need_guard(splatyield?)}
      end

      SPLATCALL_TEMPLATE_YIELD = ERB.new(<<-EOS, 0, '%-', 'io')
%bug() unless param.size > 0
  {
    int argc = <%= @argc - 1 %>;
    VALUE buf[<%= SPLATCALL_LIMIT %>]; /* FIXME */
    VALUE *argv = buf;
%splat_param  = param.last()
%normal_param = param.slice(0, param.size() - 1)
    VALUE ary = <%= splat_param %>;
%if splat_param.is_just?(Array)
%  is_ary = true
    VALUE tmp = ary;
%else
%  is_ary = false
    VALUE tmp = rb_check_convert_type(ary, T_ARRAY, "Array", "to_a");
%end

%normal_param.each_with_index do |p, i|
    argv[<%= i %>] = <%= p %>;
%end
%unless is_ary
    if (NIL_P(tmp)) {
      /* do nothing */
    } else {
%else
    {
%end
      VALUE *ptr;
      long i, len = RARRAY_LEN(tmp);
      ptr = RARRAY_PTR(tmp);
      argc += len;
      if (UNLIKELY(argc > <%= SPLATCALL_LIMIT %>)) {
        VALUE *newbuf = ALLOCA_N(VALUE, argc);
%normal_param.size.times do |i|
        newbuf[i] = argv[i];
%end
        argv = newbuf;
      }
      for (i = 0; i < len; i++) {
        argv[<%= normal_param.size %> + i] = ptr[i];
      }
    }
    rb_yield_values2(argc, argv);
  }
      EOS

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()

        if splatyield?
          ret << SPLATCALL_TEMPLATE_YIELD.trigger(binding)
        else
          if param.empty?
            ret << "  #{@return_value} = rb_yield(Qundef);"
          else
            ret << "  #{@return_value} = rb_yield_values(#{param.size}, #{param.join(", ")});"
          end
        end

        ret.join("\n")
      end

      def to_verbose_string()
        "yield"
      end

      def type_propergation(defs)
        @return_value.is_dynamic()
      end

      def harmless?(recv_p)
        false
      end

      def should_be_alive?
        true
      end

      def side_effect?
        true
      end

      def splatyield?
        (@flags & VM_CALL_ARGS_SPLAT_BIT) != 0
      end
    end

    class InvokeIR < CallIR
      attr_reader :method_id

      IncompatMethods = [
        :eval,         # use vm_get_ruby_level_caller_cfp
        :binding,      # use vm_get_ruby_level_caller_cfp
        :block_given?, # use vm_get_ruby_level_caller_cfp
        :iterator?,    # use vm_get_ruby_level_caller_cfp
      ]

      def initialize(mid, flags, param, argc, return_value, insn, cfg)
        super(param, argc, return_value, insn, cfg)
        @flags = flags
        @method_id = mid

        if fcall? && IncompatMethods.include?(@method_id)
          raise(UnsupportedError.new(<<-EOS))

Currently, #{@method_id} method is incompatible.
You should not use #{@method_id} method in compilation target of CastOff.
          EOS
        end
      end

      def propergate_guard_usage()
        params = param_irs()
        bug() if params.empty?
        recv = params.shift()
        recv.need_guard(true)
        if splatcall? || specializecall?
          params.each{|p| p.need_guard(true)}
        else
          params.each{|p| p.need_guard(false)}
        end
      end

      def specializecall?
        params = param_variables()
        recv, *args = *params
        bug() if recv.undefined?
        if recv.dynamic? || @configuration.force_dispatch_method?
          return false
        else
          bug() if recv.types.empty?
          recv.types.each do |klass|
            bug() unless klass.is_a?(ClassWrapper)
            next if klass.get_method_type(@method_id) != :cfunc
            next unless @configuration.should_be_call_directly?(klass, @method_id)
            cfunc_argc = klass.get_cfunc_argc(@method_id)
            bug() unless cfunc_argc
            if klass.String? || klass.Array? || klass.Fixnum? || klass.Float?
              # != とかのために、クラス単位で分ける必要がある。
              return true if SpecializeTable0[[MethodWrapper.new(klass, @method_id), @argc]]
            end
            # FIXME specializecall 側を修正
            return true if SpecializeTable1[[@method_id, @argc, MethodWrapper.new(klass, @method_id)]]
          end
        end
        false
      end

      def to_verbose_string()
        recv = param_variables()[0]
        "[#{recv.dynamic? ? "dynamic" : recv.types.join(", ")}]##{@method_id}"
      end

      def fcall?
        bug() unless @flags
        (@flags & VM_CALL_FCALL_BIT) != 0
      end

      def blockarg?
        bug() unless @flags
        (@flags & VM_CALL_ARGS_BLOCKARG_BIT) != 0
      end

      def splatcall?
        bug() unless @flags
        (@flags & VM_CALL_ARGS_SPLAT_BIT) != 0
      end

      SPLATCALL_TEMPLATE_CFUNC = ERB.new(<<-EOS, 0, '%-', 'io')
%bug() unless param.size > 0
  {
    int argc = <%= argc - 2 %>;
%splat_param  = param.last()
%normal_param = param.slice(0, param.size() - 1)
    VALUE ary = <%= splat_param %>;
%if splat_param.is_just?(Array)
%  is_ary = true
    VALUE tmp = ary;
%else
%  is_ary = false
    VALUE tmp = rb_check_convert_type(ary, T_ARRAY, "Array", "to_a");
%end
    VALUE *ptr = NULL;

%unless is_ary
    if (NIL_P(tmp)) {
      /* do nothing */
    } else {
%end
      ptr = RARRAY_PTR(tmp);
      argc += RARRAY_LEN(tmp);
%unless is_ary
    }
%end
    if (UNLIKELY(argc != <%= splat_call_argc %>)) {
      rb_raise(rb_eCastOffExecutionError, "wrong number of arguments (<%= splat_call_argc %> for %d)", argc);
    }
%unless is_ary
    if (ptr) {
%end
%rest = ""
%(splat_call_argc - normal_param.size).times do |i|
%  rest += ", ptr[\#{i}]"
%end
      <%= @return_value %> = <%= fnam_code %>(<%= recv %><%= normal_param.empty? ? nil : ", \#{normal_param.join(", ")}" %><%= rest %>);
%unless is_ary
    } else {
      <%= @return_value %> = <%= fnam_code %>(<%= recv %><%= normal_param.empty? ? nil : ", \#{normal_param.join(", ")}" %>);
    }
%end
  }
      EOS

      SPLATCALL_TEMPLATE_ARGV = ERB.new(<<-EOS, 0, '%-', 'io')
%bug() unless param.size > 0
  {
    int argc = <%= argc - 2 %>;
    VALUE buf[<%= SPLATCALL_LIMIT %>];
    VALUE *argv = buf;
%splat_param  = param.last()
%normal_param = param.slice(0, param.size() - 1)
    VALUE ary = <%= splat_param %>;
%if splat_param.is_just?(Array)
%  is_ary = true
    VALUE tmp = ary;
%else
%  is_ary = false
    VALUE tmp = rb_check_convert_type(ary, T_ARRAY, "Array", "to_a");
%end

%normal_param.each_with_index do |p, i|
    argv[<%= i %>] = <%= p %>;
%end
%unless is_ary
    if (NIL_P(tmp)) {
      /* do nothing */
    } else {
%else
    {
%end
      VALUE *ptr;
      long i, len = RARRAY_LEN(tmp);
      ptr = RARRAY_PTR(tmp);
      argc += len;
      if (UNLIKELY(argc > <%= SPLATCALL_LIMIT %>)) {
        VALUE *newbuf = ALLOCA_N(VALUE, argc);
%normal_param.size.times do |i|
        newbuf[i] = argv[i];
%end
        argv = newbuf;
      }
      for (i = 0; i < len; i++) {
        argv[<%= normal_param.size %> + i] = ptr[i];
      }
    }
    <%= call_code %>
  }
      EOS

      def funcall_fptr(klass, argc, suffix = nil)
        bug() unless klass.nil? || klass.instance_of?(ClassWrapper)
        (klass && !suffix) ? @translator.allocate_function_pointer(klass, @method_id, -3, argc) : "rb_funcall#{suffix}"
      end

      def funcall_code(klass, id, recv, param, argc)
        if blockarg?
          bug() if param.empty?
          blockarg = param.last()
          param = param.slice(0, param.size - 1)
          argc = argc - 1
          ret = "  handle_blockarg(#{blockarg});\n" 
          if splatcall?
            fptr = funcall_fptr(klass, nil, 2)
            call_code = "#{@return_value} = #{fptr}(#{recv}, #{id}, argc, argv);"
            ret += SPLATCALL_TEMPLATE_ARGV.trigger(binding)
          else
            fptr = funcall_fptr(klass, param.size)
            ret += "  #{@return_value} = #{fptr}(#{recv}, #{id}, #{param.size}#{param.empty? ? nil : ", #{param.join(", ")}"});"
          end
          ret
        else
          if splatcall?
            fptr = funcall_fptr(klass, nil, 2)
            call_code = "#{@return_value} = #{fptr}(#{recv}, #{id}, argc, argv);"
            SPLATCALL_TEMPLATE_ARGV.trigger(binding)
          else
            fptr = funcall_fptr(klass, param.size)
            "  #{@return_value} = #{fptr}(#{recv}, #{id}, #{argc - 1}#{param.empty? ? nil : ", #{param.join(", ")}"});"
          end
        end
      end

      StringWrapper       = ClassWrapper.new(String, true)
      FixnumWrapper       = ClassWrapper.new(Fixnum, true)
      FloatWrapper        = ClassWrapper.new(Float, true)
      ArrayWrapper        = ClassWrapper.new(Array, true)
      ObjectWrapper       = ClassWrapper.new(Object, true)
      NilClassWrapper     = ClassWrapper.new(NilClass, true)
      FalseClassWrapper   = ClassWrapper.new(FalseClass, true)
      BasicObjectWrapper  = ClassWrapper.new(BasicObject, true)
      KernelWrapper       = ModuleWrapper.new(Kernel)
      SpecializeTable0 = {
        [MethodWrapper.new(StringWrapper, :<<), 2]     => [['concat',       [String], nil, String, false, false]],
        [MethodWrapper.new(StringWrapper, :+), 2]      => [['plus',         [String], nil, String, false, false]],
        [MethodWrapper.new(StringWrapper, :==), 2]     => [['eq',           [String], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(StringWrapper, :===), 2]    => [['eqq',          [String], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(StringWrapper, :!=), 2]     => [['neq',          [String], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(StringWrapper, :empty?), 1] => [['empty_p',      [], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(ArrayWrapper,  :[]), 2]     => [['entry',        [Fixnum], nil, nil, false, false]],
        [MethodWrapper.new(ArrayWrapper,  :[]=), 3]    => [['store',        [Fixnum, nil], nil, nil, false, false]],
        [MethodWrapper.new(ArrayWrapper,  :length), 1] => [['length',       [], Fixnum, nil, false, false]], # FIXME
        [MethodWrapper.new(ArrayWrapper,  :size), 1]   => [['size',         [], Fixnum, nil, false, false]], # FIXME
        [MethodWrapper.new(ArrayWrapper,  :empty?), 1] => [['empty_p',      [], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(ArrayWrapper,  :last), 1]   => [['last',         [], nil, nil, false, false]],
        [MethodWrapper.new(ArrayWrapper,  :first), 1]  => [['first',        [], nil, nil, false, false]],
        [MethodWrapper.new(FixnumWrapper, :+), 2]      => [['fixnum_plus',  [Fixnum], nil, [Fixnum, Bignum], false, true], ['float_plus',   [Float],   nil, Float, true, true]], # FIXME
        [MethodWrapper.new(FixnumWrapper, :-), 2]      => [['fixnum_minus', [Fixnum], nil, [Fixnum, Bignum], false, true], ['float_minus',  [Float],   nil, Float, true, true]], # FIXME
        [MethodWrapper.new(FixnumWrapper, :*), 2]      => [['fixnum_mult',  [Fixnum], nil, [Fixnum, Bignum], false, true], ['float_mult',   [Float],   nil, Float, true, true]], # FIXME
        [MethodWrapper.new(FixnumWrapper, :<=), 2]     => [['le',           [Fixnum], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(FixnumWrapper, :<), 2]      => [['lt',           [Fixnum], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(FixnumWrapper, :>=), 2]     => [['ge',           [Fixnum], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(FixnumWrapper, :>), 2]      => [['gt',           [Fixnum], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(FixnumWrapper, :==), 2]     => [['eq',           [Fixnum], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(FixnumWrapper, :===), 2]    => [['eqq',          [Fixnum], nil, [TrueClass,  FalseClass], false, false]],
        [MethodWrapper.new(FixnumWrapper, :&), 2]      => [['and',          [Fixnum], Fixnum, nil, false, false]], # FIXME
        [MethodWrapper.new(FloatWrapper,  :+), 2]      => [['float_plus',   [Float],   nil, Float, true, true], ['fixnum_plus',   [Fixnum],  nil, Float, true, true]],
        [MethodWrapper.new(FloatWrapper,  :-), 2]      => [['float_minus',  [Float],   nil, Float, true, true], ['fixnum_minus',  [Fixnum],  nil, Float, true, true]],
        [MethodWrapper.new(FloatWrapper,  :*), 2]      => [['float_mult',   [Float],   nil, Float, true, true], ['fixnum_mult',   [Fixnum],  nil, Float, true, true]],
        [MethodWrapper.new(FloatWrapper,  :/), 2]      => [['float_div',    [Float],   nil, Float, true, true], ['fixnum_div',    [Fixnum],  nil, Float, true, true]],
        [MethodWrapper.new(FloatWrapper,  :<=), 2]     => [['float_le',     [Float],   nil, [TrueClass,  FalseClass], false, true],
                                                           ['fixnum_le',    [Fixnum],  nil, [TrueClass,  FalseClass], false, true]],
        [MethodWrapper.new(FloatWrapper,  :<), 2]      => [['float_lt',     [Float],   nil, [TrueClass,  FalseClass], false, true],
                                                           ['fixnum_lt',    [Fixnum],  nil, [TrueClass,  FalseClass], false, true]],
        [MethodWrapper.new(FloatWrapper,  :>=), 2]     => [['float_ge',     [Float],   nil, [TrueClass,  FalseClass], false, true],
                                                           ['fixnum_ge',    [Fixnum],  nil, [TrueClass,  FalseClass], false, true]],
        [MethodWrapper.new(FloatWrapper,  :>), 2]      => [['float_gt',     [Float],   nil, [TrueClass,  FalseClass], false, true],
                                                           ['fixnum_gt',    [Fixnum],  nil, [TrueClass,  FalseClass], false, true]],
        [MethodWrapper.new(FloatWrapper,  :==), 2]     => [['float_eq',     [Float],   nil, [TrueClass,  FalseClass], false, true],
                                                           ['fixnum_eq',    [Fixnum],  nil, [TrueClass,  FalseClass], false, true]],
        [MethodWrapper.new(FixnumWrapper, :!=), 2]     => [['fixnum_neq',   [Fixnum],  nil, [TrueClass,  FalseClass], false, true],
                                                           ['float_neq',    [Float],   nil, [TrueClass,  FalseClass], false, true]],
        [MethodWrapper.new(FloatWrapper,  :!=), 2]     => [['float_neq',    [Float],   nil, [TrueClass,  FalseClass], false, true],
                                                           ['fixnum_neq',   [Fixnum],  nil, [TrueClass,  FalseClass], false, true]],
        [MethodWrapper.new(FloatWrapper,  :===), 2]    => [['float_eqq',    [Float],   nil, [TrueClass,  FalseClass], false, true],
                                                           ['fixnum_eqq',   [Fixnum],  nil, [TrueClass,  FalseClass], false, true]],
        [MethodWrapper.new(FixnumWrapper, :-@), 1]     => [['uminus',       [], nil, [Fixnum, Bignum], false, true]],
        [MethodWrapper.new(FloatWrapper, :-@), 1]      => [['uminus',       [], nil, Float, true, true]],
        [MethodWrapper.new(FixnumWrapper, :to_f), 1]   => [['to_f',         [], nil, Float, true, true]],
        [MethodWrapper.new(FloatWrapper, :to_f), 1]    => [['to_f',         [], nil, Float, true, false]],
        [MethodWrapper.new(FloatWrapper, :to_i), 1]    => [['to_i',         [], nil, Float, false, true]],
      }
      SpecializeTable1 = {
        [:==,   2, MethodWrapper.new(ObjectWrapper, :==)]      => :specialized_object_eq,
        [:nil?, 1, MethodWrapper.new(NilClassWrapper, :nil?)]  => :specialized_nilclass_nil?,
        [:nil?, 1, MethodWrapper.new(KernelWrapper, :nil?)]    => :specialized_kernel_nil?,
        [:!,    1, MethodWrapper.new(BasicObjectWrapper, :!)]  => :specialized_basicobject_not,
      }

      def specialized_object_eq(klass, mid, argc, recv, param)
        bug() unless mid == :==
        bug() unless argc == 2
        bug() unless param.size() == 1
        return "  #{@return_value} = (#{recv} == #{param[0]}) ? Qtrue : Qfalse;"
      end

      def specialized_nilclass_nil?(klass, mid, argc, recv, param)
        bug() unless mid == :nil?
        bug() unless argc == 1
        bug() unless param.empty?
        return "  #{@return_value} = Qtrue;"
      end

      def specialized_kernel_nil?(klass, mid, argc, recv, param)
        bug() unless mid == :nil?
        bug() unless argc == 1
        bug() unless param.empty?
        return "  #{@return_value} = Qfalse;"
      end

      def specialized_basicobject_not(klass, mid, argc, recv, param)
        bug() unless mid == :!
        bug() unless argc == 1
        bug() unless param.empty?
        classes = recv.types
        case classes.size
        when 0
          bug()
        when 1
          case classes[0]
          when NilClassWrapper, FalseClassWrapper
            return "  #{@return_value} = Qtrue;"
          else
            return "  #{@return_value} = Qfalse;"
          end
        when 2
          if classes == [NilClassWrapper, FalseClassWrapper] || classes == [FalseClassWrapper, NilClassWrapper]
            return "  #{@return_value} = Qtrue;"
          elsif !classes.include?(NilClassWrapper) && !classes.include?(FalseClassWrapper)
            return "  #{@return_value} = Qfalse;"
          else
            return "  #{@return_value} = RTEST(#{recv}) ? Qfalse : Qtrue;"
          end
        else
          return "  #{@return_value} = RTEST(#{recv}) ? Qfalse : Qtrue;"
        end
        bug()
      end

      def unboxed_decl(v)
        bug() unless v.is_a?(Variable)
        bug() if v.dynamic?
        bug() unless v.types.size == 1
        c = v.types[0]
        bug() unless c.is_a?(ClassWrapper)
        case c
        when FloatWrapper
          'double'
        when FixnumWrapper
          'long'
        else
          bug()
        end
      end

      def specialized_code(klass, mid, argc, recv, param)
        bug() unless klass.is_a?(ClassWrapper)
        return false unless @configuration.enable_inline_api?
        # FIXME ロード時に、関数ポインタが想定しているものと同一であることをチェック
        if klass.String? || klass.Array? || klass.Fixnum? || klass.Float?
          entries = SpecializeTable0[[MethodWrapper.new(klass, mid), argc]]
          return false unless entries
          entry = nil
          entries.each do |e|
            bug() unless e.size == 6
            name, t_param, t_result, exact_classes, can_unbox_result, can_unbox_param = e
            bug("param = #{param}, t_param = #{t_param}") unless param.size == t_param.size
            fin = true
            (param + [@return_value]).zip(t_param + [t_result]).each do |p, t|
              next if t.nil?
              unless p.is_just?(t)
                fin = false
                break
              end
            end
            if fin
              entry = e
              break
            end
          end
          return false unless entry
          name, t_param, t_result, exact_classes, can_unbox_result, can_unbox_param = entry

          s_param = param.empty? ? '' : ", #{param.join(", ")}"
          if can_unbox_param || can_unbox_result
            bug() if !can_unbox_param && ([recv] + param).find{|p| p.unboxed? }
            suffix = ([recv] + param).map{|p| p.unboxed? ? unboxed_decl(p) : 'VALUE'}
            bug() if !can_unbox_result && @return_value.unboxed?
            suffix << (@return_value.unboxed? ? unboxed_decl(@return_value) : 'VALUE')
            suffix = suffix.join('_')
            return "  #{@return_value} = cast_off_inline_#{klass.to_s.downcase}_#{name}_#{suffix}(#{recv}#{s_param});"
          else
            return "  #{@return_value} = cast_off_inline_#{klass.to_s.downcase}_#{name}(#{recv}#{s_param});"
          end
        else
          m = SpecializeTable1[[mid, argc, MethodWrapper.new(klass, mid)]]
          return m ? __send__(m, klass, mid, argc, recv, param) : false
        end
        bug()
      end

      def call_cfunc_code(klass, mid, cfunc_argc, recv, param, argc)
        bug() unless klass.is_a?(ClassWrapper)
        bug() unless @configuration.should_be_call_directly?(klass, mid)
        if !splatcall? && sp = specialized_code(klass, mid, argc, recv, param)
          return sp
        else
          id = @translator.allocate_id(mid)
          ary = []
          if @configuration.enable_trace?
            ary << "#ifdef CAST_OFF_ENABLE_TRACE"
            ary << "  trace_recv = #{recv};  trace_klass = rb_class_of(#{recv});"
            ary << "  EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, trace_recv, #{id}, trace_klass);"
            ary << "#endif"
          end
          fptr = @translator.allocate_function_pointer(klass, mid, cfunc_argc, param.size)
          case cfunc_argc
          when -2
            if splatcall?
              return nil # use funcall
            else
              c_ary = @insn.iseq.use_temporary_c_ary(param.size)
              param.each_with_index do |arg, i|
                ary << "  #{c_ary}[#{i}] = #{arg};"
              end
              ary << "  #{@return_value} = (*#{fptr})(#{recv}, rb_ary_new4(#{argc - 1}, #{c_ary}));"
            end
          when -1
            if splatcall?
              call_code = "#{@return_value} = (*#{fptr})(argc, argv, #{recv});"
              ary << SPLATCALL_TEMPLATE_ARGV.trigger(binding)
            else
              c_ary = @insn.iseq.use_temporary_c_ary(param.size)
              param.each_with_index do |arg, i|
                ary << "  #{c_ary}[#{i}] = #{arg};"
              end
              ary << "  #{@return_value} = (*#{fptr})(#{argc - 1}, #{c_ary}, #{recv});"
            end
          when 0..15
            if splatcall?
              splat_call_argc = cfunc_argc
              fnam_code = "(*#{fptr})"
              ary << SPLATCALL_TEMPLATE_CFUNC.trigger(binding)
            else
              ary << "  #{@return_value} = (*#{fptr})(#{recv}#{param.empty? ? nil : ", #{param.join(", ")}"});"
            end
          else
            raise(CompileError.new("too many arguments #{klass}##{mid}"))
          end
          if @configuration.enable_trace?
            ary << "#ifdef CAST_OFF_ENABLE_TRACE"
            ary << "  EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, trace_recv, #{id}, trace_klass);"
            ary << "#endif"
          end
          return ary.join("\n")
        end
        bug()
      end

      def recursive_call_class?(klass, mid)
        same_class = false
        bug() unless klass.is_a?(ClassWrapper)
        if @translator.reciever_class && @translator.reciever_class.include?(klass)
          same_class = true
        end
        if same_class && mid == @translator.mid
          true
        else
          false
        end
      end

      def recursive_call_var?(recv, mid)
        same_class = false
        if @translator.reciever_class && @translator.reciever_class.size() == 1
          same_class = true if recv.is_just?(@translator.reciever_class[0])
        end
        recv_defn = param_irs.first.get_definition(recv)
        if recv_defn.size == 1 && (@translator.inline_block? || @insn.iseq.root?)
          recv_defn = recv_defn.first
          same_class |= recv_defn.is_a?(SubIR) && recv_defn.src.is_a?(Self)
        end
        if same_class && mid == @translator.mid
          true
        else
          false
        end
      end

      def recursive_call_code(recv, param, argc)
        return nil if !@translator.inline_block?
        fname = @translator.this_function_name()
        if @translator.complex_call?
          if splatcall?
            call_code = "#{@return_value} = #{fname}(argc, argv, #{recv});"
            return SPLATCALL_TEMPLATE_ARGV.trigger(binding)
          else
            ret = ""
            c_ary = @insn.iseq.use_temporary_c_ary(param.size)
            param.each_with_index do |arg, i|
              ret += "  #{c_ary}[#{i}] = #{arg};\n"
            end
            return ret + "  #{@return_value} = #{fname}(#{argc - 1}, #{c_ary}, #{recv});"
          end
        else
          if splatcall?
            splat_call_argc = @translator.root_iseq.args.arg_size
            fnam_code = fname
            return SPLATCALL_TEMPLATE_CFUNC.trigger(binding)
          else
            if param.size == @translator.root_iseq.args.arg_size
              return "  #{@return_value} = #{fname}(#{recv}#{param.empty? ? nil : ", #{param.join(", ")}"});"
            else
              return nil
            end
          end
        end
        bug()
      end

      def same_call_code?(ary)
        bug() if ary.empty?
        code = ary[0][1]
        ary.each{|(k, c)| return false unless code == c}
        true
      end

      FuncallThreshold = 10
      MultiCallTemplate = ERB.new(<<-'end', 0, '%-', 'io')
%ary = []
%mid = @method_id
%if types.size < FuncallThreshold
%  funcall = false
%  types.each do |klass|
%    if @translator.get_c_classname(klass)
%      call_code = not_funcall_code(klass, mid, recv, param, @argc)
%      if call_code
%        ary << [klass, call_code]
%      else
%        begin
%          @dependency.add(klass, @method_id, false)
%          ary << [klass, funcall_code(klass, id, recv, param, @argc)]
%        rescue CompileError => e
%          funcall = true
%          dlog("catch exception #{e}")
%        end
%      end
%    else
%      funcall = true
%    end
%  end
%else
%  funcall = true
%end
%if ary.empty?
%  bug() unless funcall
<%= funcall_code(nil, id, recv, param, @argc) %>
%elsif !funcall && same_call_code?(ary)
<%= ary[0][1] %>
%else
  cast_off_tmp = rb_class_of(<%= recv %>);
  if (0) {
%  ary.each do |(klass, call_code)|
  } else if (cast_off_tmp == <%= @translator.get_c_classname(klass) %>) {
  <%= call_code %>
%  end
  } else {
%  if funcall
  <%= funcall_code(nil, id, recv, param, @argc) %>
%  else # empty_method_table_p に通った特異クラスがくる可能性がある。
  <%= funcall_code(nil, id, recv, param, @argc) %>
%  end
  }
%end

      end

      def not_funcall_code(klass, mid, recv, param, argc)
        bug() unless klass.is_a?(ClassWrapper)
        code = recursive_call_code(recv, param, argc) if recursive_call_class?(klass, mid)
        return code if code
        case klass.get_method_type(mid)
        when :cfunc
          cfunc_argc = klass.get_cfunc_argc(mid)
          bug() unless cfunc_argc
          if @configuration.should_be_call_directly?(klass, mid)
            @dependency.add(klass, mid, false)
            return call_cfunc_code(klass, mid, cfunc_argc, recv, param, argc)
          else
            return nil # shoud be use funcall
          end
        when :attrset
          raise(CompileError.new("invalid call site")) if splatcall? || param.size() != 1
          @dependency.add(klass, mid, false)
          return "  #{@return_value} = rb_ivar_set(#{recv}, #{@translator.allocate_id(klass.get_attr_id(mid))}, #{param[0]});"
        when :ivar
          raise(CompileError.new("invalid call site")) if splatcall? || param.size() != 0
          @dependency.add(klass, mid, false)
          return "  #{@return_value} = rb_attr_get(#{recv}, #{@translator.allocate_id(klass.get_attr_id(mid))});"
        when false
          return nil
        end
        bug()
      end

      def to_c(params)
        ret = []
        ret << super(params)
        param = param_variables()
        recv = param.shift
        id = @translator.allocate_id(@method_id)
        bug() if recv.undefined?
        if @configuration.development? && sampling_return_value?
          ret << "  sampling_tmp = #{recv.boxed_form};"
        end
        if blockarg?
          ret << funcall_code(nil, id, recv, param, @argc)
        elsif recv.dynamic? || @configuration.force_dispatch_method?
          if @configuration.force_dispatch_method?
            # ユーザからの指定に基づいているので、Suggestion は吐かない
            ret << funcall_code(nil, id, recv, param, @argc)
          elsif recursive_call_var?(recv, @method_id)
            ret << recursive_call_code(recv, param, @argc) || funcall_code(nil, id, recv, param, @argc)
          else
            if @configuration.development? && @source
              @translator.add_type_suggestion([get_definition_str(recv), @method_id.to_s, @source_line, @source])
            end
            ret << funcall_code(nil, id, recv, param, @argc)
          end
        else
          bug() if recv.types.empty?
          if recv.types.size() == 1
            multicall = false
          else
            multicall = true
          end
          if multicall
            types = recv.types
            types.each{|t| bug() unless t.is_a?(ClassWrapper) }
            nil_wrapper = ClassWrapper.new(NilClass, true)
            if types.size() == 2 && (types[0] == nil_wrapper || types[1] == nil_wrapper)
              # FIXME ここで nil もしくは別クラスだったらどうこうという処理は行わずに
              #       データフロー解析時に nil もしくは別のクラスという形だったら
              #       中間コードレベルで nil かどうかの条件分岐を入れたほうが
              #       定数伝播などによる最適化まで期待できる分、性能が向上すると思う。
              nil_index  = (types[0] == nil_wrapper ? 0 : 1)
              else_index = 1 - nil_index
              nil_code = not_funcall_code(nil_wrapper, @method_id, recv, param, @argc)
              if !nil_code
                nil_code = funcall_code(nil, id, recv, param, @argc)
              end
              else_class = types[else_index]
              else_code = not_funcall_code(else_class, @method_id, recv, param, @argc)
              if !else_code
                @dependency.add(else_class, @method_id, false)
                else_code = funcall_code(else_class, id, recv, param, @argc)
              end
              if nil_code == else_code
                ret << "  #{nil_code}"
              else
                ret << <<-EOS
  if (#{recv} == Qnil) {
    #{nil_code}
  } else {
    #{else_code}
  }
                EOS
              end
            else
              ret << MultiCallTemplate.trigger(binding)
            end
          else # singlecall
            klass = recv.types[0]
            c = not_funcall_code(klass, @method_id, recv, param, @argc)
            if c
              ret << c
            else
              begin
                @dependency.add(klass, @method_id, false)
              rescue CompileError
                # 通過していない分岐をコンパイルするときに通る
                klass = nil
              end
              ret << funcall_code(klass, id, recv, param, @argc)
            end
          end
        end
        if @configuration.development? && sampling_return_value?
          ret << "  sampling_poscall(#{@return_value.boxed_form}, sampling_tmp, ID2SYM(rb_intern(#{@method_id.to_s.inspect})));"
        end
        ret.join("\n")
      end

      def type_propergation(defs)
        return false if @return_value.dynamic?
        recv = @param[0].param_value
        return if recv.undefined?
        change = false
        recv = @param[0].param_value
        bug() if recv.undefined?
        if recv.dynamic?
          dynamic = true
        else
          dynamic = false
          types = recv.types
          types.each do |t|
            return_value_class = @translator.return_value_class(t, @method_id)
            if return_value_class
              return_value_class.each{|c| change = true if @return_value.is_also(c)}
            else
              dynamic = true
              break
            end
          end
        end
        if dynamic
          change |= @return_value.is_dynamic()
        end
        change
      end

      def harmless?(recv_p)
        recv = @param[0].param_value
        bug() if recv.undefined?
        return false if recv.dynamic?
        recv.types.each do |t|
          return false unless @configuration.harmless?(t, @method_id, recv_p)
        end
        recv.types.each do |t|
          ok = @configuration.use_method_information(t, @method_id)
          return false unless ok
          # これのせいで依存するクラスなどが結構増える。読み込みが遅くなる。
          @dependency.add(t, @method_id, true)
        end 
        return true
      end

      def side_effect?
        recv = @param[0].param_value
        bug() if recv.undefined?
        if recv.dynamic?
          se = true
        else
          se = false
          recv.types.each do |t|
            if @configuration.side_effect?(t, @method_id)
              se = true
              break
            end
          end
        end
        if !se
          recv.types.each do |t|
            ok = @configuration.use_method_information(t, @method_id)
            return true unless ok
            # これのせいで依存するクラスなどが結構増える。読み込みが遅くなる。
            @dependency.add(t, @method_id, true)
          end 
        end
        se
      end

      def should_be_alive?
        side_effect?
      end

      def propergate_exact_class(defs)
        if @return_value.class_exact?
          false
        elsif class_exact?
          @return_value.is_class_exact() 
          true
        else
          false
        end
      end

      ### unboxing begin ###
      def unboxing_prelude()
        params = param_variables()
        recv, *args = *params
        bug() if recv.undefined?
        bug() unless instance_of?(InvokeIR)
        if recv.dynamic? || @configuration.force_dispatch_method?
          can_not_unbox()
          return
        else
          bug() if recv.types.empty?
          unless recv.types.size() == 1
            can_not_unbox()
            return
          end
          klass = recv.types[0]
          bug() unless klass.is_a?(ClassWrapper)
          unless klass.get_method_type(@method_id) == :cfunc
            can_not_unbox()
            return
          end
          unless @configuration.should_be_call_directly?(klass, @method_id)
            can_not_unbox()
            return
          end
          cfunc_argc = klass.get_cfunc_argc(@method_id)
          bug() unless cfunc_argc
          entries = SpecializeTable0[[MethodWrapper.new(klass, @method_id), argc]]
          unless entries
            can_not_unbox()
            return
          end
          entry = nil
          entries.each do |e|
            bug() unless e.size == 6
            name, t_args, t_result, exact_classes, can_unbox_result, can_unbox_param = e
            bug() unless args.size == t_args.size
            fin = true
            (args + [@return_value]).zip(t_args + [t_result]).each do |p, t|
              next if t.nil?
              unless p.is_just?(t)
                fin = false
                break
              end
            end
            if fin
              entry = e
              break
            end
          end
          unless entry
            can_not_unbox()
            return
          end
          name, t_args, t_result, exact_classes, can_unbox_result, can_unbox_param = entry
          can_unbox_param ? params.each{|p| p.box() unless p.can_unbox?} : params.each{|p| p.box()}
          @return_value.box() unless can_unbox_result && @return_value.can_unbox?
          return
        end
      end
      ### unboxing end ###

      def inlining_target?
        false # TODO
      end

      private

      def class_exact?
        params = param_variables()
        recv, *args = *params
        bug() if recv.undefined?
        if recv.dynamic? || @configuration.force_dispatch_method? || !instance_of?(InvokeIR)
          return false
        else
          bug() if recv.types.empty?
          unless recv.types.size() == 1
            return false
          end
          klass = recv.types[0]
          bug() unless klass.is_a?(ClassWrapper)
          unless klass.get_method_type(@method_id) == :cfunc
            return false 
          end
          unless @configuration.should_be_call_directly?(klass, @method_id)
            return false
          end
          cfunc_argc = klass.get_cfunc_argc(@method_id)
          bug() unless cfunc_argc
          entries = SpecializeTable0[[MethodWrapper.new(klass, @method_id), argc]]
          return false unless entries
          entry = nil
          entries.each do |e|
            bug() unless e.size == 6
            name, t_args, t_result, exact_classes, can_unbox_result, can_unbox_param = e
            bug() unless args.size == t_args.size
            fin = true
            (args + [@return_value]).zip(t_args + [t_result]).each do |p, t|
              next if t.nil?
              unless p.is_just?(t)
                fin = false
                break
              end
            end
            if fin
              entry = e
              break
            end
          end
          unless entry
            return false
          end
          name, t_args, t_result, exact_classes, can_unbox_result, can_unbox_param = entry
          return false unless exact_classes
          if @return_value.is_just?(exact_classes)
            return true
          else
            return false
          end
        end
      end
    end
  end
end
end

