require "uuid"
require_relative "../lib/local_store"

module PuavoRest

class Session < Hash
  include LocalStore

  # Clear sessions after after 12 hours if they are not manually cleared during
  # logout. Ie. on crash
  MAX_AGE = 60 * 60 * 12

  UUID_CHARS = [*'a'..'z', *'A'..'Z', *'0'..'9'].freeze

  def self.generate_uuid
    UUID_CHARS.sample(50).join
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
class Sessions < PuavoSinatra

  # @api {post} /v3/sessions
  # @apiName Create new desktop session
  # @apiGroup sessions
  post "/v3/sessions" do
    if (json_params['authoritative'] != 'true') || CONFIG['cloud'] then
      # If client has not requested authoritative answer, we may proceed as
      # usual.  In case we are a cloud server, we are authoritative without
      # any tricks anyway, so we may proceed as usual.
      auth :basic_auth, :server_auth, :kerberos
    elsif CONFIG['bootserver'] then
      # Client has requested an authoritative answer, but we are a bootserver,
      # with some delay before the local ldap has synchronized latest changes.
      # We drop our current connection and setup a new one against the ldap
      # master, so we can be authoritative.
      if !CONFIG['ldapmaster'] then
        raise InternalError,
              :user => 'Requested authoritative answer but ldapmaster not known'
      end

      msg = 'authoritative session requested,' \
              + ' setting up ldap connection to ldapmaster'
      rlog.info(msg)
      LdapModel.disconnect()
      auth :basic_auth, :server_auth, :kerberos
      LdapModel.setup(:ldap_server => CONFIG['ldapmaster'])
    else
      raise InternalError,
            :user => 'Not a bootserver or cloud instance, what are we?'
    end

    session = Session.new
    session.merge!(
      "uuid" => Session.generate_uuid,
      "created" => Time.now.to_i,
      "printer_queues" => []
    )

    if json_params["hostname"]
      # Normal user has no permission to read device attributes so force server
      # credentials here.
      credentials = CONFIG["server"]

      # Use credentials by device if it is defined (laptop).
      if json_params["device_dn"] && json_params["device_password"]
        credentials = {
          :dn => json_params["device_dn"],
          :password => json_params["device_password"]
        }
      end

      LdapModel.setup(:credentials => credentials) do
        device = Device.by_hostname!(json_params["hostname"])

        session["preferred_language"] = device.preferred_language
        session["locale"] = device.locale

        session["device"] = device.to_hash
        session["printer_queues"] += device.printer_queues
        session["printer_queues"] += device.school.printer_queues
        session["printer_queues"] += device.school.wireless_printer_queues
        session
      end
    end

    if User.current && !User.current.server_user?
      user = User.current

      session['user'] = {
        # Generic useful information (mostly for puavo-login)
        'username' => user.username,
        'first_name' => user.first_name,
        'last_name' => user.last_name,
        'user_type' => user.user_type,
        'gid_number' => user.gid_number,
        'uid_number' => user.uid_number,

        # check-if-account-is-locked
        'locked' => user.locked,

        # 41puavo-set-locale
        'locale' => user.locale,
        'preferred_language' => user.preferred_language,

        # 42puavo-set-browser-homepage
        'homepage' => user.homepage,

        # puavo-handle-user-password-expiration
        'password_last_set' => user.password_last_set,

        # various bits and pieces of info that isn't currently required,
        # but that can be useful
        'id' => user.id.to_i,
        'profile_image_link' => user.profile_image_link,
        'edu_person_principal_name' => user.edu_person_principal_name,
        'primary_school_id' => user.school.id.to_i,
      }

      # puavo-login needs groups and their GID numbers. Convert schools into groups,
      # because from our system's POV a school *is* a group.
      raw_groups = user.schools

      raw_groups += user.groups

      groups = []

      # This works because schools and groups have the same members. And Ruby does not care
      # if an array contains different types of objects.
      raw_groups.each do |group|
        groups << {
          'id' => group.id.to_i,                            # currently unused
          'name' => group.name,                             # currently unused
          'abbreviation' => group.abbreviation,
          'gid_number' => group.gid_number,
          'printer_queue_dns' => group.printer_queue_dns,   # currently unused?
        }
      end

      session['user']['groups'] = groups

      # Needed by 41puavo-set-locale
      session["preferred_language"] = user.preferred_language
      session["locale"] = user.locale

      # Needed by 90puavo-setup-printers
      user.groups.each do |group|
        session["printer_queues"] += group.printer_queues
      end
    end

    rlog.info("created new session #{ session["uuid"] }")
    session["printer_queues"].uniq!{ |pq| pq.dn }
    session["organisation"] = Organisation.current.domain
    session.save

    json session
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
