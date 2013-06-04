require "uuid"
require_relative "../pstore_model"

module PuavoRest

class SessionsModel < LdapModel

  class CannotFindLtspServer < Exception; end

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

  # Create new desktop session
  #
  # @param attrs [Hash]
  # @option attrs [String] :image
  def create_session(attrs={})
    uuid = generate_uuid
    session = {
      :uuid => uuid,
      :created => Time.now
    }.merge(attrs)

    session[:ltsp_server] ||= @ltsp_servers.most_idle(attrs[:image]).first
    raise CannotFindLtspServer if session[:ltsp_server].nil?
    set uuid, session
  end


end


# Desktop login sessions
class Sessions < LdapSinatra

  auth Credentials::BootServer

  before do
    @sessions = SessionsModel.from_domain @organisation_info["domain"]
  end

  # Create new desktop session for a thin client. If the thin client requests
  # some specific LTSP image and no server provides it will get the most idle
  # LTSP server with what ever image it has
  #
  # @param hostname Thin client hostname requesting a desktop session
  post "/v3/sessions" do
    session = nil

    if params["hostname"].nil?
      logger.warn "'hostname' missing"
      halt 400, json("error" => "'hostname' missing")
    end

    device = new_model(DevicesModel).by_hostname(params["hostname"])
    if device.nil?
      logger.warn "Unknown device hostname '#{ params["hostname"] }' requested session"
      halt 400, json("error" => "Unknown device #{ params["hostname"] }")
    end

    # Find out whether the thin client requires a specific ltsp image
    image = [
      lambda { device },
      lambda { new_model(SchoolsModel).by_dn(device["school_dn"]) },
      lambda { new_model(Organisations).by_dn(@organisation_info["base"]) }
    ].reduce(nil) do |image, block|
      if image.nil?
        model = block.call
        image = model["image"] if model
      end
      image
    end

    session_attrs = {
      :hostname => params["hostname"],
      :username => params["username"]
    }

    # Try to find ltsp server this this image
    if image
      logger.info "'#{ params["hostname"] }' requests image '#{ image }'"
      begin
        session = @sessions.create_session(
          session_attrs.merge(:image => image)
        )
      rescue SessionsModel::CannotFindLtspServer
        logger.warn "Cannot find ltsp server for image: #{ image }"
      end
    end

    if not session
      # If not found fallback to any available ltsp server with least amount of
      # load
      begin
        session = @sessions.create_session(session_attrs)
      rescue SessionsModel::CannotFindLtspServer
        logger.fatal "Failed to create session for '#{ params["hostname"] }'"
        halt 400, json(:error => "I have no LTSP servers for you :(")
      end
    end

    logger.info "Session #{ session[:uuid] } created on '#{ session[:ltsp_server][:hostname] }' for device '#{ params["hostname"] }'"
    json session
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
