require "uuid"
require_relative "../local_store"
require_relative "../lib/error_codes"

module PuavoRest

class Session < LdapHash
  include LocalStoreMixin

  # Create new desktop session for a device
  #
  # @param device_attrs [Hash]
  def self.create(device_attrs={})
    session = new.merge!(
      "uuid" => UUID.generator.generate,
      "created" => Time.now,
      "client" => device_attrs
    )

    filtered = ServerFilter.new(LtspServer.all_with_state)
    filtered.filter_old
    filtered.safe_apply(:filter_by_image, device_attrs["preferred_image"]) if device_attrs["preferred_image"]
    filtered.safe_apply(:filter_by_server, device_attrs["preferred_server"])
    filtered.safe_apply(:filter_by_other_schools, device_attrs["school"])
    filtered.safe_apply(:filter_by_school, device_attrs["school"])
    filtered.sort_by_load

    session["ltsp_server"] = filtered.first

    if session["ltsp_server"].nil?
      raise NotFound, :user => "cannot find any LTSP servers"
    end
    session
  end

  def save
    self.class.store.set self["uuid"], self
  end

  def destroy
    self.class.store.delete self["uuid"]
  end

  def self.load(uuid)
    session = store.get(uuid)
    if session.nil?
      raise NotFound, "unknown session uuid '#{ uuid }'"
    end
    session
  end

  def self.all
    store.all
  end

end

# Desktop login sessions
class Sessions < LdapSinatra

  # Create new desktop session for a thin client. If the thin client requests
  # some specific LTSP image and no server provides it will get the most idle
  # LTSP server with what ever image it has
  #
  # @!macro route
  post "/v3/sessions" do
    auth :basic_auth, :server_auth, :kerberos

    if params["hostname"].nil?
      logger.warn "'hostname' missing"
      halt 400, json("error" => "'hostname' missing")
    end

    # Normal user has no permission to read device attributes so force server
    # credentials here.
    session = LdapHash.setup(:credentials => CONFIG["server"]) do
      device = Device.by_hostname(params["hostname"])
      device.fallback_defaults

      logger.info "Thin #{ params["hostname"] } " +
        "from school #{ device["school"].inspect } " +
        "prefering image #{ device["image"] } " +
        "and server #{ device["preferred_server"].inspect } " +
        "is requesting a desktop session"

      session = Session.create(
        "hostname" => params["hostname"],
        "school" => device["school"],
        "preferred_image" => device["image"],
        "preferred_server" => device["preferred_server"]
      )

      session["printer_queues"] = device.printer_queues
      session["printer_queues"] += device.school.printer_queues
      session["printer_queues"] += device.school.wireless_printer_queues
      session
    end

    if User.current
      Group.by_user_dn(User.current["dn"]).each do |group|
        session["printer_queues"] += group.printer_queues
      end
    end

    session.save

    logger.info "Created session #{ session["uuid"] } " +
      "to ltsp server #{ session["ltsp_server"]["hostname"] } " +
      "for #{ params["hostname"] }"
    json session
  end

  # Return all sessions
  #
  # @!macro route
  get "/v3/sessions" do
    auth :server_auth, :legacy_server_auth

    json limit Session.all
  end

  # Get session by uid
  #
  # @!macro route
  get "/v3/sessions/:uuid" do
    auth :server_auth, :legacy_server_auth

    json Session.load(params["uuid"])
  end

  # Delete session
  #
  # @!macro route
  delete "/v3/sessions/:uuid" do

    Session.load(params["uuid"]).destroy
    json :ok => true
  end

end
end
