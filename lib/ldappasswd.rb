
require "open3"

module Puavo

  def self.ldap_passwd(host, bind_dn, current_pw, new_pw, user_dn)
    started = Time.now.to_i
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

      # User who's password we're going to change
      user_dn.to_s

    ) do |stdin, stdout, stderr, wait_thr|
      wait_thr.join

      res = {
        :duration => Time.now.to_i - started,
        :stdout => stdout.read(1024 * 5),
        :stderr => stderr.read(1024 * 5),
        :exit_status => wait_thr.value.exitstatus,
        :args => {
          :host => host,
          :bind_dn => bind_dn.to_s,
          :user_dn => user_dn.to_s,
        }
      }

    end

    return res
  end
end
