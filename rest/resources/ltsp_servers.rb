require "pstore"
require "fileutils"
require_relative "../pstore_model"

module PuavoRest


class ServerFilter

  # How old servers we report as available
  MAX_AGE = 60 * 2

  def initialize(servers)
    @servers = servers
  end

  def to_a
    @servers.to_a
  end

  def first
    @servers.first
  end

  def empty?
    @servers.empty?
  end

  # filter out servers that have not posted their load under MAX_AGE.  ie.
  # assume them being offline
  def filter_old
    @servers = @servers.select do |server|
      Time.now - server["updated"] < MAX_AGE
    end
  end

  def filter_by_image(ltsp_image)
    @servers = @servers.select do |server|
      server["ltsp_image"] == ltsp_image
    end
  end


  # Filter out servers that are dedicated to some other schools
  def filter_by_other_schools(school_dn)
    @servers = @servers.select do |server|
      schools = Array(server["schools"])
      # If schools attribute is empty server will serve any school
      schools.empty? || schools.include?(school_dn)
    end
  end

  # get only those servers that are dedicated to this school
  def filter_by_school(school_dn)
    @servers = @servers.select do |server|
      Array(server["schools"]).include?(school_dn)
    end
  end

  # client can be limited to specific server
  def filter_by_server(server_dn)
    @servers = @servers.select do |server|
      server["dn"] == server_dn
    end
  end

  def sort_by_load
    @servers = @servers.sort do |a, b|
      a["load_avg"] <=> b["load_avg"]
    end
  end

  # Apply method of this class to @servers but revert it if it goes to empty
  def safe_apply(method, *args)
    prev = @servers
    send(method, *args)
    if @servers.empty?
      @servers = prev
    else
      @servers
    end
  end

end


# Pstore packed model for LTSP server data. Currently contains mainly load
# balancing data
class LtspServersModel < LdapModel

  ldap_attr_conversion :dn, :dn
  ldap_attr_conversion(:puavoSchool, :schools) { |v| v }

  # How old servers we report as available
  MAX_AGE = 60 * 2

  def initialize(ldap_conn, organisation_info)
    @store = LocalStore.from_domain organisation_info["domain"] + self.class.name
    super(ldap_conn, organisation_info)
  end

  def set_server(key, data)

    if filter("(puavoHostname=#{ LdapModel.escape key })").empty?
      raise BadInput, "cannot find server from LDAP for #{ key }"
    end

    data["updated"] = Time.now
    data["hostname"] = key
    @store.set key, data
    data
  end


  def ldap_base
    "ou=Servers,ou=Hosts,#{ @organisation_info["base"] }"
  end

  def all
    @store.all.map do |server|
      inject_ldap_data server
    end
  end

  def inject_ldap_data(server)
    data = filter(
      "(puavoHostname=#{ LdapModel.escape server["hostname"] })"
    ).first

    if data
      server.merge(LtspServersModel.convert data)
    else
      server
    end
  end

  def get(key)
    inject_ldap_data @store.get(key)
  end

  # Return the most idle LTSP server which is update under MAX_AGE
  #
  # @return [Array]
  def most_idle(ltsp_image=nil)
    servers = ServerFilter.new(@store.all)
    servers.filter_old
    servers.safe_apply(:filter_by_image, ltsp_image)
    servers.sort_by_load
    servers.to_a
  end

end


# Load balancer resource for LTSP servers
class LtspServers < LdapSinatra

  # auth Credentials::BasicAuth, :skip => :get
  auth Credentials::BasicAuth
  auth Credentials::BootServer

  before do
    @m = new_model(LtspServersModel)
  end

  # Get list of LTSP servers sorted by they load. Most idle server is the first
  #
  # @param all [Boolean] Include old servers too
  # @!macro route
  get "/v3/ltsp_servers" do
    if params["all"]
      json limit @m.all
    else
      json limit ServerFilter.new(@m.all).filter_old
    end
  end

  # Computed resource for the most idle ltsp server
  #
  # Set format to txt to get only the server name as plain/text
  #
  # Examples:
  # curl /v3/hogwarts/ltsp_servers/_most_idle
  # => {"load_avg":0.035,"ltsp_image":null,"updated":"2013-05-20 11:29:13 +0300","hostname":"someservername"}
  #
  # curl /v3/hogwarts/ltsp_servers/_most_idle.txt
  # => someservername
  #
  # @!macro route
  get "/v3/ltsp_servers/_most_idle.?:format?" do
    logger.warn "Call to legacy _most_idle route. Use POST /v3/sessions in future"
    server = @m.most_idle.first
    if server
      logger.info "Sending '#{ server["hostname"] }' as the most idle server to #{ request.ip }"
    else
      logger.warn "Cannot find any ltsp servers..."
      halt 400, json(:error => "cannot find any ltsp servers...")
    end

    json server
  end

  get "/v3/ltsp_servers/:hostname" do
    if server = @m.get(params["hostname"])
      json server
    else
      not_found "server not found"
    end
  end

  # Set LTSP server idle status as x-www-form-urlencoded. If cpu_count is
  # provided load_avg will be divided using it.
  #
  # @param [Float] load_avg
  # @param [Fixnum] cpu_count optional
  # @!macro route
  put "/v3/ltsp_servers/:hostname" do
    require_auth

    attrs = {}

    if params["cpu_count"] && params["cpu_count"].to_i == 0
      logger.fatal "Invalid cpu count '#{ params["cpu_count"] }' for '#{ params["hostname"] }'"
      halt 400, json("message" => "0 cpu_count makes no sense")
    end

    if params["cpu_count"]
      attrs["load_avg"] = params["load_avg"].to_f / params["cpu_count"].to_i
    else
      attrs["load_avg"] = params["load_avg"].to_f
    end

    attrs["ltsp_image"] = params["ltsp_image"]

    json @m.set_server(params["hostname"], attrs)
  end

  def search(base, attrs=[], filter="(objectclass=*)")
    res = nil
    @ldap_conn.search(base, LDAP::LDAP_SCOPE_SUBTREE, filter,
      attrs
    ) do |entry|
      res = entry.to_hash
      break
    end
    res
  end
end
end
