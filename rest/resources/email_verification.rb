# Email address changing and verification. Very similar to password resetting.

require 'sinatra/r18n'

module PuavoRest

class EmailManagement < PuavoSinatra
  register Sinatra::R18n

  # Add or remove user's email addresses. Can remove verification/primary emails, but not set them.
  post '/email_verification/change_addresses' do
    auth :email_mgmt_server_auth

    data = JSON.parse(request.body.read)
    request_id = data.fetch('request_id', '???')

    unless Array(CONFIG['email_management']['ip_whitelist'] || []).include?(request.ip)
      $rest_log.error("[#{request_id}] got a POST /email_verification/change_addresses from an unauthorised IP address \"#{request.ip}\"")
      status 403
      return
    end

    $rest_log.info("[#{request_id}] Updating the email addresses of user \"#{data['username']}\" (DN=#{data['dn']})")

    user = User.by_dn(data['dn'])

    if user.nil?
      # Should not happen, as the user has already been validated, but it doesn't hurt to double-check
      $rest_log.error("[#{request_id}] The user does not exist")
      status 404
      return
    end

    current_addresses = Array(user.email || [])
    new_addresses = Array(data['emails'])

    begin
      if new_addresses.empty?
        $rest_log.info("[#{request_id}] Clearing all email addresses")

        user.class.ldap_op(:modify, user.dn, [LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'mail', [])])
        user.class.ldap_op(:modify, user.dn, [LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'puavoVerifiedEmail', [])])
        user.class.ldap_op(:modify, user.dn, [LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'puavoPrimaryEmail', [])])
      else
        $rest_log.info("[#{request_id}] New email addresses are: [#{new_addresses.join(', ')}]")
        user.class.ldap_op(:modify, user.dn, [LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'mail', new_addresses)])

        # Handle verified/primary address removals. We can remove, but we will never set.
        current_verified = Array(user.verified_email || []).to_set
        new_verified = []

        new_addresses.each do |a|
          if current_verified.include?(a)
            new_verified << a
          end
        end

        if new_verified.to_set != current_verified
          $rest_log.info("[#{request_id}] New verified addresses are: [#{new_verified.join(', ')}]")
          user.class.ldap_op(:modify, user.dn, [LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'puavoVerifiedEmail', new_verified)])
        else
          $rest_log.info("[#{request_id}] Verified email addresses did not change")
        end

        if user.primary_email && !new_verified.include?(user.primary_email)
          $rest_log.info("[#{request_id}] The current primary email address isn't verified anymore, picking the next available")

          if new_verified.empty?
            $rest_log.info("[#{request_id}] No other verified addresses left")
            user.class.ldap_op(:modify, user.dn, [LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'puavoPrimaryEmail', [])])
          else
            $rest_log.info("[#{request_id}] Selecting \"#{new_verified.first}\" as the new primary address")
            user.class.ldap_op(:modify, user.dn, [LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'puavoPrimaryEmail', [new_verified.first])])
          end
        else
          $rest_log.info("[#{request_id}] Primary email address did not change")
        end
      end
    rescue StandardError => e
      $rest_log.error("[#{request_id}] Could not update the email addresses: #{e}")
      status 500
      return
    end

    $rest_log.info("[#{request_id}] The addresses have been updated")
    status 200
  end

  # Generates and sends the email address verification email
  post '/email_verification/send' do
    auth :email_mgmt_server_auth

    data = JSON.parse(request.body.read)
    request_id = data.fetch('request_id', '???')

    unless Array(CONFIG['email_management']['ip_whitelist'] || []).include?(request.ip)
      $rest_log.error("[#{request_id}] got a POST /email_verification/send from an unauthorised IP address \"#{request.ip}\"")
      status 403
      return
    end

    email = data['email']

    $rest_log.info("[#{request_id}] User \"#{data['username']}\" (DN=#{data['dn']}) is requesting " \
                   "the email address \"#{email}\" to be verified")

    user = User.by_dn(data['dn'])

    if user.nil?
      # Should not happen, as the user has already been validated, but it doesn't hurt to double-check
      $rest_log.error("[#{request_id}] The user does not exist")
      status 404
      return
    end

    # Verify the email address
    unless user.email.include?(email)
      $rest_log.error("[#{request_id}] The user does not have this email address")
      status 400
      return
    end

    if user.verified_email && user.verified_email.include?(email)
      $rest_log.error("[#{request_id}] This address is already verified!")
      status 400
      return
    end

    url = "https://#{user.organisation_domain}/users/email_verification/#{data['token']}?lang=#{data['language']}"

    $rest_log.info("[#{request_id}] The full verification URL is \"#{url}\"")

    # Format and send the verification email
    @first_name = data['first_name']
    @email_verify_url = url

    # Bypass the R18n's current language and use the language used in the form. I spent two hours
    # trying to figure out how to do this, and I'm not sure if it's correctly done.
    @tr = R18n.set(data['language'])

    message = erb(:email_verification, :layout => false)

    begin
      $mailer.send(to: email, subject: t.email_verification.subject, body: message, charset: 'UTF-8')
    rescue => e
      $rest_log.info("[#{request_id}] The email could not be sent: #{e}")
      status 404
      return
    end

    $rest_log.info("[#{request_id}] The email has been sent")
    status 200
  end

  # Actually verify the address
  put '/email_verification/verify' do
    auth :email_mgmt_server_auth

    data = JSON.parse(request.body.read)
    request_id = data.fetch('request_id', '???')

    begin
      unless Array(CONFIG['email_management']['ip_whitelist'] || []).include?(request.ip)
        $rest_log.error("[#{request_id}] got a PUT /email_verification/verify from an unauthorised IP address \"#{request.ip}\"")
        status 403
        return
      end

      address = data['email']

      $rest_log.info("[#{request_id}] Verifying address \"#{address}\" for user \"#{data['username']}\" (\"#{data['dn']}\")")

      user = User.by_dn(data['dn'])

      if user.nil?
        # Should not happen, as the user has already been validated, but it doesn't hurt to double-check
        $rest_log.error("[#{request_id}] The user does not exist")
        status 404
        return
      end

      unless user.email.include?(address)
        $rest_log.error("[#{request_id}] The user does not have this email address")
        status 400
        return
      end

      if user.verified_email && user.verified_email.include?(address)
        $rest_log.error("[#{request_id}] This address is already verified!")
        status 400
        return
      end

      # Verify the email address
      if user.verified_email.nil? || user.verified_email.empty?
        user.class.ldap_op(:modify, user.dn, [LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'puavoVerifiedEmail', [address])])
      else
        user.class.ldap_op(:modify, user.dn, [LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'puavoVerifiedEmail', user.verified_email + [address])])
      end

      unless user.primary_email
        # Set the initial primary address
        $rest_log.info("[#{request_id}] Setting \"#{address}\" as the primary address")
        user.class.ldap_op(:modify, user.dn, [LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, 'puavoPrimaryEmail', [address])])
      end

      $rest_log.info("[#{request_id}] The address has been verified")
      status 200
    rescue StandardError => e
      $rest_log.info("[#{request_id}] Failed to verify the address: #{e}")
      status 500
    end
  end
end

end   # module PuavoRest
