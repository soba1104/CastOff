module CastOff
  module Compiler
    class MethodInformation
      include CastOff::Util

      attr_reader :method

      InformationName = [
        :destroy_reciever, :destroy_arguments, :escape_reciever, :escape_arguments, :side_effect
      ]
      def initialize(me, info)
        @method = me
        InformationName.each do |name|
          instance_variable_set("@#{name}", true)
        end
        raise(ArgumentError.new("invalid information")) unless info.is_a?(Hash)
        info.each do |(name, val)|
          raise(ArgumentError.new("unknown information name #{name}")) unless InformationName.include?(name)
          instance_variable_set("@#{name}", !!val)
        end
      end

      InformationName.each do |name|
        eval(<<-EOS)
        def #{name}?
          @#{name}
        end
        EOS
      end

      def ==(other)
        eql?(other)
      end

      def eql?(other)
        case other
        when MethodInformation
          ome = other.method
        when MethodWrapper
          ome = other
        else
          bug()
        end
        bug() unless @method.instance_of?(MethodWrapper)
        bug() unless ome.instance_of?(MethodWrapper)
        @method == ome
      end

      def hash()
        bug() unless @method.instance_of?(MethodWrapper)
        @method.hash
      end

      def self.use_builtin_library_information()
        # ==
        CastOff.set_method_information(BasicObject, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Module, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Comparable, :==, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(String, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Symbol, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Exception, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Hash, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Regexp, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(MatchData, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Range, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Random, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Rational, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Complex, :==, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # ===
        CastOff.set_method_information(Kernel, :===, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Module, :===, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(String, :===, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Symbol, :===, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :===, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :===, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :===, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Regexp, :===, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => true,
                                       :escape_arguments => false,
                                       :side_effect => true)
        CastOff.set_method_information(Range, :===, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        
        # eql?
        CastOff.set_method_information(Kernel, :eql?, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(String, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Numeric, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Hash, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Regexp, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(MatchData, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Range, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Time, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Complex, :eql?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # equal?
        CastOff.set_method_information(BasicObject, :equal?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # !=
        CastOff.set_method_information(BasicObject, :!=, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # !
        CastOff.set_method_information(BasicObject, :!, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # +
        CastOff.set_method_information(String, :+, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :+, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :+, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :+, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :+, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Time, :+, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Rational, :+, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Complex, :+, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # -
        CastOff.set_method_information(Fixnum, :-, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :-, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :-, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :-, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Time, :-, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Rational, :-, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Complex, :-, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # *
        CastOff.set_method_information(String, :*, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :*, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :*, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :*, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :*, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Rational, :*, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Complex, :*, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # /
        CastOff.set_method_information(Fixnum, :/, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :/, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :/, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Rational, :/, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Complex, :/, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # %
        CastOff.set_method_information(String, :%, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Numeric, :%, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :%, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :%, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :%, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # |
        CastOff.set_method_information(NilClass, :|, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(TrueClass, :|, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(FalseClass, :|, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :|, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :|, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :|, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # &
        CastOff.set_method_information(NilClass, :&, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(TrueClass, :&, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(FalseClass, :&, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :&, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :&, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :&, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # <=>        
        CastOff.set_method_information(Kernel, :<=>, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Module, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(String, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Symbol, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Numeric, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(File::Stat, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Time, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Rational, :<=>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # >
        CastOff.set_method_information(Module, :>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Comparable, :>, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :>, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # >=
        CastOff.set_method_information(Module, :>=, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Comparable, :>=, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :>=, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :>=, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :>=, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # <
        CastOff.set_method_information(Module, :<, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Comparable, :<, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :<, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :<, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :<, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # <=
        CastOff.set_method_information(Module, :<=, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Comparable, :<=, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :<=, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :<=, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :<=, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # nil?
        CastOff.set_method_information(Kernel, :nil?, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(NilClass, :nil?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # to_s
        CastOff.set_method_information(Kernel, :to_s, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(NilClass, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Module, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(TrueClass, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(FalseClass, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Encoding, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(String, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => true,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Symbol, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Exception, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Float, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Regexp, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(MatchData, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Range, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Time, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Rational, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Complex, :to_s, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # <<
        CastOff.set_method_information(String, :<<, :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => false,
                                       :escape_reciever => true,
                                       :escape_arguments => false,
                                       :side_effect => true)
        CastOff.set_method_information(Fixnum, :<<, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :<<, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :<<, :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => false,
                                       :escape_reciever => true,
                                       :escape_arguments => true,
                                       :side_effect => true)

        # []
        CastOff.set_method_information(String, :[], :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Symbol, :[], :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :[], :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :[], :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :[], :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Hash, :[], :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => true,
                                       :escape_reciever => true,
                                       :escape_arguments => true,
                                       :side_effect => true)

        # []=
        CastOff.set_method_information(String, :[]=, :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => true,
                                       :side_effect => true)
        CastOff.set_method_information(Array, :[]=, :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => true,
                                       :side_effect => true)
        CastOff.set_method_information(Hash, :[]=, :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => true,
                                       :side_effect => true)

        # concat
        CastOff.set_method_information(String, :concat, :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => false,
                                       :escape_reciever => true,
                                       :escape_arguments => false,
                                       :side_effect => true)
        CastOff.set_method_information(Array, :concat, :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => false,
                                       :escape_reciever => true,
                                       :escape_arguments => false,
                                       :side_effect => true)

        # print
        CastOff.set_method_information(Kernel, :print, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => true)
        CastOff.set_method_information(Kernel, :print, :singleton,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => true)
        CastOff.set_method_information(IO, :print, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => true)

        # puts
        CastOff.set_method_information(Kernel, :puts, :module,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => true)
        CastOff.set_method_information(Kernel, :puts, :singleton,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => true)
        CastOff.set_method_information(IO, :puts, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => true)

        # join
        CastOff.set_method_information(Array, :join, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(File, :join, :singleton,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # index
        CastOff.set_method_information(String, :index, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :index, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Hash, :index, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # sub
        CastOff.set_method_information(String, :sub, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # sub!
        CastOff.set_method_information(String, :sub!, :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => false,
                                       :escape_reciever => true,
                                       :escape_arguments => false,
                                       :side_effect => true)

        # gsub
        CastOff.set_method_information(String, :gsub, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # gsub!
        CastOff.set_method_information(String, :gsub!, :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => false,
                                       :escape_reciever => true,
                                       :escape_arguments => false,
                                       :side_effect => true)

        # strip
        CastOff.set_method_information(String, :strip, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # tr
        CastOff.set_method_information(String, :tr, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # tr!
        CastOff.set_method_information(String, :tr!, :class,
                                       :destroy_reciever => true,
                                       :destroy_arguments => false,
                                       :escape_reciever => true,
                                       :escape_arguments => false,
                                       :side_effect => true)
        
        # count
        CastOff.set_method_information(String, :count, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # split
        CastOff.set_method_information(String, :split, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # include?
        CastOff.set_method_information(Array, :include?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # compact
        CastOff.set_method_information(Array, :compact, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # flatten
        CastOff.set_method_information(Array, :flatten, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # reverse
        CastOff.set_method_information(String, :reverse, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :reverse, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # size
        CastOff.set_method_information(String, :size, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Symbol, :size, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :size, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :size, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Hash, :size, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Struct, :size, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(MatchData, :size, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # length
        CastOff.set_method_information(String, :length, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Symbol, :length, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :length, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Hash, :length, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Struct, :length, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(MatchData, :length, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # empty?
        CastOff.set_method_information(String, :empty?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Symbol, :empty?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Array, :empty?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Hash, :empty?, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # ^
        CastOff.set_method_information(NilClass, :^, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(TrueClass, :^, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(FalseClass, :^, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Fixnum, :^, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Bignum, :^, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # chr
        CastOff.set_method_information(String, :chr, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Integer, :chr, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # last
        CastOff.set_method_information(Array, :last, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Range, :last, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)

        # first
        CastOff.set_method_information(Array, :first, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
        CastOff.set_method_information(Range, :first, :class,
                                       :destroy_reciever => false,
                                       :destroy_arguments => false,
                                       :escape_reciever => false,
                                       :escape_arguments => false,
                                       :side_effect => false)
      end
    end
  end
end

