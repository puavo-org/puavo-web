require "pstore"

module PuavoRest

class LoadBalanceModel

  def initialize
    @store = PStore.new("/tmp/ltsp_server_loads.pstore")
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

  def most_idle
    current = nil
    @store.transaction(true) do
      @store.roots.each do |k|
        server = @store[k]
        if not current
          current = server
        elsif relative_load(current) > relative_load(server)
          current = server
        end
      end
    end
    current
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

end

# Load balancer resource for LTSP servers
class LtspServers < LdapSinatra

  auth Credentials::BasicAuth, :skip => :get

  before do
    @m = LoadBalanceModel.new
  end

  # Get list of LTSP servers with their load averages
  #
  # @!macro route
  get "/v3/:organisation/ltsp_servers" do
    json @m.all
  end

  # Get the most idle LTSP server
  #
  # @!macro route
  get "/v3/:organisation/ltsp_servers/most_idle" do
    json @m.most_idle
  end

  # Update LTSP server idle status
  #
  # @!macro route
  post "/v3/:organisation/ltsp_servers/most_idle" do
    @m.update(
      params["domain"],
      params["cpu_count"].to_i,
      params["load_avg"].to_f
    )
    json "ok" => true
  end

end
end
