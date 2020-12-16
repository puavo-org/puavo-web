require "open3"

require_relative './external_login'

require_relative './integrations'

module Puavo
  def self.change_passwd(mode, host, actor_dn, actor_username, actor_password,
                         target_user_username, target_user_password, request_id)

    started = Time.now

    upstream_res = nil

    if mode != :no_upstream then
      upstream_res = change_passwd_upstream(
        host, actor_username,
        actor_password, target_user_username,
        target_user_password, request_id
      )

      upstream_res[:duration] = (Time.now.to_f - started.to_f).round(5)

      return upstream_res if mode == :upstream_only

      # Return if upstream password change failed.  This allows external
      # (upstream) password service to block password changes, for example
      # because password policy rejects the password or user does not have
      # sufficient permissions for the change operation.
      # Missing user can be normal, in that case we can still try to change
      # the Puavo-password (for users that exist in Puavo but not in external
      # login service).
      if upstream_res[:exit_status] != 0 then
        if (upstream_res[:extlogin_status] \
              != PuavoRest::ExternalLoginStatus::USERMISSING) then
          return upstream_res
        else
          upstream_res[:extlogin_status] \
            = PuavoRest::ExternalLoginStatus::NOCHANGE
        end
      end
    end

    begin
      if !actor_dn then
        actor_dn = PuavoRest::User.by_username!(actor_username).dn.to_s
      end

      res = change_passwd_no_upstream(
        host, actor_dn, actor_password,
        target_user_username, target_user_password,
        request_id
      )

      res[:extlogin_status] = upstream_res[:extlogin_status] if upstream_res
    rescue StandardError => e
      # We shouldn't get here very often, as change_passwd_no_upstream()
      # contains its own exception handlind in many places. So if we end
      # up here, something has gone really badly wrong.

      error_message  = "[#{request_id}] failed to change the Puavo password for user" \
                        + " '#{ target_user_username }'" \
                        + " by '#{ actor_dn || actor_username }': #{ e.message }"

      $rest_flog.error(error_message)

      res = {
        :exit_status     => 1,
        :stderr          => e.message,
        :stdout          => '',
        :sync_status     => 'unknown_error',
      }

      res[:extlogin_status] = upstream_res[:extlogin_status] if upstream_res
    end

    res[:duration] = (Time.now.to_f - started.to_f).round(5)

    return res
  end

  def self.change_passwd_no_upstream(host, actor_dn,
        actor_password, target_user_username, target_user_password,
        request_id)

    target_user = PuavoRest::User.by_username!(target_user_username)
    target_user_dn = target_user.dn.to_s

    # It would be nice if we could use 'ldappasswd -n' to check if we can
    # change password before doing downstream password change, and then
    # doing the downstream password change first, but unfortunately that
    # does not always work :-(

    res = LdapPassword.change_ldap_passwd(host, actor_dn, actor_password,
                                          target_user_dn, target_user_password)

    if res[:exit_status] != 0
      res[:sync_status] = 'unknown_error'   # what else do we have? :-(
      return res
    end

    # Administration schools are ALWAYS excluded from password synchronisations.
    # No exceptions.
    return res if target_user.school.name == 'Administration'

    # Synchronise the new password to other places
    org_name = LdapModel.organisation.organisation_key

    actions = Puavo::Integrations.get_school_sync_actions(
      org_name, target_user.school.id, :change_password)

    unless actions
      $rest_flog.info("[#{request_id}] Nothing configured for password synchronisation " \
                      "for school #{target_user.school.id} (\"#{target_user.school.name}\") in " \
                      "organisation \"#{org_name}\"")
      res[:sync_status] = 'ok'
      return res
    end

    $rest_flog.info(
      "[#{request_id}] School is #{target_user.school.id} (\"#{target_user.school.name}\") in " \
      "organisation \"#{org_name}\", synchronising the password change to these external systems: " \
      "#{actions.keys.join(', ')}"
    )

    # Send a HTTP request to every listed synchronisation service.
    # If they return an error, handle it and stop.
    index = 1

    user_roles = Array(target_user.roles || [])

    actions.each do |system, params|
      $rest_flog.info(
        "[#{request_id}] Synchronously changing the password for user " \
        "\"#{target_user.username}\" (#{target_user.id}) to the external system " \
        "\"#{system}\" (#{index}/#{actions.count})")

      index += 1

      # Optionally filter actions by user role
      if params.include?('for_roles')
        overlap = Array(params['for_roles']) & user_roles

        unless overlap.any?
          $rest_flog.info(
            "[#{request_id}] Role filtering is enabled for this action; wanted " \
            "\"#{params['for_roles']}\", got \"#{user_roles}\", skipping synchronisation")
          next
        end
      end

      begin
        status, code = Puavo::Integrations.do_synchronous_action(
          :change_password, system, request_id, params,
          # -----
          organisation: org_name,
          user: target_user,
          new_password: target_user_password,
        )

        unless status
          $rest_flog.warn("[#{request_id}] Aborting password synchronisation")

          return {
            :exit_status => 1,
            :stderr => '',
            :stdout => '',
            :sync_status => code,
          }
        end
      rescue StandardError => e
        $rest_flog.error("[#{request_id}] #{e}")

        begin
          # Try resetting password if we can in case downstream password change
          # failed.
          if actor_dn == target_user_dn
            LdapPassword.change_ldap_passwd(
              host, actor_dn, target_user_password,
              target_user_dn, actor_password
            )
          end
        rescue StandardError => e
          $rest_flog.error("[#{request_id}] Unable to restore the old password after a failed synchronisation: #{e}")
          # TODO: what now?
        end

        return {
          :exit_status => 1,
          :stderr => e.to_s,
          :stdout => '',
          :sync_status => 'unknown_error',
        }
      end
    end

    $rest_flog.info("[#{request_id}] All password synchronisations completed")
    res[:sync_status] = 'ok'

    return res
  end

  def self.change_passwd_upstream(host, actor_username, actor_password,
                                  target_user_username, target_user_password,
                                  request_id)
    begin
      external_login = PuavoRest::ExternalLogin.new
      login_service = external_login.new_external_service_handler()

      raise 'actor_username not set' \
        unless actor_username.kind_of?(String) && !actor_username.empty?
      login_service.change_password(actor_username,
                                    actor_password,
                                    target_user_username,
                                    target_user_password)
    rescue ExternalLoginNotConfigured => e
      # If external logins are not configured we should end up here,
      # and that is normal.
      full = "not changing upstream password, because external logins are not configured"
      $rest_flog.info("[#{request_id}] #{full}: #{e.message}")

      return {
        :exit_status     => 0,
        :extlogin_status => PuavoRest::ExternalLoginStatus::NOTCONFIGURED,
        :stderr          => '',
        :stdout          => full,
        :sync_status     => 'configuration_error',
      }

    rescue ExternalLoginUserMissing => e
      full = "not changing upstream password, target user '#{ target_user_username }' is missing " \
             "from the external service"
      $rest_flog.info("[#{request_id}] #{full}: #{e.message}")

      return {
        :exit_status     => 1,
        :extlogin_status => PuavoRest::ExternalLoginStatus::USERMISSING,
        :stderr          => full,
        :stdout          => '',
        :sync_status     => 'user_not_found',
      }

    rescue ExternalLoginWrongCredentials => e
      full = "login to upstream password change service failed for user " \
             "'#{ target_user_username }': #{e.message}"
      $rest_flog.error("[#{request_id}] #{full}")

      return {
        :exit_status     => 1,
        :extlogin_status => PuavoRest::ExternalLoginStatus::BADUSERCREDS,
        :stderr          => full,
        :stdout          => '',
        :sync_status     => 'bad_credentials',
      }

    rescue StandardError => e
      full = "changing upstream password failed for user '#{ target_user_username }': #{e.message}"
      $rest_flog.error("[#{request_id}] #{full}")

      return {
        :exit_status     => 1,
        :extlogin_status => PuavoRest::ExternalLoginStatus::UPDATEERROR,
        :stderr          => full,
        :stdout          => '',
        :sync_status     => 'unknown_error',
      }
    end

    $rest_flog.info("[#{request_id}] upstream password changed for user '#{ target_user_username }' " \
                    "by '#{ actor_username }'")

    return {
      :exit_status     => 0,
      :extlogin_status => PuavoRest::ExternalLoginStatus::UPDATED,
      :stderr          => '',
      :stdout          => 'password change to external login service ok',
      :sync_status     => 'ok',
    }
  end

  class LdapPassword
    def self.change_ldap_passwd(host, bind_dn, bind_dn_pw, user_dn, new_pw)
      cmd = [ 'ldappasswd',
              # use simple authentication instead of SASL
              '-x',
              # issue StartTLS (Transport Layer Security) extended operation
              '-Z',
              # specify an alternate host on which the ldap server is running
              '-h', host,
              # Distinguished Name used to bind to the LDAP directory
              '-D', bind_dn,
              # the password to bind with
              '-w', bind_dn_pw,
              # set the new password
              '-s', new_pw,
              # timeout after 20 sec
              '-o', 'nettimeout=20',
              # The user whose password we're changing
              user_dn.to_s ]

      stdout_str, stderr_str, status = Open3.capture3(*cmd)

      return {
        :exit_status => status.exitstatus,
        :stderr      => stderr_str,
        :stdout      => stdout_str,
        :sync_status => 'unknown_error',
      }
    end
  end
end
