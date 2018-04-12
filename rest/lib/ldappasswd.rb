
require "open3"

module Puavo

  def self.change_passwd(host, bind_dn, current_pw, new_pw, user_dn,
                         external_pw_mgmt_url=nil)
    started = Time.now

    res = change_upstream_password(host, bind_dn, current_pw, new_pw, user_dn)

    return res unless res

    res[:duration] = (Time.now.to_f - started.to_f).round(5)

    # Return if upstream password change failed.
    return res unless res && res[:exit_status] == 0

    begin
      res = change_passwd_no_upstream_change(host, bind_dn, current_pw,
              new_pw, user_dn, external_pw_mgmt_url)
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

  def self.change_passwd_no_upstream_change(host, bind_dn, current_pw, new_pw,
                                            user_dn, external_pw_mgmt_url=nil)
    res = LdapPasswd.run_ldap_passwd(host, bind_dn, current_pw, new_pw,
                                     user_dn)

    return res unless external_pw_mgmt_url && res && res[:exit_status] == 0

    # Do downstream password management only after we know that password
    # changing to ldap has worked.  It might seem better to do this the
    # other way around, but this is the only way to make sure that the
    # bind_dn/user has permissions to change the password for user_dn/user.
    # XXX Using slapacl(8) to check for permissions, then first changing
    # XXX the external passwords and then our ldap password might be
    # XXX the better option.

    begin
      change_downstream_passwords(User.find(user_dn),
                                  new_pw,
                                  external_pw_mgmt_url)
    rescue StandardError => e
      # Restore old password for user
      # (XXX only effective if bind_dn and user_dn match).
      if bind_dn.to_s == user_dn.to_s then
        LdapPasswd.run_ldap_passwd(host, bind_dn, new_pw, current_pw, user_dn)
      end
      raise e
    end

    return res
  end

  def self.change_downstream_passwords(user, new_pw, external_pw_mgmt_url)
    http_res = HTTP.send('post',
                         external_pw_mgmt_url,
                         :json => { 'username'          => user.uid,
                                    'new_user_password' => new_pw })

    return true if http_res.code == 200

    raise "Cannot change downstream passwords: #{ http_res.body.to_s }"
  end

  def self.change_upstream_password(host, bind_dn, current_pw, new_pw, user_dn)
    # XXX This should change upstream password, for example the password on
    # XXX Microsoft AD Directory.  We might not be configured to handle
    # XXX external upstream passwords, so we should return true in that case.
    return {
      :exit_status => 0,
      :stderr      => '',
      :stdout      => '',
    }
  end

  class LdapPasswd
    def self.run_ldap_passwd(host, bind_dn, current_pw, new_pw, user_dn)
      cmd = [ 'ldappasswd',
              # Use simple authentication instead of SASL
              '-x',
              # Issue StartTLS (Transport Layer Security) extended operation
              '-Z',
              # Specify an alternate host on which the ldap server is running
              '-h', host,
              # Distinguished Name used to bind to the LDAP directory
              '-D', bind_dn.to_s,
              # The password to bind with
              '-w', current_pw,
              # Set the new password
              '-s', new_pw,
              # Timeout after 20 sec
              '-o', 'nettimeout=20',
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
