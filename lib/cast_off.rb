require 'cast_off.so'
require 'cast_off/util'
require 'cast_off/suggestion'
require 'cast_off/compile/dependency'
require 'cast_off/compile/method_information'
require 'cast_off/compile/configuration'
require 'cast_off/compile/code_manager'
require 'cast_off/compile/namespace/uuid'
require 'cast_off/compile/namespace/namespace'
require 'cast_off/compile'

module CastOff
  extend CastOff::Util
  extend CastOff::Compiler
end
CastOff.clear_settings()

