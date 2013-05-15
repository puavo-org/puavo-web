require "pstore"

module PuavoRest

class LoadBalanceModel

  def initialize(organisation)
    @store = PStore.new("/tmp/ltsp_server.#{ organisation }.pstore")
  end

  def update(domain, cpu_count, load_avg)
    @store.transaction do
      @store[domain] = {
        :domain => domain,
        :cpu_count => cpu_count,
        :load_avg => load_avg,
        :updated => Time.now
      }
    end
  end

  def relative_load(server)
    server[:load_avg] / server[:cpu_count]
  end

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
      relative_load(a) <=> relative_load(b)
    end
  end

end

# Load balancer resource for LTSP servers
class LtspServers < LdapSinatra

  auth Credentials::BasicAuth, :skip => :get

  before do
    @m = LoadBalanceModel.new @organisation
  end

  # Get list of LTSP servers sorted by they load. Most idle server is the first
  #
  # @!macro route
  get "/v3/:organisation/ltsp_servers" do
    json limit @m.all
  end

  # @!macro route
  get "/v3/:organisation/ltsp_servers/_most_idle.?:format?" do
    if params["format"] == "txt"
      json @m.most_idle.first
    else
      txt @m.most_idle.first[:domain]
    end
  end

  # Update LTSP server idle status
  #
  # @!macro route
  put "/v3/:organisation/ltsp_servers/:domain" do
    @m.update(
      params["domain"],
      params["cpu_count"].to_i,
      params["load_avg"].to_f
    )
    json "ok" => true
  end

end
end
