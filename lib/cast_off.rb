require 'cast_off.so'
require 'cast_off/util'
require 'cast_off/suggestion'
require 'cast_off/compile/dependency'
require 'cast_off/compile/method_information'
require 'cast_off/compile/configuration'
require 'cast_off/compile/code_manager'
require 'cast_off/compile'

module CastOff
  extend CastOff::Util
  extend CastOff::Compiler
end
CastOff.hook_method_definition()
CastOff.clear_settings()

