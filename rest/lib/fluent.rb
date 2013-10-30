
require 'fluent-logger'

Fluent::Logger::FluentLogger.open(nil, :host=>'localhost', :port=>24224)

class FluetWrap

  def initialize(tag, base_attrs)
    @tag = tag
    @base_attrs = clean_passwords(base_attrs)
  end

  def log(level, msg, attrs=nil)
    attrs ||= {}
    attrs["msg"] = msg
    attrs = clean_passwords(attrs)
    attrs[:meta] = @base_attrs
    attrs[:meta][:level] = level
    Fluent::Logger.post(@tag, attrs)
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

  def merge(more_attrs={})
    FluetWrap.new(@tag, @base_attrs.merge(more_attrs))
  end

  def clean_passwords(attrs)
    clean(attrs,
      :new_password,
      :new_password_confirmation,
      :password_plaintext,
      :password,
      :authenticity_token
    )
  end

  def clean(hash, *del_keys)
    hash = hash.symbolize_keys
    hash.each do |k, v|
      if del_keys.include?(k)
        hash.delete(k)
      elsif v.class == Hash
        hash[k] = clean(v, *del_keys)
      end
    end
    return hash
  end

end
