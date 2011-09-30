module CastOff::Util
  private

  @@debug_level = 0
  @@verbose_mode = false

  DEBUG_LEVEL_MAX = 2
  def self.set_debug_level(lv)
    raise(ArgumentError.new("debug level should be Integer")) unless lv.is_a?(Integer)
    raise(ArgumentError.new("debug level should be >= 0 && <= #{DEBUG_LEVEL_MAX}")) unless 0 <= lv && lv <= DEBUG_LEVEL_MAX
    @@debug_level = lv
  end

  def self.set_verbose_mode(b)
    @@verbose_mode = b
  end

  def dlog(message, level = 1)
    if level <= @@debug_level
      STDERR.puts(message)
    end
  end
  public(:dlog)

  def vlog(message)
    if @@verbose_mode || @@debug_level > 0
      STDERR.puts(message)
    end
  end
  public(:vlog)

  def bt_and_bye()
    STDERR.puts("-------------------- backtrace --------------------")
    begin
      raise
    rescue => e
      STDERR.puts(e.backtrace)
    end
    exit
  end

  def todo(message = nil)
    STDERR.puts("<<< TODO #{message} :#{caller[0]} >>>")
    bt_and_bye()
  end

  def bug(message = nil)
    STDERR.puts("<<< BUG #{message} :#{caller[0]} >>>")
    bt_and_bye()
  end

=begin
  def method_missing(name, *args, &block)
    STDERR.puts("No Method #{name}:#{caller[0]}")
    bt_and_bye()
  end
=end
end
