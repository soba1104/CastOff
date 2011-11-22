# coding=utf-8

module CastOff
  module Compiler
    class Iseq
      include CastOff::Util

      attr_reader :iseq, :children, :parent, :depth, :lvars, :source, :name, :generation, :itype, :args, :source_file, :source_line, :parent_pc, :loopkey

      class Args
        include CastOff::Util

        attr_reader :arg_size, :argc, :post_len, :post_start, :rest_index, :block_index, :opts, :opt_len

        def initialize(args, iseq)
          @iseq = iseq
          case args
          when Integer
            @argc, @opts, @post_len, @post_start, @rest_index, @block_index, @simple = args, [], 0, 0, -1, -1, 1
          when Array
            bug() unless args.size == 7
            @argc, @opts, @post_len, @post_start, @rest_index, @block_index, @simple = args
          else
            bug()
          end
          @opt_len = @opts.empty? ? 0 : (@opts.size() - 1)
          @arg_size = @argc + @opt_len + @post_len + (@rest_index == -1 ? 0 : 1) + (@block_index == -1 ? 0 : 1)

          case @iseq.itype
          when :method
            bug() if @simple == 2
          when :block
            # nothing to do
          else
            bug()
          end

          if @rest_index != -1
            bug() unless @rest_index + 1 == @post_start
            bug() unless @argc + @opt_len == @rest_index
          end
        end

        def post?
          @post_len != 0
        end

        def rest?
          @rest_index != -1
        end

        def block?
          @block_index != -1
        end

        def opt?
          not @opts.empty?
        end

        def simple?
          (@simple & 0x01) != 0
        end

        def splat?
          (@simple & 0x02 == 0) && (@argc + @post_len > 0)
        end
      end

      def initialize(iseq, parent, depth, ppc)
        bug() unless iseq.is_a?(RubyVM::InstructionSequence)
        @iseq = iseq
        ary = iseq.to_a
        @name = ary[5]
        @source_file = ary[7]
        @source_line = ary[8]
        @itype = ary[9] # iseq type
        args = ary[11]
        @args = Args.new(args, self)
        if @source_file && File.exist?(@source_file)
          @source = File.readlines(@source_file)
        else
          @source = nil
        end
        @parent = parent
        @children = {} # pc => iseq
        bug() unless depth.is_a?(Fixnum)
        @depth = depth
        @parent_pc = ppc
        @generation = 0

        p = @parent
        while p
          p = p.parent
          @generation += 1
        end
        bug() if !root? && @generation < 1

        # for code generator
        @argv_size = 1
        @initialize_for_guards = []
        @guard_codes = {}
        @local_variable_declarations = []
        @c_function_body = ""
        @c_name = "iseq_#{@iseq.hash.to_s.gsub(/-/, "_")}"
        @ifunc_name = "ifunc_#{@c_name}"
        @ifunc_node_name = "ifunc_node_#{@c_name}"
        @excs = {}
        @reference_constant_p = false
        @loopkey = nil
      end

      def set_local_variables(lvars)
        @lvars = lvars
      end

      def set_loopkey(k)
        bug() if root?
        @loopkey = k
      end

      def add(child, pc)
        bug() unless child.is_a?(Iseq)
        bug() unless pc.is_a?(Fixnum)
        bug() if @children[pc]
        @children[pc] = child
      end

      def root?
        !@parent
      end

      def ancestors
        a = []
        s = self.parent
        while s
          a << s
          s = s.parent
        end
        a
      end

      def reference_constant
        @reference_constant_p = true
      end

      def reference_constant?
        @reference_constant_p
      end

      def append_c_function_body(code)
        @c_function_body = [@c_function_body, code].join("\n")
      end

      def all_c_function_body()
        o = own_c_function_body()
        c = @children.values.map{|i| i.all_c_function_body() }.join("\n")
        [o, c].join("\n")
      end

      def own_c_function_body()
        @c_function_body
      end

      def use_temporary_c_ary(size)
        @argv_size = size if size > @argv_size
      "cast_off_argv"
      end

      def all_argv_size()
        o = own_argv_size()
        c = @children.values.map{|i| i.all_argv_size()}
        [o, c].flatten.max()
      end

      def own_argv_size()
        @argv_size
      end

      def declare_local_variable(v)
        @local_variable_declarations << v
      end

      def all_local_variable_declarations()
        o = own_local_variable_declarations()
        c = @children.values.map{|i| i.all_local_variable_declarations() }
        [o, c].flatten.uniq()
      end

      def own_local_variable_declarations()
        @local_variable_declarations.uniq()
      end

      def initialize_for_guards(var)
        @initialize_for_guards << var
      end

      def all_initializations_for_guards()
        # 外のブロックで定義されたローカル変数は、LocalVariable とはならないため。
        # ローカル変数は、全て初期化してしまって問題ない。
        ret = []
        ret += own_initializations_for_guards()
        @children.values.each{|c| ret += c.all_initializations_for_guards() }
        ret.uniq()
      end

      def own_initializations_for_guards()
        @initialize_for_guards.map{|v| "  #{v} = Qnil;"}.uniq()
      end

      def inject_guard(insn, code)
        bug() unless insn.iseq == self
        if @guard_codes[code]
          @guard_codes[code] << insn
        else
          @guard_codes[code] = [insn]
        end
      end

      def iterate_all_guards(&b)
        iterate_own_guards(&b)
        @children.values.each{|c| c.iterate_all_guards(&b)}
      end

      def iterate_own_guards()
        @guard_codes.each{|(code, insns)| yield(code, insns)}
      end
      
      def iterate_all_iseq(&b)
        yield(self)
        @children.values.each{|c| c.iterate_all_iseq(&b)}
      end

      def declare_ifunc_node()
        "static NODE *#{@ifunc_node_name}"
      end

      IfuncNodeGeneratorTemplate = ERB.new(<<-EOS, 0, '%-', 'io')
