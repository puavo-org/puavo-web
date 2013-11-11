
FLUENT_RELAY = 
module PuavoRest

class FluentRelay < LdapSinatra

  def self.fluent_logger
    @@logger ||= Fluent::Logger::FluentLogger.new(nil, :host=>'localhost', :port=>24224)
  end

  def fluent_logger
    self.class.fluent_logger
  end

  def self.fluent_logger=(logger)
    @@logger = logger
  end

  post "/v3/fluent" do
    auth :basic_auth, :kerberos

    if request.content_type.downcase != "application/json"
      raise BadInput, :user => "Only json body is allowed"
    end

    request.body.rewind
    records = JSON.parse(request.body.read)

    klass = records.class
    if klass == Hash
      records = [records]
    elsif klass == Array
      records = records
    else
      raise BadInput, :user => "Invalid json type #{ klass }"
    end

    records.each do |r|
      tag = r["_tag"]
      time = r["_time"]
      r.delete("_tag")
      r.delete("_time")
      if not fluent_logger.post_with_time(tag, time, r)
        raise InternalError, :user => "Failed to relay fluent packages"
      end
    end

    "ok"
  end

end
end
