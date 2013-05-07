
module PuavoRest


class LdapModel

  def initialize(ldap_conn, organisation)
    @ldap_conn = ldap_conn
    @organisation = organisation
  end

  # Escape unsafe user input for safe LDAP filter use
  #
  # @see https://github.com/ruby-ldap/ruby-net-ldap/blob/8ddb2d7c8476c3a2b2ad9fcd367ca0d36edaa611/lib/net/ldap/filter.rb#L247-L264
  def self.escape(s)
    # TODO
    # https://github.com/ruby-ldap/ruby-net-ldap/blob/master/lib/net/ldap/filter.rb
    s
  end

  # Define conversion between LDAP attribute and the JSON attribute
  # @param ldap_name [Symbol] LDAP attribute to convert
  # @param json_name [Symbol] Value conversion block. Default: Get first array item
  # @param convert [Block] Use block to 
  # @see convert
  def self.ldap_attr_conversion(ldap_name, json_name, &convert)
    @@ldap2json[ldap_name.to_s] = {
      :attr => json_name.to_s,
      :convert => convert || lambda { |v| Array(v).first }
    }
  end

  # Return LDAP attributes that will be converted
  def self.ldap_attrs
    @@ldap2json.keys
  end

  # Covert LDAP entry Hash to JSON style Hash
  # @param entry [Hash] Ruby Hash from #filter
  # @param all [Boolean] Include also those attributes that have no attribute
  # conversion
  # @see ldap_attr_conversion
  # @see #filter
  def self.convert(entry, all=false)
    h = {}

    entry.each do |k,v|
      if ob = @@ldap2json[k.to_s]
        h[ob[:attr]] = ob[:convert].call(v)
      elsif all
        h[k] = v
      end
    end

    return h
  end

  # LDAP base for this model. Must be implemented by subclasses
  def ldap_base
    raise "not implemented"
  end

  # LDAP::LDAP_SCOPE_SUBTREE filter search for #ldap_base
  # @param filter [String] LDAP filter
  # @param attributes [Array] Limit search results to these attributes
  # @see #ldap_base
  # @see http://ruby-ldap.sourceforge.net/rdoc/classes/LDAP/Conn.html#M000025
  def filter(filter, attributes=nil)
    res = []

    @ldap_conn.search(
      ldap_base,
      LDAP::LDAP_SCOPE_SUBTREE,
      filter,
      attributes
    ) do |entry|
      res.push(entry.to_hash)
    end

    return res
  end

end



# Possible error responses in PuavoRest.
#
# Example response:
#
#    {
#      "error": {
#        "code": <[String] error code>,
#        "message": <[String] human readable error message>,
#
#      }
#    }
#
module ErrorMethods

  # Halt request with not_found code
  # @param msg [String] Human readable description of the situation
  # @return [HTTP response]
  def bad_credentials(msg="")
    json_format(401, "bad_credentials", msg)
  end

  # Halt request with not_found code
  # @param msg [String] Human readable description of the situation
  # @return [HTTP response]
  def not_found(msg="")
    json_format(404, "not_found", msg)
  end

  private

  def json_format(status, code, msg)
    halt status, {"Content-Type" => "application/json"}, {
      "error" => {
        "code" => code,
        "message" => msg
      }
    }.to_json
  end

end

# Abstract Sinatra base class which add ldap connection to instance scope
class LdapSinatra < Sinatra::Base

  include ErrorMethods
  helpers Sinatra::JSON


  not_found do
    puts "not found in #{ self.class }"
    not_found "Cannot find resource from #{ request.path }"
  end


  before "/:organisation/*" do

    # XXX: Escape!
    @organisation = params["organisation"]

    cred = request.env["PUAVO_CREDENTIALS"]
    if not cred
      bad_credentials "No credentials supplied"
    end

    @ldap_conn = LDAP::Conn.new("precise64.opinsys.net")
    @ldap_conn.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    @ldap_conn.start_tls

    begin
      puts "binding #{ cred[:username] } in #{ self.class }"
      @ldap_conn.bind(cred[:username], cred[:password])
    rescue LDAP::ResultError
      bad_credentials("Bad username or password")
    end

  end

  # Model instance factory
  # Create new model instance with the current organisation and ldap connection
  #
  # @param klass [Model class]
  # @return [Model instance]
  def new_model(klass)
    klass.new(@ldap_conn, @organisation)
  end

end

end
