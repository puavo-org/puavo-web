require "pstore"
require "fileutils"

module PuavoRest

# Pstore packed model for LTSP server data. Currently contains mainly load
# balancing data
class LtspServersModel

  # How old servers we report as available
  MAX_AGE = 60 * 2

  def initialize(path)
    FileUtils.mkdir_p File.dirname(path)
    @store = PStore.new(path)
  end

  # set server load average for domain
  # @param [String] domain
  # @param [Float] load_avg
  def set(domain, attrs)
    attrs[:updated] = Time.now
    attrs[:domain] = domain
    @store.transaction do
      @store[domain] = attrs
    end
  end

  # Get server info for domain
  #
  # @param [String] domain
  # @return [Hash]
  def get(domain)
    @store.transaction(true) do
      @store[domain]
    end
  end

  # Return all known ltsp servers
  # @return [Array]
  def all
    a = []
    @store.transaction(true) do
      @store.roots.each do |k|
        a.push(@store[k])
      end
    end
    a
  end

  # Return all known ltsp servers which updated under MAX_AGE
  #
  # @return [Array]
  def all_without_old
    all.select do |server|
      Time.now - server[:updated] < MAX_AGE
    end
  end

  # Return the most idle LTSP server which is update under MAX_AGE
  #
  # @return [Array]
  def most_idle(ltsp_image=nil)
    # TODO: Return server by ltsp image
    # device > school > organisation
    # puavoDeviceImage
    all_without_old.sort do |a, b|
      a[:load_avg] <=> b[:load_avg]
    end.first
  end

end


class DeviceModel < LdapModel

  def image(hostname)

  end

end

# Load balancer resource for LTSP servers
class LtspServers < LdapSinatra

  # auth Credentials::BasicAuth, :skip => :get
  auth Credentials::BasicAuth
  auth Credentials::BootServer

  before do
    @m = LtspServersModel.new File.join(
      CONFIG["ltsp_server_data_dir"],
      "ltsp_servers.#{ @organisation_info["domain"] }.pstore"
    )
  end

  # Get list of LTSP servers sorted by they load. Most idle server is the first
  #
  # @!macro route
  get "/v3/ltsp_servers" do
    json limit @m.all
  end

  # Computed resource for the most idle ltsp server
  #
  # Set format to txt to get only the server name as plain/text
  #
  # Examples:
  # curl /v3/hogwarts/ltsp_servers/_most_idle
  # => {"load_avg":0.035,"ltsp_image":null,"updated":"2013-05-20 11:29:13 +0300","domain":"someservername"}
  #
  # curl /v3/hogwarts/ltsp_servers/_most_idle.txt
  # => someservername
  #
  # @!macro route
  get "/v3/ltsp_servers/_most_idle.?:format?" do
    if params["format"] == "txt"
      txt @m.most_idle[:domain]
    else
      json @m.most_idle
    end
  end

  get "/v3/ltsp_servers/:domain" do
    json @m.get(params["domain"])
  end

  # Set LTSP server idle status as x-www-form-urlencoded. If cpu_count is
  # provided load_avg will be divided using it.
  #
  # @param [Float] load_avg
  # @param [Fixnum] cpu_count optional
  # @!macro route
  put "/v3/ltsp_servers/:domain" do
    require_auth

    attrs = {}

    if params["cpu_count"]
      attrs[:load_avg] = params["load_avg"].to_f / params["cpu_count"].to_i
    else
      attrs[:load_avg] = params["load_avg"].to_f
    end

    attrs[:ltsp_image] = params["ltsp_image"]

    @m.set(params["domain"], attrs)

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


  get "/v3/load_balance/:hostname" do

    device = search(
      "ou=Devices,ou=Hosts,#{ @organisation_info["base"] }",
      ["puavoSchool", "puavoDeviceImage" ],
      "(cn=#{ LdapModel.escape params["hostname"] })"
    )

    if device.nil?
      not_found "Unknown device #{ params["hostname"] }"
    end

    if device["puavoDeviceImage"]
      halt json device["puavoDeviceImage"].first
    end

    school = search(
      device["puavoSchool"].first,
      []
    )

    # if school["puavoDeviceImage"]
    #   halt json school["puavoDeviceImage"].first
    # end

    json ":(" => school

  end

end
end
