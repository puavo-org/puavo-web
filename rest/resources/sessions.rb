module PuavoRest

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

    session = {
      "created" => Time.now.to_i,
      "printer_queues" => []
    }

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

    session["printer_queues"].uniq!{ |pq| pq.dn }
    session["organisation"] = Organisation.current.domain

    json session
  end
end
end