static void <%= ifunc_node_generator() %>()
{
%# NEW_IFUNC の第二引数は Proc に対して渡せる好きな値
%#<%= @ifunc_node_name %> = NEW_IFUNC(<%= @ifunc_name %>, <%= self %>->self); 
  <%= @ifunc_node_name %> = NEW_IFUNC(<%= @ifunc_name %>, Qnil); 
%# nd_aid = 0 だと rb_frame_this_func で <ifunc> となる。
  <%= @ifunc_node_name %>->nd_aid = 0;
  rb_gc_register_mark_object((VALUE)<%= @ifunc_node_name %>);
}
      EOS

      def define_ifunc_node_generator()
        IfuncNodeGeneratorTemplate.trigger(binding)
      end

      def ifunc_node_generator()
        "generate_ifunc_node_#{@c_name}"
      end

      BlockGeneratorTemplate = ERB.new(<<-EOS, 0, '%-', 'io')
<%= declare_block_generator() %>
{
  VALUE thval = rb_thread_current();
  rb_thread_t * th = DATA_PTR(thval);
  rb_control_frame_t *cfp = th->cfp;
  rb_block_t *blockptr = (rb_block_t *)(&(cfp)->self);
  /* cfp の self 以下が block 構造体のメンバとなる */

  blockptr->iseq = (void *)<%= @ifunc_node_name %>;
  blockptr->proc = 0;
  blockptr->self = self; /* for CastOff.execute */

  return blockptr;
}
      EOS

      def declare_block_generator()
        "rb_block_t *#{block_generator()}(VALUE self)"
      end

      def define_block_generator()
        BlockGeneratorTemplate.trigger(binding)
      end

      def block_generator()
        "cast_off_create_block_#{@c_name}"
      end

      def declare_dfp(indent = 2)
        indent = ' ' * indent
        (0..@generation).map{|i| "#{indent}VALUE *dfp#{i};"}.join("\n")
      end

      def update_dfp(indent = 2)
        indent = ' ' * indent
        (0..@generation).map{|i| "#{indent}dfp#{i} = fetch_dfp(th, #{@generation - i});"}.join("\n")
      end

      IfuncTemplate = ERB.new(<<-'EOS', 0, '%-', 'io')
