
require "open3"

module Puavo

  def self.ldap_passwd(host, bind_dn, current_pw, new_pw, user_dn, external_pw_mgmt_url = nil)
    started = Time.now
    res = nil

    unless external_pw_mgmt_url.nil?
      user = User.find(user_dn)
      res = HTTP.send("post", external_pw_mgmt_url, :json => {"username" => user.uid, "new_user_password" => new_pw})

      puts res.body
      if res.code != 200

        return {
          :duration => (Time.now.to_f - started.to_f).round(5),
          :stdout => "",
          :stderr => "Cannot change extrenal password: " + res.body.to_s,
          :exit_status => 1
      }

      end
    end


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

      res = {
        :duration => (Time.now.to_f - started.to_f).round(5),
        :stdout => stdout.read(1024 * 5),
        :stderr => stderr.read(1024 * 5),
        :exit_status => wait_thr.value.exitstatus
      }

    end

    return res
  end
end
