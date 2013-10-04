require "uuid"
require_relative "../local_store"
require_relative "../lib/error_codes"

module PuavoRest

class Session < Hash
  include LocalStore

  # Clear sessions after after 12 hours if they are not manually cleared during
  # logout. Ie. on crash
  MAX_AGE = 60 * 60 * 12

  UUID_CHARS = ["a".."z", "A".."Z", "0".."9"].reduce([]) do |memo, range|
    memo + range.to_a
  end

  def self.generate_uuid
    (0...50).map{ UUID_CHARS[rand(UUID_CHARS.size)] }.join
  end


  def session_key
    "session:#{ self["device"]["hostname"] }"
  end

  def self.session_key(hostname)
    "session:#{ hostname }"
  end

  def save
    local_store.set(session_key, self.to_json)
    local_store.expire(session_key, MAX_AGE)
  end

  def destroy
    local_store.del(session_key)
  end

  def self.load(hostname)
    json = local_store.get(session_key hostname)
    if json.nil?
      raise NotFound, :user => "Cannot find session"
    end
    new.merge JSON.parse(json)
  end

  def self.keys
    local_store.keys("session:*")
  end

  def self.all
    keys.map do |k|
      new.merge! JSON.parse(local_store.get(k))
    end
  end

end

# Desktop login sessions
class Sessions < LdapSinatra

  def find_ltsp_server(preferred_image, preferred_server, school_dn)

    filtered = ServerFilter.new(LtspServer.all_with_state)
    filtered.filter_old
    filtered.safe_apply(:filter_by_image, preferred_image) if preferred_image
    filtered.safe_apply(:filter_by_server, preferred_server)
    filtered.safe_apply(:filter_by_other_schools, school_dn)
    filtered.safe_apply(:filter_by_school, school_dn)
    filtered.sort_by_load

    if filtered.first.nil?
      raise NotFound, :user => "cannot find any LTSP servers"
    end

    filtered.first
  end


  # Create new desktop session for a thin client. If the thin client requests
  # some specific LTSP image and no server provides it will get the most idle
  # LTSP server with what ever image it has
  post "/v3/sessions" do
    auth :basic_auth, :server_auth, :kerberos

    if params["hostname"].nil?
      logger.warn "'hostname' missing"
      halt 400, json("error" => "'hostname' missing")
    end

    session = Session.new
    session.merge!(
      "uuid" => Session.generate_uuid,
      "created" => Time.now.to_i,
      "printer_queues" => []
    )

    if User.current
      session["user"] = User.current.to_hash
      Group.by_user_dn(User.current.dn).each do |group|
        session["printer_queues"] += group.printer_queues
      end
    end

    # Normal user has no permission to read device attributes so force server
    # credentials here.
    json(LdapHash.setup(:credentials => CONFIG["server"]) do
      device = Device.by_hostname(params["hostname"])

      logger.info "Thin #{ params["hostname"] } " +
        "from school #{ device["school"].inspect } " +
        "prefering image #{ device.preferred_image } " +
        "and server #{ device["preferred_server"].inspect } " +
        "is requesting a desktop session"

      session["ltsp_server"] = find_ltsp_server(
        device.preferred_image,
        device.preferred_server,
        device.school_dn
      )

      session["device"] = device.to_hash
      session["printer_queues"] += device.printer_queues
      session["printer_queues"] += device.school.printer_queues
      session["printer_queues"] += device.school.wireless_printer_queues

      session.save

      logger.info "Created session #{ session["uuid"] } " +
        "to ltsp server #{ session["ltsp_server"]["hostname"] } " +
        "for #{ params["hostname"] }"

      session
    end)
  end


  # Return all sessions
  #
  # @!macro route
  get "/v3/sessions" do
    auth :server_auth, :legacy_server_auth

    session_hostnames = Session.keys.map do |key|
      key.split(":")[1]
    end

    json limit session_hostnames
  end


  def assert_uuid(session)
    if params["uuid"].nil?
      raise BadInput, :user => "uuid query string is missing"
    end

    if session["uuid"] != params["uuid"]
      raise BadInput, :user => "uuid does not match"
    end
  end

  # Get session by uid
  #
  # @!macro route
  get "/v3/sessions/:hostname" do
    auth :server_auth, :legacy_server_auth
    session = Session.load(params["hostname"])
    assert_uuid session
    json session
  end

  # Delete session
  #
  # @!macro route
  delete "/v3/sessions/:hostname" do
    session = Session.load(params["hostname"])
    assert_uuid session
    session.destroy
    json :ok => true
  end

end
end
