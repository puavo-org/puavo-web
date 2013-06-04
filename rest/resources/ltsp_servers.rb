require "pstore"
require "fileutils"
require_relative "../pstore_model"

module PuavoRest

# Pstore packed model for LTSP server data. Currently contains mainly load
# balancing data
class LtspServersModel < PstoreModel

  # How old servers we report as available
  MAX_AGE = 60 * 2

  # Return all known ltsp servers which updated under MAX_AGE
  #
  # @return [Array]
  def all_without_old
    all.select do |server|
      Time.now - server[:updated] < MAX_AGE
    end
  end

  def set_server(key, data)
    data[:updated] = Time.now
    data[:hostname] = key
    set key, data
  end


  # Return the most idle LTSP server which is update under MAX_AGE
  #
  # @return [Array]
  def most_idle(ltsp_image=nil)
    servers = all_without_old
    if ltsp_image
      servers.select! do |s|
        s[:ltsp_image] == ltsp_image
      end
    end

    servers.sort do |a, b|
      a[:load_avg] <=> b[:load_avg]
    end
  end

end


# Load balancer resource for LTSP servers
class LtspServers < LdapSinatra

  # auth Credentials::BasicAuth, :skip => :get
  auth Credentials::BasicAuth
  auth Credentials::BootServer

  before do
    @m = LtspServersModel.from_domain @organisation_info["domain"] 
  end

  # Get list of LTSP servers sorted by they load. Most idle server is the first
  #
  # @param all [Boolean] Include old servers too
  # @!macro route
  get "/v3/ltsp_servers" do
    if params["all"]
      json limit @m.all
    else
      json limit @m.all_without_old
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
    server = @m.most_idle.first
    if server
      logger.info "Sending '#{ server[:hostname] }' as the most idle server to #{ request.ip }"
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
      attrs[:load_avg] = params["load_avg"].to_f / params["cpu_count"].to_i
    else
      attrs[:load_avg] = params["load_avg"].to_f
    end

    attrs[:ltsp_image] = params["ltsp_image"]

    @m.set_server(params["hostname"], attrs)

    json "ok" => true
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
