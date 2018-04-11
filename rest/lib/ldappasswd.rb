
require "open3"

module Puavo

  def self.change_passwd(host, bind_dn, current_pw, new_pw, user_dn, external_pw_mgmt_url = nil)
    started = Time.now

    res = LdapPasswd.run_ldap_passwd(host, bind_dn, current_pw, new_pw, user_dn)
    return res unless res
    res[:duration] = (Time.now.to_f - started.to_f).round(5)

    return res unless external_pw_mgmt_url && res[:exit_status] == 0

    # Do external password management only after we know that password
    # changing to ldap has worked.  It might seem better to do this the
    # other way around, but this is the only way to make sure that the
    # bind_dn/user has permissions to change the password for user_dn/user.

    begin
      change_external_passwd(host, bind_dn, current_pw, new_pw,
                             user_dn, external_pw_mgmt_url)
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

  def self.change_external_passwd(host, bind_dn, current_pw, new_pw, user_dn,
                                  external_pw_mgmt_url)
    user = User.find(user_dn)
    http_res = HTTP.send('post',
                         external_pw_mgmt_url,
                         :json => { 'username'          => user.uid,
                                    'new_user_password' => new_pw })

    return true if http_res.code == 200

    # Restore old password for user
    # (XXX only effective if bind_dn and user_dn match).
    if bind_dn.to_s == user_dn.to_s then
      LdapPasswd.run_ldap_passwd(host, bind_dn, new_pw, current_pw, user_dn)
    end

    raise "Cannot change external password: #{ http_res.body.to_s }"
  end

  class LdapPasswd

    def self.run_ldap_passwd(host, bind_dn, current_pw, new_pw, user_dn)
      res = nil

      Open3.popen3(
        'ldappasswd',

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
        user_dn.to_s

      ) do |stdin, stdout, stderr, wait_thr|
        wait_thr.join

        # XXX This way of doing wait_thr + stdout/stderr reads is not safe
        # XXX if data does not fit into the kernel buffer, and program
        # XXX expects us to to read it before exiting (will likely work
        # XXX with small outputs, though).
        res = {
          :exit_status => wait_thr.value.exitstatus,
          :stderr      => stderr.read(1024 * 5),
          :stdout      => stdout.read(1024 * 5),
        }

      end

      return res
    end
  end
end
