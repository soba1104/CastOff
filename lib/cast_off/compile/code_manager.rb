# coding=utf-8

require 'rbconfig'
require 'fileutils'

module CastOff
  module Compiler
    class CodeManager
      include RbConfig
      include CastOff::Util
      extend CastOff::Util

      attr_reader :signiture, :compilation_target

      CastOffDir = "#{ENV["HOME"]}/.CastOff"
      FileUtils.mkdir(CastOffDir) unless File.exist?(CastOffDir)
      BaseDir = "#{CastOffDir}/#{File.expand_path(__FILE__).gsub(/\.|\/|-|:/, "_")}"
      FileUtils.mkdir(BaseDir) unless File.exist?(BaseDir)

      @@program_name = File.expand_path($PROGRAM_NAME)
      CastOff::Compiler.class_eval do
        def program_name=(dir)
          CastOff::Compiler::CodeManager.class_variable_set(:@@program_name, dir)
        end
      end

      def self.program_dir()
        dir = "#{BaseDir}/#{@@program_name.gsub(/\.|\/|-|:/, "_")}"
        FileUtils.mkdir(dir) unless File.exist?(dir)
        dir
      end

      def self.clear()
        dir = program_dir()
        vlog("delete #{dir}")
        FileUtils.remove_entry_secure(dir)
        dir
      end

      def self.delete_from_compiled(entry)
        compiled = load_autocompiled()
        return false unless compiled
        return false unless compiled.delete(entry)
        dump_auto_compiled(compiled)
        return true
      end

      @@compiled_methods_fetch_str = nil
      @@compiled_methods_load_str  = nil
      def self.load_autocompiled()
        begin
          dir = program_dir()
          # fetch classes
          path = "#{dir}/.compiled_methods"
          return nil unless File.exist?(path)
          if !@@compiled_methods_fetch_str
            @@compiled_methods_fetch_str = File.open(path, 'rb:us-ascii').read() 
            @@compiled_methods_fetch_str.untaint # FIXME
          end
          Marshal.load(@@compiled_methods_fetch_str)
          # load compiled methods information
          path = "#{dir}/compiled_methods"
          return nil unless File.exist?(path)
          if !@@compiled_methods_load_str
            @@compiled_methods_load_str = File.open(path, 'rb:us-ascii').read() 
            @@compiled_methods_load_str.untaint # FIXME
          end
          Marshal.load(@@compiled_methods_load_str)
        rescue ArgumentError, NameError
          false
        end
      end

      def self.dump_auto_compiled(compiled)
        dir = program_dir()
        path = "#{dir}/.compiled_methods"
        File.open("#{path}", 'wb:us-ascii') do |f|
          Marshal.dump(compiled.map{|c| c.first}, f) # dump only classes
        end
        @@compiled_methods_fetch_str = nil
        path = "#{dir}/compiled_methods"
        File.open("#{path}", 'wb:us-ascii') do |f|
          Marshal.dump(compiled, f)
        end
        @@compiled_methods_load_str = nil
        load_autocompiled()
      end

      def create_dstdir()
        FileUtils.mkdir(@dstdir) unless File.exist?(@dstdir)
        FileUtils.touch(@lockpath) unless File.exist?(@lockpath)
      end

      def version_up()
        bug() unless File.exist?(@versionpath)
        v = File.read(@versionpath).to_i
        bug() if v < 0
        v = [@version, v].max + 1
        vlog("version: #{@version} => #{v}")
        File.open(@versionpath, 'w'){|f| f.write(v)}
      end

      def fetch_version()
        bug() unless File.exist?(@dstdir)
        if File.exist?(@versionpath)
          version = File.read(@versionpath)
        else
          version = 0
        end
        version.to_i
      end

      def initialize(filepath, line_no)
        @filepath = filepath
        @line_no = line_no
        base_sign = "#{@filepath}_#{@line_no}".gsub(/\.|\/|-|:/, "_")
        dir = self.class.program_dir()
        @dstdir = "#{dir}/#{base_sign}"
        @lockpath = "#{@dstdir}/lock"
        @versionfile = "version"
        @versionpath = "#{@dstdir}/#{@versionfile}"
        create_dstdir()
        @version = fetch_version()
        @signiture = "#{base_sign}_ver#{@version}"
        @dstfile = "#{@signiture}.c"
        @depfile = "#{@signiture}.mdep"
        @deppath = "#{@dstdir}/#{@depfile}"
        @conffile = "#{@signiture}.conf"
        @base_configuration_path = "#{@dstdir}/#{base_sign}.base.conf"
        @annotation_path = "#{@dstdir}/#{@signiture}.ann"
        @development_mark_file = "development"
        @development_mark_path = "#{@dstdir}/#{@development_mark_file}"
        @dstbin = "#{@dstdir}/#{@signiture}.so"
        @compilation_target = nil
      end

      class CompilationTarget
        include CastOff::Util

        attr_reader :target_object, :method_id

        def initialize(target, mid, singleton)
          @target_object = target
          @method_id = mid
          @singleton_p = singleton
          bug() unless @method_id.is_a?(Symbol)
          bug() unless @singleton_p == true || @singleton_p == false
        end

        def singleton_method?
          @singleton_p
        end
      end

      def compilation_target_is_a(target, mid, singleton)
        @compilation_target = CompilationTarget.new(target, mid, singleton)
      end

      def do_atomically()
        bug() unless block_given?
        File.open(@lockpath, "w") do |f|
          f.flock(File::LOCK_EX)
          yield
        end
      end

      def target_file_updated?
        not (File.exist?(@dstbin) && File.mtime(@filepath).tv_sec < File.mtime(@dstbin).tv_sec)
      end

      def compiled_binary()
        @dstbin
      end

      def remove_binary_if_raised(&b)
        begin
          b.call()
        rescue => e
          FileUtils.remove_entry_secure(@dstbin) if File.exist?(@dstbin)
          raise(e)
        end
      end

      def compile_c_source(c_source, conf, dep)
        base = load_base_configuration()
        FileUtils.remove_entry_secure(@dstdir, true)
        create_dstdir()
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
              bug() unless conf
              conf.dump(f)
            end
            File.open(@depfile, 'wb:us-ascii') do |f|
              bug() unless dep.instance_of?(Dependency)
              dep.dump(f)
            end
          end
          bug() unless @version.is_a?(Integer)
          File.open(@versionfile, 'w'){|f| f.write(@version)}
          save_base_configuration(base) if base
        end
      end

      def last_configuration_enabled_development?
        File.exist?(@development_mark_path)
      end

      def dump_development_mark(conf)
        bug() unless conf
        FileUtils.touch(@development_mark_path) if conf.development?
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
        conf_str = File.open(@base_configuration_path, 'rb:us-ascii').read()
        Configuration.load(conf_str)
      end

      def load_last_configuration()
        return nil unless File.exist?("#{@dstdir}/#{@conffile}")
        exist_conf_str = File.open("#{@dstdir}/#{@conffile}", 'rb:us-ascii').read()
        # exist_conf_str が tainted であるため、Marshal.load で読み込んだ class も tainted になってしまう
        # RDoc だと、それのせいで Insecure: can't modify array となる
        #exist_conf_str.untaint
        Configuration.load(exist_conf_str)
      end

      def save_annotation(ann)
        bug() unless ann.is_a?(Hash)
        remove_binary_if_raised do
          File.open("#{@annotation_path}", 'wb:us-ascii'){|f| Marshal.dump(ann, f)}
        end
      end

      def load_annotation()
        return nil unless File.exist?(@annotation_path)
        ann_str = File.open(@annotation_path, 'rb:us-ascii').read()
        ann_str.untaint
        Marshal.load(ann_str)
      end

      def load_dependency()
        raise(LoadError.new("method dependency file is not exist")) unless File.exist?(@deppath)
        str = File.open(@deppath, 'rb:us-ascii').read()
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

