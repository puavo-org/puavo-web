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
        raise BadCredentials, :user => 'provide user/password with basic auth' \
          unless env['HTTP_AUTHORIZATION']

        auth_type, auth_data = env['HTTP_AUTHORIZATION'].split(' ', 2)
        raise BadCredentials, :user => 'provide user/password with basic auth' \
          unless auth_type == 'Basic'

        username, password = Base64.decode64(auth_data).split(':')
        if username.empty? then
          raise BadCredentials, :user => 'no username provided'
        end
        if password.empty? then
          raise BadCredentials, :user => 'no password provided'
        end

        external_login = ExternalLogin.new
        external_login.setup_puavo_connection()
        external_login.check_user_is_manageable(username)

        login_service = external_login.new_external_service_handler()

        wrong_password = false
        begin
          message = 'attempting external login to service' \
                      + " '#{ login_service.service_name }' by user" \
                      + " '#{ username }'"
          flog.info('external login attempt', message)
          userinfo = login_service.login(username, password)
        rescue ExternalLoginUserMissing => e
          flog.info('user does not exist in external ldap', e.message)
          userinfo = nil
        rescue ExternalLoginWrongPassword => e
          flog.info('user provided wrong password', e.message)
          userinfo = nil
          wrong_password = true
        rescue ExternalLoginError => e
          raise e
        rescue StandardError => e
          # Unexpected errors when authenticating to external service means
          # it was not available.
          raise ExternalLoginUnavailable, e
        end

        if wrong_password then
          external_id = login_service.lookup_external_id(username)
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
        elsif !userinfo then
          # No user information, but password was not wrong, therefore
          # user information is missing from external login service
          # and user must be removed from Puavo.  But instead of removing
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

        if !userinfo then
          msg = 'could not login to external service' \
                  + " '#{ login_service.service_name }' by user" \
                  + " '#{ username }', username or password was wrong"
          flog.info('could not login to external service', msg)
          return json(ExternalLogin.status_badusercreds(msg))
        end

        # update user information after successful login

        message = 'successful login to external service' \
                    + " by user '#{ userinfo['username'] }'"
        flog.info('external login successful', message)

        begin
          user_status \
            = external_login.update_user_info(userinfo, password, params)
        rescue StandardError => e
          flog.warn('error updating user information',
                    "error updating user information: #{ e.message }")
          return json(ExternalLogin.status_updateerror(e.message))
        end

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
      rescue StandardError => e
        raise InternalError, e
      end

      json_user_status = json(user_status)
      flog.info(nil, "returning external login status #{ json_user_status }")
      return json_user_status
    end

    post '/v3/external_login/mark_removed_users' do
      auth :basic_auth

      all_ok = true

      external_login = ExternalLogin.new
      login_service = external_login.new_external_service_handler()

      puavo_users_with_external_ids = User.all.select { |u| u.external_id }

      puavo_users_with_external_ids.each do |puavo_user|
        begin
          if login_service.user_exists?(puavo_user.external_id) then
            if puavo_user.removal_request_time then
              puavo_user.removal_request_time = nil
              puavo_user.save!
              flog.info('mark-for-removal removed for puavo user',
                        'mark-for-removal removed for puavo user' \
                          + " '#{ puavo_user.username }'")

            end
            next
          end
        rescue StandardError => e
          flog.warn('error checking if user exists in external login service',
                    "error checking if user '#{ puavo_user.username }'" \
                      + ' exists in external login service:' \
                      + " #{ e.message }")
          all_ok = false
          next
        end

        if puavo_user.mark_for_removal! then
          flog.info('puavo user marked for removal',
                    "puavo user '#{ puavo_user.username }' is marked" \
                      + ' for removal')
        end
      end

      unless all_ok then
        errmsg = 'could not check some users from external login service'
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
