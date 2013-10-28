
require 'fluent-logger'
require 'socket'

Fluent::Logger::FluentLogger.open(nil, :host=>'localhost', :port=>24224)

hostname = Socket.gethostname

class FluetWrap

  def initialize(tag, base_attrs)
    @tag = tag
    @base_attrs = base_attrs
  end

  def log(msg, attrs={})
    attrs["msg"] = msg
    attrs = clean(attrs.merge(@base_attrs),
      :new_password,
      :new_password_confirmation,
      :password_plaintext,
      :password,
      :authenticity_token
    )
    Fluent::Logger.post(@tag, attrs)
  end

  def info(msg, attrs={})
    log(msg, attrs.merge(:level => "info"))
  end

  def warn(msg, attrs={})
    log(msg, attrs.merge(:level => "warn"))
  end

  def error(msg, attrs={})
    log(msg, attrs.merge(:level => "error"))
  end

  def merge(tag, more_attrs={})
    FluetWrap.new(@tag + "." + tag, @base_attrs.merge(more_attrs))
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

FLOG = FluetWrap.new("puavo-web", "hostname" => hostname)
FLOG.info "starting"
