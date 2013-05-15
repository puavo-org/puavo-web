require "pstore"
require "fileutils"

module PuavoRest

# Pstore packed model for LTSP server data. Currently contains mainly load
# balancing data
class LtspServersModel

  def initialize(path)
    FileUtils.mkdir_p File.dirname(path)
    @store = PStore.new(path)
  end

  # set server load average for domain
  # @param [String] domain
  # @param [Float] load_avg
  def set(domain, load_avg)
    @store.transaction do
      @store[domain] = {
        :domain => domain,
        :load_avg => load_avg,
        :updated => Time.now
      }
    end
  end

  def get(domain)
    @store.transaction(true) do
      @store[domain]
    end
  end

  # Return all known ltsp servers
  def all
    a = []
    @store.transaction(true) do
      @store.roots.each do |k|
        a.push(@store[k])
      end
    end
    a
  end

  def most_idle
    all.sort do |a, b|
      a[:load_avg] <=> b[:load_avg]
    end.first
  end

end

# Load balancer resource for LTSP servers
class LtspServers < LdapSinatra

  auth Credentials::BasicAuth, :skip => :get

  before do
    @m = LtspServersModel.new File.join(
      CONFIG["ltsp_server_data_dir"],
      "ltsp_servers.#{ @organisation }.pstore"
    )
  end

  # Get list of LTSP servers sorted by they load. Most idle server is the first
  #
  # @!macro route
  get "/v3/:organisation/ltsp_servers" do
    json limit @m.all
  end

  # Computed resource for the most idle ltsp server
  #
  # @!macro route
  get "/v3/:organisation/ltsp_servers/_most_idle.?:format?" do
    if params["format"] == "txt"
      txt @m.most_idle[:domain]
    else
      json @m.most_idle
    end
  end

  get "/v3/:organisation/ltsp_servers/:domain" do
    json @m.get(params["domain"])
  end

  # set LTSP server idle status
  #
  # @!macro route
  put "/v3/:organisation/ltsp_servers/:domain" do
    if params["cpu_count"]
      load_avg = params["load_avg"].to_f / params["cpu_count"].to_i
    else
      load_avg = params["load_avg"].to_f
    end

    @m.set(params["domain"], load_avg)

    json "ok" => true
  end

end
end
