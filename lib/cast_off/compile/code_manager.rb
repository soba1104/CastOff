# coding=utf-8

require 'rbconfig'
require 'fileutils'

module CastOff
  module Compiler
    class CodeManager
      include RbConfig
      include CastOff::Util

      attr_reader :signiture

      CastOffDir = "#{ENV["HOME"]}/.CastOff"
      FileUtils.mkdir(CastOffDir) unless File.exist?(CastOffDir)

      @@program_name = File.expand_path($PROGRAM_NAME)
      CastOff::Compiler.class_eval do
	def program_name=(dir)
	  CastOff::Compiler::CodeManager.class_variable_set(:@@program_name, dir)
	end
      end

      def self.program_dir()
	dir = "#{CastOffDir}/#{@@program_name.gsub(/\.|\/|-/, "_")}"
	FileUtils.mkdir(dir) unless File.exist?(dir)
	dir
      end

      def self.load_autocompiled()
	begin
	  dir = program_dir()
	  path = "#{dir}/auto_compiled.dump"
	  return nil unless File.exist?(path)
	  str = File.read(path)
	  str.untaint # FIXME
	  Marshal.load(str)
	rescue ArgumentError, NameError
	  false
	end
      end

      def self.dump_auto_compiled(compiled)
	dir = program_dir()
	path = "#{dir}/auto_compiled.dump"
	File.open("#{path}", 'wb:us-ascii') do |f|
	  Marshal.dump(compiled, f)
	end
	load_autocompiled()
      end

      def initialize(filepath, line_no)
	@filepath = filepath
	@line_no = line_no
	@signiture = "#{@filepath}_#{@line_no}".gsub(/\.|\/|-/, "_")
	dir = self.class.program_dir()
	@dstdir = "#{dir}/#{@signiture}"
	@dstfile = "#{@signiture}.c"
	@depfile = "#{@signiture}.mdep"
	@deppath = "#{@dstdir}/#{@depfile}"
	@conffile = "#{@signiture}.conf"
	@suggested_configuration_file = "#{@signiture}.suggested.conf"
	@suggested_configuration_path = "#{@dstdir}/#{@suggested_configuration_file}"
	@specified_configuration_file = "#{@signiture}.specified.conf"
	@specified_configuration_path = "#{@dstdir}/#{@specified_configuration_file}"
	@base_configuration_path = "#{@dstdir}/#{@signiture}.base.conf"
	@development_mark_file = "development"
	@development_mark_path = "#{@dstdir}/#{@development_mark_file}"
	@dstbin = "#{@dstdir}/#{@signiture}.so"
	@configuration = nil
      end

      def target_file_updated?
	not (File.exist?(@dstbin) && File.mtime(@filepath).tv_sec < File.mtime(@dstbin).tv_sec)
      end

      def suggested_configuration_available?
	File.exist?(@suggested_configuration_path)
      end

      def compiled_binary()
	@dstbin
      end

      def configure(conf)
	bug() unless conf.instance_of?(Configuration)
	@configuration = conf
      end

      def adapted_configuration
	@configuration
      end

      def remove_binary_if_raised(&b)
	begin
	  b.call()
	rescue => e
	  FileUtils.remove_entry_secure(@dstbin) if File.exist?(@dstbin)
	  raise(e)
	end
      end

      def compile_c_source(c_source, dep)
	base = load_base_configuration()
	FileUtils.remove_entry_secure(@dstdir, true)
	FileUtils.mkdir(@dstdir)
	File.open("#{@dstdir}/#{@dstfile}", 'w'){|f| f.write(c_source)}
	gen_makefile(@dstdir, @dstfile)
	gen_header_files(@dstdir)
	Dir.chdir(@dstdir) do
	  File.open(@dstfile, 'wb:us-ascii') do |f|
	    f.write(c_source.dup.force_encoding('US-ASCII'))
	  end
	  if CONFIG["host_os"].match(/mswin/)
	    # windows
	    makecmd = 'nmake'
	  else
	    # linux, freebsd, solaris
	    makecmd = 'make'
	  end
	  log = `#{makecmd} 2>&1`
	  if $? != 0
	    dlog(c_source)
	    dlog(log)
	    bug("failed to compile c source: status = (#{$?})") 
	  else
	    dlog(c_source, 2)
	    dlog(log, 2)
	  end
	  remove_binary_if_raised do
	    File.open(@conffile, 'wb:us-ascii') do |f|
	      bug() unless @configuration
	      @configuration.dump(f)
	    end
	    File.open(@depfile, 'wb:us-ascii') do |f|
	      bug() unless dep.instance_of?(Dependency)
	      dep.dump(f)
	    end
	  end
	  save_base_configuration(base) if base
	end
      end

      def last_used_configuration_enabled_development?
	File.exist?(@development_mark_path)
      end

      def dump_development_mark()
	bug() unless @configuration
	FileUtils.touch(@development_mark_path) if @configuration.development?
      end

      def dump_specified_configuration(conf)
	remove_binary_if_raised do
	  File.open("#{@specified_configuration_path}", 'wb:us-ascii') do |f|
	    conf.dump(f)
	  end
	end
      end

      def save_base_configuration(conf)
	begin
	  File.open(@base_configuration_path, 'wb:us-ascii') do |f|
	    bug() unless conf.instance_of?(Configuration)
	    conf.dump(f)
	  end
	rescue => e
	  vlog("failed to update base configuration: #{e}")
	end
      end

      def clear_base_configuration()
	return unless File.exist?(@base_configuration_path)
	FileUtils.remove_entry_secure(@base_configuration_path)
      end

      def load_base_configuration()
	return nil unless File.exist?(@base_configuration_path)
	conf_str = File.read(@base_configuration_path)
	Configuration.load(conf_str)
      end

      def load_last_specified_configuration()
	return nil unless File.exist?(@specified_configuration_path)
	conf_str = File.read(@specified_configuration_path)
	Configuration.load(conf_str)
      end

      def dump_suggested_configuration(conf)
	remove_binary_if_raised do
	  File.open("#{@suggested_configuration_path}", 'wb:us-ascii') do |f|
	    conf.dump(f)
	  end
	end
      end

      def load_suggested_configuration(dev)
	return nil unless File.exist?(@suggested_configuration_path)
	conf_str = File.read(@suggested_configuration_path)
	conf = Configuration.load(conf_str)
	return nil unless conf
	conf.development(dev)
	conf
      end

      def load_last_used_configuration()
	return nil unless File.exist?("#{@dstdir}/#{@conffile}")
	exist_conf_str = File.read("#{@dstdir}/#{@conffile}")
	# exist_conf_str が tainted であるため、Marshal.load で読み込んだ class も tainted になってしまう
	# RDoc だと、それのせいで Insecure: can't modify array となる
	#exist_conf_str.untaint
	Configuration.load(exist_conf_str)
      end

      def load_dependency()
	raise(LoadError.new("method dependency file is not exist")) unless File.exist?(@deppath)
	str = File.read(@deppath)
	str.untaint # FIXME
	Dependency.load(str)
      end

      def gen_makefile(dir, file)
	Dir.chdir(dir) do
	  File.open('extconf.rb', 'wb:us-ascii') do |f|
	    f.write <<-EOS
  require 'mkmf'
  create_makefile("#{File.basename(file, ".c")}")
	  EOS
	  end
	  runruby = CONFIG["prefix"] + "/bin/" + CONFIG["ruby_install_name"] 
	  dlog(`#{runruby} extconf.rb`, 2)
	  bug("failed to generate extconf.rb: status = (#{$?})") if $? != 0
	end
      end

      def gen_header_files(dir)
	Dir.chdir(dir) do
	  Headers.each_pair do |k, v|
	    File.open(k, 'wb:binary'){|f| f.write(v)}
	    FileUtils.touch("insns.inc")
	  end
	end
      end
    end
  end
end

