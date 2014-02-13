
require 'fluent-logger'

Fluent::Logger::FluentLogger.open(nil, :host=>'localhost', :port=>24224)

class FluentWrap

  def initialize(tag, base_attrs, logger=Fluent::Logger)
    @tag = tag
    @logger = logger
    @base_attrs = clean(base_attrs)
  end

  def log(level, msg, attrs=nil)
    attrs ||= {}
    attrs[:msg] = msg
    attrs[:meta] = @base_attrs
    attrs[:meta][:level] = level
    attrs = clean(attrs)

    @logger.post(@tag, attrs)
    log_stdout(attrs)
  end

  def log_stdout(attrs)
    return if ENV["RACK_ENV"] == "test"
    level = attrs[:meta][:level]
    msg = attrs[:msg]

    attrs = attrs.dup
    attrs.delete(:msg)
    attrs.delete(:meta)

    puts "FLUENT-#{ level }: #{ msg } #{ attrs.inspect }"
  end

  def info(msg, attrs=nil)
    log("info", msg, attrs)
  end

  def warn(msg, attrs=nil)
    log("warn", msg, attrs)
  end

  def error(msg, attrs=nil)
    log("error", msg, attrs)
  end

  def merge(more_attrs=nil, new_logger=nil)
    FluentWrap.new(
      @tag,
      @base_attrs.merge(more_attrs || {}),
      new_logger || @logger
    )
  end

  def filter_passwords(val)
    return val if !val.kind_of?(Hash)
    val = val.dup
    val.each do |k, v|
      # Sensor keys that contain word password
      if k.to_s.include?("password")
        val[k] = "[FILTERED]"
      end
    end
    val
  end

  def clean(val)
    val = filter_passwords(val)

    if val.kind_of?(Array)
      val = val.map do |val|
        clean(val)
      end
    end

    if val.kind_of?(Hash)
      val = val.dup
      val.each do |k, v|
        val[k] = clean(v)
      end
    end

    val
  end

end
