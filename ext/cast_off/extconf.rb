# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

require 'mkmf'
require 'rbconfig'
extend RbConfig

$defs.push '-DCABI_OPERANDS' if enable_config 'cabi-operands', true
$defs.push '-DCABI_PASS_CFP' if enable_config 'cabi-pass-cfp', true

$INCFLAGS << ' -I$(srcdir)/ruby_source'
$objs = %w'$(srcdir)/cast_off.o'
$srcs = %w'$(srcdir)/cast_off.c.rb'
create_header
create_makefile 'cast_off'

