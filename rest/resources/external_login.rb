require 'date'
require 'net/ldap'
require 'securerandom'

require_relative '../lib/external_login'

module PuavoRest
  class ExternalLogins < PuavoSinatra
    post '/v3/external_login/auth' do
      userinfo = nil
      user_status = nil

      begin
        raise ExternalLoginWrongCredentials, 'no basic auth used' \
          unless env['HTTP_AUTHORIZATION']

        auth_type, auth_data = env['HTTP_AUTHORIZATION'].split(' ', 2)
        raise ExternalLoginWrongCredentials, 'no basic auth used' \
          unless auth_type == 'Basic'

        username, password = Base64.decode64(auth_data).split(':')
        if !username || username.empty? then
          raise ExternalLoginWrongCredentials, 'no username provided'
        end
        if !password || password.empty? then
          raise ExternalLoginWrongCredentials, 'no password provided'
        end

        external_login = ExternalLogin.new
        external_login.setup_puavo_connection()
        external_login.check_user_is_manageable(username)

        login_service = external_login.new_external_service_handler()

        remove_user_if_found = false
        wrong_credentials    = false

        begin
          message = 'attempting external login to service' \
                      + " '#{ login_service.service_name }' by user" \
                      + " '#{ username }'"
          flog.info('external login attempt', message)
          userinfo = login_service.login(username, password)
        rescue ExternalLoginUserMissing => e
          flog.info('user does not exist in external ldap', e.message)
          remove_user_if_found = true
          userinfo = nil
        rescue ExternalLoginWrongCredentials => e
          flog.info('user provided wrong username/password', e.message)
          wrong_credentials = true
          userinfo = nil
        rescue ExternalLoginError => e
          raise e
        rescue StandardError => e
          # Unexpected errors when authenticating to external service means
          # it was not available.
          raise ExternalLoginUnavailable, e
        end

        if remove_user_if_found then
          # No user information in external login service, so remove user
          # from Puavo if there is one.  But instead of removing
          # we simply generate a new, random password, and mark the account
          # for removal, in case it was not marked before.  Not removing
          # right away should allow use to catch some possible accidents
          # in case the external ldap somehow "loses" some users, and we want
          # keep user uids stable on our side.
          user_to_remove = User.by_username(username)
          if user_to_remove && user_to_remove.mark_for_removal! then
            flog.info('puavo user marked for removal',
                      "puavo user '#{ user_to_remove.username }' is marked" \
                        + ' for removal')
          end
        end

        if wrong_credentials then
          # Try looking up user from Puavo, but in case a user does not exist
          # yet (there is a mismatch between username in Puavo and username
          # in external service), look up the user external_id from external
          # service so we can try to invalidate the password matching
          # the right Puavo username.
          user = User.by_username(username)
          external_id = (user && user.external_id) \
                          || login_service.lookup_external_id(username)

          # We must not force the user of admin_dn for this password change,
          # because this should happen only when password was valid for puavo
          # but not for external login, in which case we invalidate the puavo
          # password.
          new_password = SecureRandom.hex(128)
          pw_update_status = external_login.set_puavo_password(username,
                                                               external_id,
                                                               password,
                                                               new_password)
          if pw_update_status == ExternalLoginStatus::UPDATED then
            msg = 'user password invalidated'
            flog.info('user password invalidated',
                      "user password invalidated for #{ username }")
            return json(ExternalLogin.status_updated_but_fail(msg))
          end
        end

        if !userinfo then
          msg = 'could not login to external service' \
                  + " '#{ login_service.service_name }' by user" \
                  + " '#{ username }', username or password was wrong"
          flog.info('could not login to external service', msg)
          raise ExternalLoginWrongCredentials, msg
        end

        # update user information after successful login

        message = 'successful login to external service' \
                    + " by user '#{ userinfo['username'] }'"
        flog.info('external login successful', message)

        begin
          extlogin_status = external_login.update_user_info(userinfo,
                                                            password,
                                                            params)
          user_status \
            = case extlogin_status
                when ExternalLoginStatus::NOCHANGE
                  ExternalLogin.status_nochange()
                when ExternalLoginStatus::UPDATED
                  ExternalLogin.status_updated()
                else
                  raise 'unexpected update status from update_user_info()'
              end
        rescue StandardError => e
          flog.warn('error updating user information',
                    "error updating user information: #{ e.message }")
          return json(ExternalLogin.status_updateerror(e.message))
        end

      rescue BadCredentials => e
        # this means there was a problem with Puavo credentials (admin dn)
        user_status = ExternalLogin.status_configerror(e.message)
      rescue ExternalLoginConfigError => e
        flog.info('external login configuration error',
                  "external login configuration error: #{ e.message }")
        user_status = ExternalLogin.status_configerror(e.message)
      rescue ExternalLoginNotConfigured => e
        flog.info('external login not configured',
                  "external login is not configured: #{ e.message }")
        user_status = ExternalLogin.status_notconfigured(e.message)
      rescue ExternalLoginUnavailable => e
        flog.warn('external login unavailable',
                  "external login is unavailable: #{ e.message }")
        user_status = ExternalLogin.status_unavailable(e.message)
      rescue ExternalLoginWrongCredentials => e
        user_status = ExternalLogin.status_badusercreds(e.message)
      rescue StandardError => e
        raise InternalError, e
      end

      json_user_status = json(user_status)
      flog.info(nil, "returning external login status #{ json_user_status }")
      return json_user_status
    end

    post '/v3/external_login/check_and_update_users' do
      auth :basic_auth

      begin
        external_login = ExternalLogin.new
        login_service = external_login.new_external_service_handler()

        external_users = nil
        begin
          external_users = login_service.lookup_all_users()
        rescue StandardError => e
          errmsg = 'error looking up all users from external login service'
          flog.warn(errmsg, "#{ errmsg }: #{ e.message }")
          return json({ :error => errmsg, :status => 'failed' })
        end

        all_ok = true

        User.all.each do |puavo_user|
          begin
            external_id = puavo_user.external_id
            next unless external_id
            next if external_users.has_key?(external_id)

            # User not found in external service, so it must be in Puavo
            # and we mark it for removal.
            if puavo_user.mark_for_removal! then
              flog.info('puavo user marked for removal',
                        "puavo user '#{ puavo_user.username }' is marked" \
                          + ' for removal')
            end

          rescue StandardError => e
            flog.warn('error in marking user for removal',
                      "error in marking user '#{ puavo_user.username }'" \
                         + " for removal: #{ e.message }")
            all_ok = false
          end
        end

        external_users.each do |external_id, userinfo|
          begin
            username   = userinfo['username']
            ldap_entry = userinfo['ldap_entry']

            login_service.set_ldapuserinfo(username, ldap_entry)
            userinfo = login_service.get_userinfo(username)
            user_status = external_login.update_user_info(userinfo, nil, {})

            if user_status != ExternalLoginStatus::NOCHANGE \
              && user_status != ExternalLoginStatus::UPDATED then
                errmsg = 'user information update to Puavo failed for' \
                           + " #{ username }" \
                           + " (#{ external_id })"
                raise errmsg
            end

          rescue StandardError => e
            flog.warn('error checking user in external login service',
                      "error checking user '#{ username }'" \
                        + " in external login service: #{ e.message }")
            all_ok = false
          end
        end

        unless all_ok then
          raise 'could not check and update one or more users' \
                  + '  from external login service'
        end

      rescue StandardError => e
        errmsg = 'error in updating users from external login service'
        flog.warn(errmsg, "#{ errmsg }: #{ e.message }")
        return json({ :error => errmsg, :status => 'failed' })
      end

      return json({ :status => 'successfully' })
    end

    post '/v3/external_login/remove_users_marked_for_removal' do
      auth :basic_auth

      external_login = ExternalLogin.new
      begin
        remove_after_n_days \
          = Integer(external_login.config['days_after_removing_marked_users'])
      rescue StandardError => e
        errmsg = 'external_login/days_after_removing_marked_users' \
                   + ' is not configured in puavo-rest configuration'
        return json({ :error => errmsg, :status => 'failed' })
      end

      now = Time.now.utc.to_datetime

      puavo_users_to_be_deleted \
        = User.all.select do |user|
            user.external_id \
              && user.removal_request_time \
              && (now > (user.removal_request_time + remove_after_n_days))
          end

      all_ok = true

      puavo_users_to_be_deleted.each do |puavo_user|
        begin
          flog.info('removing puavo user because it was marked for removal',
                    "removing puavo user '#{ puavo_user.username }' because" \
                      + ' it was marked for removal')
          puavo_user.destroy!
        rescue StandardError => e
          flog.warn('failed to remove puavo user that was marked for removal',
                    "failed to remove puavo user '#{ puavo_user.username }'" \
                      + " that was marked for removal: #{ e.message }")
          all_ok = false
        end
      end

      unless all_ok then
        return json({ :error  => 'could not remove some users',
                      :status => 'failed' })
      end

      return json({ :status => 'successfully' })
    end
  end
end
