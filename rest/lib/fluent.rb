
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
    attrs["msg"] = msg
    attrs = clean(attrs)
    attrs[:meta] = @base_attrs
    attrs[:meta][:level] = level
    @logger.post(@tag, attrs)
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

  def clean(hash)
    hash = hash.symbolize_keys
    hash.each do |k, v|
      # Sensor keys that contain word password
      if k.to_s.include?("password")
        hash[k] = "*"*v.size
      elsif v.kind_of?(Hash)
        hash[k] = clean(v)
      end
    end
    return hash
  end

end