<%= declare_ifunc() %>
{
  /* decl variables */
  rb_thread_t *th = current_thread();
  VALUE cast_off_argv[<%= own_argv_size() %>];
  VALUE cast_off_tmp;
  VALUE sampling_tmp;
  VALUE self = get_self(th);
  int lambda_p = cast_off_lambda_p(arg, argc, argv);
  int i, num;
<%= declare_dfp %>
<%= (own_local_variable_declarations).map{|v| "  #{v};"}.join("\n") %>

% bug() if root?
  expand_dframe(th, <%= @lvars.size %>, <%= self %>, 0);
<%= update_dfp %>

%inits = own_initializations_for_guards
%bug() if inits.uniq!
%inits.join("\n")

  /* setup arguments */
  if (lambda_p) {
% bug() if @args.simple? && @args.arg_size != @args.argc
    num = cast_off_prepare_iter_api_lambda_args(<%= @args.arg_size %>, cast_off_argv, argc, argv, <%= @args.simple? ? 1 : 0 %>, <%= @args.argc %>, <%= @args.opt_len %>, <%= @args.post_len %>, <%= @args.post_start %>, <%= @args.rest_index %>);
  } else {
    num = cast_off_prepare_iter_api_block_args(<%= @args.arg_size %>, cast_off_argv, argc, argv, <%= @args.splat? ? 1 : 0 %>, <%= @args.argc %>, <%= @args.opt_len %>, <%= @args.post_len %>, <%= @args.post_start %>, <%= @args.rest_index %>);
  }
%if @args.block?
  cast_off_argv[<%= @args.block_index %>] = blockarg;
%end

<%= enclose_begin %>

%#if reference_constant?
%#  check_cref(th);
%#end

  /* body */
<%= own_c_function_body() %>

%iterate_own_guards do |code, insns|
{
  long pc;
  <%= enclose_end_deoptimize %>
%code_label = "deoptimize_#{code.hash.to_s.gsub(/-/, "_")}"
%  insns.uniq.each do |insn|
<%= insn.guard_label %>:
  pc = <%= insn.pc %>;
  goto <%= code_label %>;
%  end
<%= code_label %>:
<%= code %>
}
%end

<%= enclose_end %>
}
      EOS

      def declare_ifunc()
        "static VALUE #{@ifunc_name}(VALUE arg, VALUE dummy, int argc, VALUE *argv, VALUE blockarg)"
      end

      def define_ifunc()
        IfuncTemplate.trigger(binding)
      end

      ExceptionHandlerTemplate = ERB.new(<<-'EOS', 0, '%-', 'io')
  {
    int state;
    rb_control_frame_t *volatile cfp;

    th = current_thread();
    cfp = th->cfp;

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) != 0) {
      VALUE excval;

      th = current_thread();
      while (th->cfp != cfp) {
        th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);
      }

%@excs.each do |(exc, entries)|
      switch(state) {
%  case exc
%  when :break
      case TAG_BREAK:
        excval = catch_break(th);
        if (excval != Qundef) {
          switch((int)(cfp->pc - cfp->iseq->iseq_encoded)) {
%    entries.each do |(pc, label, stack)|
          case <%= pc %>:
<%= update_dfp(12) %>
            tmp<%= stack - 1 %> = excval; /* FIXME */
            goto <%= label %>;
%    end
          default:
            rb_bug("failed to found break target");
          }
        }
%  when :return
      case TAG_RETURN:
        excval = catch_return(th);
        if (excval != Qundef) {
          /* vm_pop_frame is called at the vm_call_method() */
          TH_POP_TAG2();
          return excval;
        }
%  else
%    bug()
%  end
      }
      TH_POP_TAG2();
      TH_JUMP_TAG(th, state);
%end
    }
      EOS

      def enclose_begin()
        return '' if @excs.empty?
        ExceptionHandlerTemplate.trigger(binding)
      end

      def enclose_end()
        @excs.empty? ? '' : <<-EOS
    TH_POP_TAG();
    rb_bug("enclose_end: should not be reached");
  }
        EOS
      end

      def enclose_end_deoptimize()
        @excs.empty? ? '' : 'TH_POP_TAG2();'
      end

      def catch_exception?
        not @excs.empty?
      end

      def catch_exception(exc, pc, label, stack)
        @excs[exc] ||= []
        entry = [pc, label, stack]
        @excs[exc] << entry unless @excs[exc].include?(entry)
      end

      def delete_labels(ls)
        entries = @excs[:break]
        return unless entries
        entries.delete_if do |(pc, label, stack)|
          del_p = ls.include?(label)
          dlog("#{self}: delete break label #{label}") if del_p
          del_p
        end
      end

      def to_name
        "#{@name}: #{@source_file} #{@source_line}"
      end

      def to_s
        @c_name
      end
    end
  end
end

