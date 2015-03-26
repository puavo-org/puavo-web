require "yajl"
require "msgpack"

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

  def handle_json
    json_parser = Yajl::Parser.new
    records = json_parser.parse(request.body)

    klass = records.class
    if klass == Hash
      records = [records]
    elsif klass == Array
      records = records
    else
      raise BadInput, :user => "Invalid json type #{ klass }"
    end

    puts "Relaying #{ records.size } fluentd records from http to local fluentd"

    records.each do |r|
      tag = r["_tag"]
      time = r["_time"]
      r.delete("_tag")
      r.delete("_time")

      # https://github.com/fluent/fluent-logger-ruby/blob/master/lib/fluent/logger/fluent_logger.rb#L115
      if not fluent_logger.post_with_time(tag, r, time)
        raise InternalError, :user => "Failed to relay fluent packages"
      end
    end
  end

  def handle_msgpack
    body_size = request.body.size
    self.flog.info("Relaying fluentd chunk", {
      :format => "msgpack",
      :bytes => body_size
    })

    parsing_start = Time.now
    u = MessagePack::Unpacker.new(request.body)
    parsing_time = Time.now - parsing_start

    puts "Relaying #{ request.body.size } bytes of msgpack data to fluentd"


    relaying_start = Time.now
    i = 0
    u.each do |(tag, time, r)|
      i += 1
      if not fluent_logger.post_with_time(tag, r, time)
        raise InternalError, :user => "Failed to relay fluent packages"
      end
    end
    relaying_time = Time.now - relaying_start

    self.flog.info("Relayed fluentd chunk", {
      :format => "msgpack",
      :parse_ms => parsing_time * 1000,
      :relay_ms => relaying_time * 1000,
      :total_ms => (relaying_time+parsing_time) * 1000,
      :bytes => body_size,
      :count => i
    })

    puts "Relayed #{ i } records to fluentd"
  end


  post "/v3/fluent" do
    auth :basic_auth, :kerberos

    request.body.rewind

    if request.content_type.downcase == "application/json"
      handle_json
    elsif request.content_type.downcase == "application/x-msgpack"
      handle_msgpack
    end

    "ok"
  end

end
end
