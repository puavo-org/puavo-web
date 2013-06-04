require "uuid"
require_relative "../pstore_model"

module PuavoRest

class SessionsModel < LdapModel

  class CannotFindLtspServer < ModelError
    def code
      500
    end
  end

  attr_accessor :store

  def initialize(ldap_conn, organisation_info)
    @ltsp_servers = LtspServersModel.new(ldap_conn, organisation_info)
    @store = LocalStore.from_domain organisation_info["domain"] + self.class.name
  end

  def generate_uuid
    UUID.generator.generate
  end

  def self.from_domain(organisation_domain)
    lsm = LtspServersModel.from_domain organisation_domain
    super organisation_domain, lsm
  end

  # Create new desktop session
  #
  # @param attrs [Hash]
  def create_session(attrs={})
    uuid = generate_uuid
    session = {
      "uuid" => uuid,
      "created" => Time.now
    }.merge(attrs)

    servers = ServerFilter.new(@ltsp_servers.all)
    servers.filter_old
    servers.safe_apply(:filter_by_image, attrs["image"]) if attrs["image"]
    servers.safe_apply(:filter_by_server, attrs["preferred_server"])
    servers.safe_apply(:filter_by_school, attrs["school"])
    servers.safe_apply(:filter_by_forced_schools, attrs["school"])
    servers.sort_by_load

    session["ltsp_server"] = servers.first
    raise CannotFindLtspServer if session["ltsp_server"].nil?
    @store.set uuid, session
  end

end


# Desktop login sessions
class Sessions < LdapSinatra

  auth Credentials::BootServer

  before do
    @sessions = new_model(SessionsModel)
  end

  # Create new desktop session for a thin client. If the thin client requests
  # some specific LTSP image and no server provides it will get the most idle
  # LTSP server with what ever image it has
  #
  # @param hostname Thin client hostname requesting a desktop session
  post "/v3/sessions" do

    if params["hostname"].nil?
      logger.warn "'hostname' missing"
      halt 400, json("error" => "'hostname' missing")
    end

    device = new_model(DevicesModel).by_hostname(params["hostname"])

    # Find out whether the thin client prefers a specific ltsp image
    image = [
      lambda { device },
      lambda { new_model(SchoolsModel).by_dn(device["school"]) },
      lambda { new_model(Organisations).by_dn(@organisation_info["base"]) }
    ].reduce(nil) do |image, block|
      if image.nil?
        model = block.call
        image = model["image"] if model
      end
      image
    end

    json @sessions.create_session(
      "image" => image,
      "hostname" => params["hostname"],
      "preferred_server" => device[:preferred_server],
      "school" => device["school"]
    )
  end

  get "/v3/sessions" do
    json @sessions.store.all
  end

  get "/v3/sessions/:uuid" do
    if s = @sessions.store.get(params["uuid"])
      json s
    else
      halt 404, json(:error => "unknown session uid #{ params["uuid"] }")
    end
  end

  delete "/v3/sessions/:uuid" do
    @sessions.store.delete params["uuid"]
    json :ok => true
  end

end
end
