require "uuid"
require_relative "../pstore_model"

module PuavoRest

class SessionsModel < PstoreModel

  def generate_uuid
    UUID.generator.generate
  end

  def initialize(path, ltsp_servers)
    @ltsp_servers = ltsp_servers
    super(path)
  end

  def self.from_domain(organisation_domain)
    lsm = LtspServersModel.from_domain organisation_domain
    super organisation_domain, lsm
  end

  def create_session(attrs={})
    uuid = generate_uuid
    session = {
      :uuid => uuid,
      :created => Time.now
    }.merge(attrs)

    session[:ltsp_server] ||= @ltsp_servers.most_idle(attrs[:image]).first

    set uuid, session
  end


end


# Desktop login sessions
class Sessions < LdapSinatra

  auth Credentials::BootServer

  before do
    @sessions = SessionsModel.from_domain @organisation_info["domain"]
  end

  # Create new desktop session
  #
  # @param hostname
  # @param username
  post "/v3/sessions" do
    session = nil
    hostname = params["hostname"]
    if hostname.nil?
      halt 400, json("error" => "'hostname' missing")
    end

    device = new_model(DevicesModel).by_hostname(hostname)
    if device.nil?
      halt 400, json("error" => "Unknown device #{ hostname }")
    end

    [
      lambda { device },
      lambda { new_model(SchoolsModel).by_dn(device["school_dn"]) },
      lambda { new_model(Organisations).by_dn(@organisation_info["base"]) }
    ].each do |block|
      model = block.call
      next if model["image"].nil?
      session = @sessions.create_session(
        :hostname => hostname,
        :image => model["image"]
      )
    end

    json session || @sessions.create_session(:hostname => hostname)
  end

  get "/v3/sessions" do
    json @sessions.all
  end

  get "/v3/sessions/:uuid" do
    if s = @sessions.get(params["uuid"])
      json s
    else
      halt 404, json(:error => "unknown session uid #{ params["uuid"] }")
    end
  end

  delete "/v3/sessions/:uuid" do
    @sessions.delete params["uuid"]
    json :ok => true
  end

end
end
