module CastOff
  class Suggestion
    include CastOff::Util

    def initialize(iseq, io)
      raise ArgumentError("invalid io object") unless io.respond_to?(:puts)
      @suggestion = []
      @handler = []
      @iseq = iseq
      @io = io
    end

    def dump_at_exit()
      return if @handler.empty?
      at_exit do
	@handler.each{|h| h.call}
	if @suggestion.size() > 0
	  @io.puts("<<<<<<<<<< Suggestion(#{target_name()}) >>>>>>>>>>")
	  @suggestion.each do |s|
	    @io.puts s
	    @io.puts
	  end
	end
      end
    end

    def add_handler(&b)
      bug() unless b.is_a?(Proc)
      @handler << b
    end

    def add_suggestion(msg, titles, contents, pretty = true)
      suggestion = []
      l_msg = msg.length
      column_size = titles.size
      contents = contents.inject([]) do |ary, c|
	bug() unless c.size == column_size
	c.map! do |v|
	  v.split("\n")
	end
	max = c.inject(0) do |m, v|
	  l = v.size
	  m > l ? m : l
	end
	max.times do |i|
	  ary << c.map{|v| v[i] || ''}
	end
	ary
      end
      l_titles = contents.inject(titles.map{|t| t.length}) do |a0, a1|
	bug() unless a0.size == a1.size
	a0.zip(a1).map do |(v0, v1)|
	  length = v1.length
	v0 > length ? v0 : length
	end
      end
      title = titles.zip(l_titles).map{|(t, l)| t.center(l)}.join(" | ")
      l_title = title.length
      width = l_msg > l_title ? l_msg : l_title
      if width != l_title
	bonus = width - l_title
	adjust = column_size - bonus % column_size
	width += adjust
	bonus += adjust
	bonus /= column_size
	l_titles.map!{|l| l + bonus}
	title = titles.zip(l_titles).map{|(t, l)| t.center(l)}.join(" | ")
      end
      sep = "-" * width
      suggestion << " #{sep} "
      suggestion << "|#{msg.center(width)}|"
      suggestion << "|#{sep}|"
      suggestion << "|#{title.center(width)}|"
      suggestion << "|#{sep}|"
      if pretty
	side = "|"
      else
	side = ""
      end
      contents.each do |line|
	suggestion << "#{side}#{line.zip(l_titles).map{|c, l| pretty ? c.center(l) : c }.join(" | ")}#{side}"
      end
      suggestion << " #{sep} "
      @suggestion << suggestion.join("\n")
    end

    private

    def target_name()
      ary = @iseq.to_a()
      name = ary[5]
      filepath = ary[7] || '<no file>'
      line = ary[8]
      "#{name}: #{filepath} #{line}"
    end
  end
end

