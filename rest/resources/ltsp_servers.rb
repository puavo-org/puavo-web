require "fileutils"
require_relative "../local_store"
require_relative "../lib/error_codes"
require_relative "./hosts"

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
      Time.now.to_i - server.state["updated"] < MAX_AGE
    end
  end

  def filter_by_image(ltsp_image)
    @servers = @servers.select do |server|
      server.state["ltsp_image"] == ltsp_image
    end
  end

  def filter_has_state
    @servers = @servers.select do |server|
      server.state
    end
  end

  # Filter out servers that are dedicated to some other schools
  def filter_by_other_schools(school_dn)
    @servers = @servers.select do |server|
      schools_dedicated_to = Array(server.school_dns)
      # If schools attribute is empty server will serve any school
      # TODO: dn string comparison!!
      schools_dedicated_to.empty? || schools_dedicated_to.include?(school_dn.downcase)
    end
  end

  # get only those servers that are dedicated to this school
  def filter_by_school(school_dn)
    @servers = @servers.select do |server|
      # TODO: dn string comparison!!
      Array(server.school_dns).include?(school_dn.downcase)
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
      a["state"]["load_avg"] <=> b["state"]["load_avg"]
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

class LtspServer < Host
  include LocalStore

  ldap_map(:puavoSchool, :school_dns) { |v| Array(v).map{ |v| v.downcase } }

  def self.ldap_base
    "ou=Servers,ou=Hosts,#{ organisation["base"] }"
  end

  # Bootservers are saved to same ldap branch as ltsp servers so we must filter
  # with type too
  def self.base_filter
    "(puavoDeviceType=ltspserver)"
  end

  def self.by_hostname(hostname)
    by_attr(:hostname, hostname)
  end

  def self.by_hostname!(hostname)
    by_attr!(:hostname, hostname)
  end

  def self.by_fqdn!(fqdn)
    hostname = fqdn.split(".").first
    by_hostname!(hostname)
  end

  def self.all_with_state
    all.select do |server|
      not server.state.nil?
    end
  end

  def state_key
    "ltsp_server:#{ hostname }:state"
  end

  def save_state(state)
    state["updated"] = Time.now.to_i
    local_store[state_key] = state.to_json
    state
  end

  def state
    json = local_store[state_key]
    JSON.parse(json) if json
  end

  def to_hash
    o = super
    o["state"] = state
    o
  end

  def preferred_image
     if get_own(:preferred_image).nil?
       organisation.preferred_image
     else
       get_own(:preferred_image).strip
     end
  end

  computed_attr :mountpoints
  def mountpoints
    schools_mountpoints = []
    schools.each do |school|
      schools_mountpoints += school.mountpoints.map{ |m| JSON.parse(m) }
    end
    schools_mountpoints
  end

  def schools
    @schools ||= school_dns.map{ |dn| School.by_dn(dn) }
  end
end

# Load balancer resource for LTSP servers
class LtspServers < LdapSinatra

  # Get list of LTSP servers sorted by they load. Most idle server is the first
  #
  # @param all [Boolean] Include old servers too
  # @!macro route
  get "/v3/ltsp_servers" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    json LtspServer.all
  end

  # Computed resource for the most idle ltsp server
  #
  # Examples:
  # curl /v3/hogwarts/ltsp_servers/_most_idle
  # => {"load_avg":0.035,"ltsp_image":null,"updated":"2013-05-20 11:29:13 +0300","hostname":"someservername"}
  #
  # @!macro route
  get "/v3/ltsp_servers/_most_idle" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    logger.warn "DEPRECATED!! Call to legacy _most_idle route. Use POST /v3/sessions !"
    filtered = ServerFilter.new(LtspServer.all_with_state)
    filtered.filter_old
    filtered.filter_has_state
    filtered.sort_by_load
    server = filtered.first

    if server
      logger.info "Sending '#{ server["hostname"] }' as the most idle server to #{ request.ip }"
    else
      logger.warn "Cannot find any ltsp servers..."
      halt 400, json(:error => "cannot find any ltsp servers...")
    end

    json server
  end

  get "/v3/ltsp_servers/:fqdn" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    json LtspServer.by_fqdn!(params["fqdn"])
  end

  # Set LTSP server idle status as x-www-form-urlencoded. If cpu_count is
  # provided load_avg will be divided using it.
  #
  # @param [Float] load_avg
  # @param [Fixnum] cpu_count optional
  # @!macro route
  put "/v3/ltsp_servers/:fqdn" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    state = {}

    if params["cpu_count"] && params["cpu_count"].to_i == 0
      logger.fatal "Invalid cpu count '#{ params["cpu_count"] }' for '#{ params["fqdn"] }'"
      raise BadInput, :user => "0 cpu_count makes no sense"
    end

    if params["cpu_count"]
      state["load_avg"] = params["load_avg"].to_f / params["cpu_count"].to_i
    else
      state["load_avg"] = params["load_avg"].to_f
    end

    state["ltsp_image"] = params["ltsp_image"]
    state["fqdn"] = params["fqdn"]
    server = LtspServer.by_fqdn!(params["fqdn"])
    server.save_state(state)
    json server
  end

end
end
