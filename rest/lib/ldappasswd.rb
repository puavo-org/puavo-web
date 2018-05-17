require "open3"

require_relative './external_login'

module Puavo

  def self.change_passwd(host, bind_dn, bind_dn_pw, new_pw, target_user_dn,
                         target_user_username, external_pw_mgmt_url=nil)
    started = Time.now

    res = change_upstream_password(host, bind_dn, bind_dn_pw, new_pw,
                                   target_user_username)
    res[:duration] = (Time.now.to_f - started.to_f).round(5)

    # Return if upstream password change failed.  This allows external
    # (upstream) password service to block password changes, for example
    # because password policy rejects the password or user does not have
    # sufficient permissions for the change operation.
    return res unless res[:exit_status] == 0

    begin
      res = change_passwd_no_upstream_change(host, bind_dn, bind_dn_pw, new_pw,
              target_user_dn, target_user_username, external_pw_mgmt_url)
    rescue StandardError => e
      res = {
        :exit_status => 1,
        :stderr      => e.message,
        :stdout      => '',
      }
    end

    res[:duration] = (Time.now.to_f - started.to_f).round(5)

    return res
  end

  def self.change_passwd_no_upstream_change(host, bind_dn, bind_dn_pw, new_pw,
        target_user_dn, target_user_username, external_pw_mgmt_url=nil)
    # First change the password to external service(s) and then to us.
    # If we can not change it to external service(s), do not change it for us
    # either.
    if external_pw_mgmt_url then
      has_permissions = LdapPassword.has_password_change_permissions?(host,
                          bind_dn, bind_dn_pw, new_pw, target_user_dn)

      unless has_permissions then
        errmsg = "User '#{ bind_dn }' has no sufficient permissions to change" \
                   " password for user '#{ target_user_username }'"
        raise errmsg
      end

      begin
        change_downstream_passwords(target_user_username,
                                    new_pw,
                                    external_pw_mgmt_url)
      rescue StandardError => e
        raise "Cannot change downstream passwords: #{ e.message }"
      end
    end

    LdapPasswd.change_ldap_passwd(host, bind_dn, bind_dn_pw, new_pw,
                                  target_user_dn)
  end

  def self.change_downstream_passwords(username, new_pw, external_pw_mgmt_url)
    http_res = HTTP.send('post',
                         external_pw_mgmt_url,
                         :json => { 'username'          => username,
                                    'new_user_password' => new_pw })

    return true if http_res.code == 200

    raise http_res.body.to_s
  end

  def self.change_upstream_password(host, bind_dn, bind_dn_pw, new_pw,
                                    target_user_username)
    begin
      external_login = PuavoRest::ExternalLogin.new
      login_service = external_login.new_external_service_handler()
      login_service.change_password(target_user_username, new_pw)
    rescue ExternalLoginNotConfigured => e
      # this is normal
      return {
        :exit_status => 0,
        :stderr      => '',
        :stdout      => 'external logins are not configured',
      }
    rescue StandardError => e
      errmsg = 'changing external service password failed'
      # XXX how to log this? (flog does not exist here)
      # flog.error(errmsg,
      #            "#{ errmsg } for user '#{ target_user_username }': " \
      #              + e.message)
      return {
        :exit_status => 1,
        :stderr      => errmsg,
        :stdout      => '',
      }
    end

    return {
      :exit_status => 0,
      :stderr      => '',
      :stdout      => 'password change to external login service ok',
    }
  end

  class LdapPasswd
    def self.has_password_change_permissions?(host, bind_dn, bind_dn_pw,
                                              new_pw, user_dn)
      # "-n" for ldappasswd means "dry-run", it does not change the password
      # but instead can tell us if password change is possible.
      # It does check the permissions as well, which is what we want.
      res = run_ldappasswd(host, bind_dn, bind_dn_pw, new_pw, user_dn,
                           [ '-n' ])

      return res[:exit_status] == 0
    end

    def self.change_ldap_passwd(host, bind_dn, bind_dn_pw, new_pw, user_dn)
      run_ldappasswd(host, bind_dn, bind_dn_pw, new_pw, user_dn)
    end

    def self.run_ldappasswd(host, bind_dn, bind_dn_pw, new_pw, user_dn,
                            extra_cmd_args=[])
      cmd = [ 'ldappasswd',
              # use simple authentication instead of SASL
              '-x',
              # issue StartTLS (Transport Layer Security) extended operation
              '-Z',
              # specify an alternate host on which the ldap server is running
              '-h', host,
              # Distinguished Name used to bind to the LDAP directory
              '-D', bind_dn.to_s,
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
