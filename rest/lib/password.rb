require "open3"

require_relative './external_login'

module Puavo
  def self.change_passwd(host, actor_username, actor_password,
                         target_user_username, target_user_password,
                         external_pw_mgmt_url=nil)
    started = Time.now

    res = change_passwd_upstream(host, actor_username, actor_password,
                                 target_user_username, target_user_password)
    res[:duration] = (Time.now.to_f - started.to_f).round(5)

    # Return if upstream password change failed.  This allows external
    # (upstream) password service to block password changes, for example
    # because password policy rejects the password or user does not have
    # sufficient permissions for the change operation.
    return res unless res[:exit_status] == 0

    begin
      actor_dn = PuavoRest::User.by_username!(actor_username).dn.to_s
      no_upstream_res = change_passwd_no_upstream(host, actor_dn,
                          actor_password, target_user_username,
                          target_user_password, external_pw_mgmt_url)
      res = no_upstream_res.merge({ :extlogin_status => res[:extlogin_status] })

    rescue StandardError => e
      short_errmsg = 'failed to change the Puavo password'
      long_errmsg  = 'failed to change the Puavo password for user' \
                       + " '#{ target_user_username }'" \
                       + " by '#{ actor_username }': #{ e.message }"
      $rest_flog.error(short_errmsg, long_errmsg)
      res = {
        :exit_status     => 1,
        :extlogin_status => res[:extlogin_status],
        :stderr          => e.message,
        :stdout          => '',
      }
    end

    res[:duration] = (Time.now.to_f - started.to_f).round(5)

    return res
  end

  def self.change_passwd_no_upstream(host, actor_dn,
        actor_password, target_user_username, target_user_password,
        external_pw_mgmt_url=nil)

    target_user_dn = PuavoRest::User.by_username!(target_user_username).dn.to_s

    # First change the password to external service(s) and then to us.
    # If we can not change it to external service(s), do not change it for us
    # either.
    if external_pw_mgmt_url then
      has_permissions = \
         LdapPassword.has_password_change_permissions?(host,
           actor_dn, actor_password, target_user_dn,
           target_user_password)

      unless has_permissions then
        errmsg = "User '#{ actor_username }' has no sufficient permissions" \
                   " to change password for user '#{ target_user_username }'"
        raise errmsg
      end

      begin
        change_passwd_downstream(target_user_username,
                                 target_user_password,
                                 external_pw_mgmt_url)
      rescue StandardError => e
        raise "Cannot change downstream passwords: #{ e.message }"
      end
    end

    LdapPassword.change_ldap_passwd(host, actor_dn, actor_password,
                                    target_user_dn, target_user_password)
  end

  def self.change_passwd_downstream(target_user_username,
        target_user_password, external_pw_mgmt_url)

    params = {
      'username'          => target_user_username,
      'new_user_password' => target_user_password,
    }

    http_res = HTTP.send('post', external_pw_mgmt_url, :json => params)

    return true if http_res.code == 200

    raise http_res.body.to_s
  end

  def self.change_passwd_upstream(host, actor_username, actor_password,
                                  target_user_username, target_user_password)
    begin
      external_login = PuavoRest::ExternalLogin.new
      login_service = external_login.new_external_service_handler()
      login_service.change_password(actor_username,
                                    actor_password,
                                    target_user_username,
                                    target_user_password)
    rescue ExternalLoginNotConfigured => e
      # If external logins are not configured or the target user is missing
      # from an external login database, we should end up here, and that is
      # normal.
      short_msg = 'not changing upstream password,' \
                    + ' because external logins are not configured'
      long_msg = "#{ short_msg }: #{ e.message }"
      $rest_flog.info(short_msg, long_msg)
      return {
        :exit_status     => 0,
        :extlogin_status => PuavoRest::ExternalLoginStatus::NOTCONFIGURED,
        :stderr          => '',
        :stdout          => "external login not configured: #{ e.message }",
      }

    rescue ExternalLoginWrongPassword => e
      short_errmsg = 'login to upstream password change service failed'
      long_errmsg  = "#{ short_errmsg } for user"         \
                       + " '#{ target_user_username }': " \
                       + e.message
      $rest_flog.error(short_errmsg, long_errmsg)
      return {
        :exit_status     => 1,
        :extlogin_status => PuavoRest::ExternalLoginStatus::BADUSERCREDS,
        :stderr          => long_errmsg,
        :stdout          => '',
      }

    rescue StandardError => e
      short_errmsg = 'changing external service password failed'
      long_errmsg  = "#{ short_errmsg } for user"         \
                       + " '#{ target_user_username }': " \
                       + e.message
      $rest_flog.error(short_errmsg, long_errmsg)
      return {
        :exit_status     => 1,
        :extlogin_status => PuavoRest::ExternalLoginStatus::UPDATEERROR,
        :stderr          => long_errmsg,
        :stdout          => '',
      }
    end

    $rest_flog.info('upstream password changed',
                    'upstream password changed for user' \
                      + " '#{ target_user_username }' by '#{ actor_username }'")

    return {
      :exit_status     => 0,
      :extlogin_status => PuavoRest::ExternalLoginStatus::UPDATED,
      :stderr          => '',
      :stdout          => 'password change to external login service ok',
    }
  end

  class LdapPassword
    def self.has_password_change_permissions?(host, bind_dn, bind_dn_pw,
                                              user_dn, new_pw)
      # "-n" for ldappasswd means "dry-run", it does not change the password
      # but instead can tell us if password change is possible.
      # It does check the permissions as well, which is what we want.
      res = run_ldappasswd(host, bind_dn, bind_dn_pw, user_dn, new_pw,
                           [ '-n' ])

      return res[:exit_status] == 0
    end

    def self.change_ldap_passwd(host, bind_dn, bind_dn_pw, user_dn, new_pw)
      run_ldappasswd(host, bind_dn, bind_dn_pw, user_dn, new_pw)
    end

    def self.run_ldappasswd(host, bind_dn, bind_dn_pw, user_dn, new_pw,
                            extra_cmd_args=[])
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
              # plus add possible extra command arguments
              *extra_cmd_args,
              # The user whose password we're changing
              user_dn.to_s ]

      stdout_str, stderr_str, status = Open3.capture3(*cmd)

      return {
        :exit_status => status.exitstatus,
        :stderr      => stderr_str,
        :stdout      => stdout_str,
      }
    end
  end
end
