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


  def hostname_key
    self.class.hostname_key("#{ self["device"]["hostname"] }")
  end
  def self.hostname_key(hostname)
    "session:hostname:#{ hostname }"
  end

  def self.uuid_key(uuid)
    "session:uuid:#{ uuid }"
  end
  def uuid_key
    self.class.uuid_key("#{ self["uuid"] }")
  end

  def device?
    !self["device"].nil?
  end

  def save
    local_store.set(uuid_key, self.to_json)
    local_store.expire(uuid_key, MAX_AGE)

    if device?
      local_store.set(hostname_key, self["uuid"])
      local_store.expire(hostname_key, MAX_AGE)
    end
  end

  def destroy
    local_store.del(uuid_key)
    local_store.del(hostname_key) if device?
  end

  def self.by_hostname!(hostname)
    uuid = local_store.get(hostname_key(hostname))
    if uuid.nil?
      raise NotFound, :user => "Cannot find session for hostname: #{ hostname }"
    end
    by_uuid!(uuid)
  end

  def self.by_uuid!(uuid)
    json = local_store.get(uuid_key(uuid))
    if json.nil?
      raise NotFound, :user => "Cannot find session for uuid: #{ uuid }"
    end
    new.merge(JSON.parse(json))
  end

  def self.keys
    local_store.keys("session:hostname:*")
  end

  def self.all
    keys.map do |k|
      new.merge! JSON.parse(local_store.get(k))
    end
  end

end

# Desktop login sessions
class Sessions < LdapSinatra

  def find_ltsp_server!(preferred_image, preferred_server, school_dn)

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

    session = Session.new
    session.merge!(
      "uuid" => Session.generate_uuid,
      "created" => Time.now.to_i,
      "printer_queues" => []
    )

    if User.current
      user = User.current
      session["user"] = user.to_hash
      groups = user.groups
      session["user"]["groups"] = groups

      groups.each do |group|
        session["printer_queues"] += group.printer_queues
      end
    end

    if params["hostname"]
      # Normal user has no permission to read device attributes so force server
      # credentials here.
      LdapModel.setup(:credentials => CONFIG["server"]) do
        inject_device_info(params["hostname"], session)
      end
    end

    logger.info "Created session #{ session["uuid"] }"
    session["printer_queues"].uniq!{ |pq| pq.dn.downcase }
    session["organisation"] = Organisation.current.domain
    session.save

    flog.info "new session", :device => params["hostname"]
    json session
  end

  def inject_device_info(hostname, session)
    device = Device.by_hostname!(hostname)

    if device.type == "thinclient"
      session["ltsp_server"] = find_ltsp_server!(
        device.preferred_image,
        device.preferred_server,
        device.school_dn
      )
    end

    session["device"] = device.to_hash
    session["printer_queues"] += device.printer_queues
    session["printer_queues"] += device.school.printer_queues
    session["printer_queues"] += device.school.wireless_printer_queues
    session
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

  get "/v3/sessions/:uuid" do
    auth :server_auth
    session = Session.by_uuid!(params["uuid"])
    json session
  end

  # Delete session by hostname and uuid
  #
  # @!macro route
  delete "/v3/sessions/:uuid" do
    session = Session.by_uuid!(params["uuid"])
    session.destroy
    json :ok => true
  end

  # Delete session by uuid
  #
  # @!macro route
  delete "/v3/sessions/:uuid" do
    session = Session.by_uuid!(params["uuid"])
    session.destroy
    json :ok => true
  end

end
end
