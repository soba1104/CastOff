# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

# This file was splitted from compiler.rb.
#require 'uuid'
require 'erb'
require 'tsort'

# ``To compile a thing is to manage its namespace.'' -- a nameless developer
class Namespace

  # This is used to limit the UUID namespace
  UUIDNS = UUID.parse 'urn:uuid:71614e1a-0cb4-11df-bc41-5769366ff630'

  # creates a new namespace.
  def self.new namemax = 31, prefix = 'yarv_'
    limit = namemax - prefix.length
    if limit <= 0
      raise ArgumentError, "offered namespace too narrow"
    elsif 128.0 / limit > 36
      # Integer#to_s takes  radix of range up  to 36.  This limit  is due to
      # UUIDs to be safely represented in the namespace.
      raise ArgumentError, "offered namespace too narrow: at least 128bits are needed."
    else
      Class.new self do
        @namemax       = namemax
        @prefix        = prefix
        @limit         = limit
        @phasechange   = UUIDNS.to_s.length <= limit
        bpc            = 128.0 / limit
        radixf         = 2 ** bpc
        @radix         = radixf.ceil
        @desired2names = Hash.new
        @barenames     = Hash.new
        @topology      = Hash.new
        class << self
          alias new namegen
          private
          m = Class.instance_method :new
          define_method :old_new, m
        end
        self
      end
    end
  end

  class << self
    include TSort

    # This is  aliased to class method  ``new''.  Generates a  name unique in
    # this namespace, taking as much as possible from what's _desired_.
    #
    # Note  however, that an  identical argument  _desired_ generates  a same
    # name on multiple invocations unless _realuniq_ is true.
    def namegen desired = UUID.new.to_s, realuniq = false
      a = @desired2names.fetch desired, Array.new
      return a.first if not realuniq and not a.empty?
      n = nil
      cand0 = as_tr_cpp desired.to_s
      cand1 = cand0
      while @barenames.has_key? cand1
        n ||= 1
        n += 1
        cand1 = cand0 + n.to_s
      end
      if cand1.length <= @limit
        # OK, take this
        name = old_new @prefix + cand1
        a.push name
        @desired2names.store desired, a
        @barenames.store cand1, name
        return name
      elsif @phasechange
        # name too long, use UUID#to_s
        u = UUIDNS.new_sha1 desired.to_s
        return new u.to_s, realuniq
      else
        # yet too long, now use Integer#to_s
        u = UUIDNS.new_sha1 desired.to_s
        v = u.to_i.to_s @radix
        return new v, realuniq
      end
    end

    private

    # Makes an identifier string corresponding to _name_, which is safe for a
    # C  compiler.  The  name  as_tr_cpp  was taken  from  a autoconf  macro,
    # AS_TR_CPP().
    def as_tr_cpp name
      q = name.dup
      q.force_encoding 'ASCII-8BIT'
      q.gsub! %r/[^a-zA-Z0-9_]/m, '_'
      q.gsub! %r/_+/, '_'
      q
    end

    # Details TBW
    def split_decls
      # Declarations are not depended each other so they can be sorted.
      a = @barenames.values
      a.reject! do |n|
        n.declaration.nil?
      end
      a.map! do |n|
        case n.definition
        when %r/^[a-zA-Z0-9_]+\(/
                                sprintf "%s %s;", n.declaration, n.name
        when NilClass
          sprintf "%s %s;", n.declaration, n.name
        else
          n.definition
        end
      end
      a.sort!
      a.partition do |e|
        %r/\Astatic\b/.match e
      end
    end

    public

    # Iterates over static declarations
    def each_static_decls
      split_decls.first.each do |e|
        yield e
      end
    end

    # Iterates over non-static declarations
    def each_nonstatic_decls
      split_decls.last.each do |e|
        yield e
      end
    end

    # Iterates over functions
    def each_funcs
      # Functions are also not depended each other.
      a = @barenames.values
      a.map! do |n| n.definition end
      a.reject! do |e|
        not %r/^[a-zA-Z0-9_]+\(/.match e
      end
      a.each do |e|
        yield e
      end
    end

    # Iterates over initializers
    def each_initializers
      # Initializers do depend each other.  Order matters here.
      tsort_each do |n|
        if i = n.initialization
          yield i
        end
      end
    end

    # Atomic each
    def each
      @barenames.each_value do |n|
        yield n
      end
    end

    # tsort's key enumerator
    def tsort_each_node
      each do |i|
        yield i
      end
    end

    # tsort's travarsal enumerator
    def tsort_each_child e
      e.each do |i|
        yield i
      end
    end
  end

  # I originally  implemented this as a  simple Struct.new, but  I needed some
  # validations over setter methods, so I now have my own impl.
  #
  # A C object  has at most four attributes.  Normally 3  and 4 are exclusive,
  # but not required to be.
  # 1.  A name to refer to that object
  # 2.  Type of that object
  # 3.  Static definition of that object
  # 4.  Dynamic initializer for that object
  def initialize name = nil
    @name           = name
    @declaration    = nil
    @definition     = nil
    @initialization = nil
    @expression     = nil
    @dependencies   = Array.new
  end

  attr_reader :name, :declaration, :definition, :initialization, :dependencies,
              :expression

  [:declaration, :definition, :initialization, :expression].each do |i|
    define_method "#{i}=" do |decl|
      n = "@#{i}".intern
      v = instance_variable_get n
      if v  and v != decl
        raise \
          "Multiple, though not identical, object #{i} for "\
          "#{self}:\n\t#{v}\n\t#{decl}"
      elsif v
        # do nothing
      else
        instance_variable_set n, decl
      end
    end
  end

  # dangerous. do not use this.
  def force_set_decl! decl
    @declaration = decl
    @definition = nil
  end

  def to_s
    @expression or @name
  end

  def each
    @dependencies.each do |i|
      yield i
    end
  end

  def depends obj
    @dependencies.push obj
    obj
  end
end

# This  is a  hack, not  to hold  entire output  on-memory. A  YARV-converted C
# sourcecode can be huge, in order of megabytes.  It is not a wise idea for you
# to allocate such a large string at once.
#
# Taken from: http://d.hatena.ne.jp/m_seki/20100228#1267314143
class ERB
  def set_eoutvar c, e
    c.pre_cmd = ["#{e} ||= ''"]
    c.post_cmd = []
    c.put_cmd = c.insert_cmd = "#{e} << "
  end

  def trigger b
    eval @src, b, '(erb)', 0
  end
end

module Converter
  Quote = Struct.new :unquote # :nodoc:

  # Some kinds of literals are there:
  #
  # - Fixnums,  as well  as true,  false, and  nil: they  are  100% statically
  #   computable while the compilation.  No cache needed.
  # - Bignums, Floats, Ranges and Symbols:  they are almost static, except for
  #   the first time.  Suited for caching.
  # - Classes: not computable  by the compiler, but once  a ruby process boots
  #   up, they already are.
  # - Strings:  every time  a literal  is evaluated,  a new  string  object is
  #   created.  So a cache won't work.
  # - Regexps: almost  the same  as Strings, except  for /.../o, which  can be
  #   cached.
  # - Arrays and Hashes: they also  generate new objects every time, but their
  #   contents can happen to be cached.
  #
  # Cached objects can be ``shared''  -- for instance multiple occasions of an
  # identical bignum can and should point to a single address of memory.
  def robject2csource obj, namespace, strmax, volatilep = false, name = nil, contentsp = false
    decl = 'VALUE'
    vdef = 'Qundef'
    init = nil
    deps = Array.new
    expr = nil
    case obj
    when Quote # hack
      name ||= obj.unquote.to_s
    when Fixnum
      name ||= 'LONG2FIX(%d)' % obj
    when TrueClass, FalseClass, NilClass
      name ||= 'Q%p' % obj
    when Bignum
      # Bignums can  be large  enough to exceed  C's string max.   From this
      # method's usage a  bignum reaching this stage is  sourced from a Ruby
      # source  code's bignum  literals, so  they might  not be  much larger
      # though.
      name ||= namespace.new 'num_' + obj.to_s
      rstr = robject2csource obj.to_s, namespace, strmax, :volatile
      init = sprintf "rb_str2inum(%s, 10)", rstr
      deps << rstr
    when Float
      name ||= namespace.new 'float_' + obj.to_s
      init = sprintf 'rb_float_new(%s)', obj
    when Range
      from = robject2csource obj.begin, namespace, strmax, :volatile
      to   = robject2csource obj.end, namespace, strmax, :volatile
      xclp = obj.exclude_end? ? 1 : 0
      init = sprintf "rb_range_new(%s, %s, %d)", from, to, xclp
      name ||= namespace.new
      deps << from << to
    when Class
      # From  my  investigation over  the  MRI  implementation, those  three
      # classes  are the  only classes  that  can appear  in an  instruction
      # sequence.  Don't know why though.
      init = if obj == Object           then 'rb_cObject'
             elsif obj == Array         then 'rb_cArray'
             elsif obj == StandardError then 'rb_eStandardError'
             else
               raise TypeError, "unknown literal object #{obj}"
             end
    when String
      #if obj.empty?
      ## Empty strings are lightweight enough, do not need encodings.
      #name ||= 'rb_str_new(0, 0)'
      #else
      # Like I write here and there  Ruby strings can be much longer than
      # C strings can be.  Plus a  Ruby string has its encoding.  So when
      # we reconstruct a Ruby string, we  need a set of C strings plus an
      # encoding object.
      #if obj.ascii_only?
      #name ||= $namespace.new 'str_' + obj
      #aenc = Encoding.find 'US-ASCII'
      #encn = robject2csource aenc, namespace, strmax, :volatile
      #else
      name ||= namespace.new 'str_' + obj.encoding.name + '_' + obj
      encn = robject2csource obj.encoding, namespace, strmax, :volatile, nil, true
      #end
      deps << encn
      argv = rstring2cstr obj, strmax
      argv.each do |i|
        if init
          x = sprintf ";\nrb_enc_str_buf_cat(%s, %s, %d, %s)",
            name, *i, encn
          init << x
        else
          init = sprintf "rb_enc_str_new(%s, %d, %s)", *i, encn
        end
      end
      if $YARVAOT_DEBUG
        #init << ";\n    /* #{obj} */"
      end
      #end
    when Encoding
      # Thank  goodness, encoding  names are  short and  will  never contain
      # multilingual chars.
      rstr = obj.name
      if contentsp
        decl = 'rb_encoding*'
        vdef = '0'
        init = 'rb_enc_find("%s")' % rstr
        name ||= namespace.new 'enc_' + rstr
      else
        encn = robject2csource obj, namespace, strmax, :volatile, nil, true
        deps << encn
        init = 'rb_enc_from_encoding(%s)' % encn
        name ||= namespace.new 'encval_' + rstr
      end
    when Symbol
      str = obj.id2name
      if str.bytesize <= strmax
        # Why a symbol is not cached as  a VALUE?  Well a VALUE in C static
        # variable needs  to be scanned  during GC because VALUEs  can have
        # links against some other objects  in general.  But that's not the
        # case for  Symbols --  they do not  have links internally.   An ID
        # variable needs no  GC because it's clear they  are not related to
        # GC at all.   So a Symbol is more efficient when  stored as an ID,
        # rather than a VALUE.
        a = rstring2cstr str, strmax
        e = robject2csource str.encoding, namespace, strmax, :volatile, nil, true
        name = namespace.new 'sym_' + obj.to_s
        decl = 'ID'
        vdef = '0'
        init = sprintf 'rb_intern3(%s, %d, %s);', *a[0], e
        expr = 'ID2SYM(%s)' % name.name
        deps << e
      else
        # Longer symbols are much like regexps
        name ||= namespace.new 'sym_' + str
        rstr = robject2csource str, namespace, strmax, :volatile
        init = 'rb_str_intern(%s)' % rstr
        deps << rstr
      end
    when Regexp
      opts = obj.options
      srcs = robject2csource obj.source, namespace, strmax, :volatile
      name ||= namespace.new "reg#{opts}_" + srcs.to_s
      init = sprintf 'rb_reg_new_str(%s, %d)', srcs, opts
      deps << srcs
    when Array
      n = obj.length
      if n == 0
        # zero-length  arrays need  no cache,  because a  creation  of such
        # object is fast enough.
        name ||= 'rb_ary_new2(0)'
        #elsif n == 1
        ## no speedup, but a bit readable output
        #i    = obj.first
        #e    = robject2csource i, namespace, strmax, :volatile
        #j    = as_tr_cpp e.to_s
        #s    = 'a' + j
        #name ||= $namespace.new s
        #init = 'rb_ary_new3(1, %s)' % e
        #deps << e
      elsif n <= 30
        # STDC's max  # of function arguments  are 31, so at  most 30 elems
        # are made at once.
        init = 'rb_ary_new3(%d' % obj.length
        obj.each do |x|
          y = robject2csource x, namespace, strmax, :volatile
          init << ",\n        " << y.to_s
          deps << y
        end
        init << ')'
        s = init.sub %r/\Arb_ary_new3\(\d+,\s+/, 'a'
                                       name ||= namespace.new 'ary_' + s
      else
        # Too large to create at once.  Feed litte by litte.
        name ||= namespace.new
        init = 'rb_ary_new()'
        obj.each do |i|
          j = robject2csource i, namespace, strmax, :volatile
          k = sprintf 'rb_ary_push(%s, %s)', name, j
          init << ";\n    " << k
          deps << j
        end
      end
    when Hash
      # Hashes are not computable in a single expression...
      name ||= namespace.new
      init = "rb_hash_new()"
      obj.each_pair do |k, v|
        knam = robject2csource k, namespace, strmax, :volatile
        vnam = robject2csource v, namespace, strmax, :volatile
        aset = sprintf 'rb_hash_aset(%s, %s, %s)', name, knam, vnam
        init << ";\n    " << aset
        deps << knam << vnam
      end
    else
      raise TypeError, "unknown literal object #{obj.inspect}"
    end

    name ||= namespace.new init
    case name when namespace
      static_decl = "static #{decl}"
      if volatilep and name.declaration == static_decl
        # OK? same object, different visibility
      elsif not volatilep and name.declaration == decl
        # OK? same object, different visibility
        name.force_set_decl! static_decl
      else
        name.declaration = volatilep ? decl : static_decl
      end
      name.definition     = "#{name.declaration} #{name.name} = #{vdef};"
      name.initialization = "#{name.name} = #{init};" if init
      name.expression     = expr
      deps.each do |i|
        case i when namespace
          name.dependencies.push i
        end
      end
    end
    return name
  end

  # Yet more long string than gen_lenptr
  def gen_each_lenptr var, str, strmax
    names = Array.new
    str.each_line.with_index do |i, j|
      a = rstring2cstr i, strmax
      case a.size when 1
        vnam  = sprintf '%s_%x', var, j
        gnam = gen_lenptr vnam, *a[0]
        names << gnam
      else
        a.each_with_index do |b, k|
          vnam = sprintf '%s_%x_%x', var, j, k
          gnam = gen_lenptr vnam, *b
          names << gnam
        end
      end
    end
    names.each_cons 2 do |x, y|
      y.depends x
    end
  end

  # Static allocation of a loooooong string
  def gen_lenptr var, ptr, len
    name = $namespace.new var
    name.declaration = "static sourcecode_t #{name}"
    name.definition  = sprintf '%s = { %#05x, %s, };',
    name.declaration, len, ptr
    name
  end

  # Returns a 2-dimensional array [[str, len], [str, len], ... ]
  #
  # This is needed because Ruby's String#dump is different from C's.
  def rstring2cstr str, strmax, rs = nil
    return [["".inspect, 0]] if str.empty?
    a = str.each_line rs
    a = a.to_a
    a.map! do |b|
      c = b.each_byte.each_slice strmax
      c.to_a
    end
    a.flatten! 1
    a.map! do |bytes|
      b = bytes.each_slice 80
      c = b.map do |d|
        d.map do |e|
          '\\x%x' % e
          #case e # this case statement is optimized
          #when 0x00 then '\\0'
          #when 0x07 then '\\a'
          #when 0x08 then '\\b'
          #when 0x09 then '\\t'
          #when 0x0A then '\\n'
          #when 0x0B then '\\v'
          #when 0x0C then '\\f'
          #when 0x0D then '\\r'
          #when 0x22 then '\\"'
          #when 0x27 then '\\\''
          #when 0x5C then '\\\\' # not \\
          #else
          #case e
          #when 0x20 ... 0x7F then '%c' % e
          #else '\\x%x' % e
          #end
          #end
        end
      end
      c.map! do |d|
        "\n        " '"' + d.join + '"'
      end
      if c.size == 1
        c.first.strip!
      end
      [ c.join, bytes.size, ]
    end
    a
  end
end

