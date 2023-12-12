# Multi-factor authentication management. Enables or disables it for a user.
# This is not used on normal production puavo-rest machines. It's used in
# a special puavo-rest server that runs in a special mode.

require 'base64'

module PuavoRest

class MFAManagement < PuavoSinatra
  # Enable or disable MFA for a user
  post '/v3/mfa/change_state' do
    auth :mfa_mgmt_server_auth

    # Authenticate the caller (client)
    got = request.env.fetch('HTTP_AUTHORIZATION', '')

    auth_config = CONFIG['mfa_management']['client']
    expected = 'Basic ' + Base64.strict_encode64(auth_config['username'] + ':' + auth_config['password']).strip

    unless got == expected
      $rest_log.error("got a POST /mfa/change_state with invalid authorisation (#{got}), from an IP address \"#{request.ip}\"")
      status 401
      return
    end

    data = JSON.parse(request.body.read)
    request_id = data.fetch('request_id', '???')

    # IP address check
    unless Array(CONFIG['mfa_management']['ip_whitelist'] || []).include?(request.ip)
      $rest_log.error("[#{request_id}] got a POST /mfa/change_state from an unauthorised IP address \"#{request.ip}\"")
      status 403
      return
    end

    $rest_log.info("[#{request_id}] Changing the MFA activation state of user \"#{data['user_uuid']}\" to #{data['mfa_state'].inspect}")

    user = User.by_dn(data['user_dn'])

    if user.nil?
      # Should not happen, as the user has already been validated, but it doesn't hurt to double-check
      $rest_log.error("[#{request_id}] The user does not exist")
      status 404
      return
    end

    begin
      # Ensure we have a boolean
      case data['mfa_state']
        when true
          user.mfa_enabled = true
          $rest_log.info("[#{request_id}] MFA enabled")
        when false
          user.mfa_enabled = false
          $rest_log.info("[#{request_id}] MFA disabled")
        else
          $rest_log.error("[#{request_id}] Cannot interpret the MFA state as a boolean")
          status 400
          return
      end

      user.save!
    rescue StandardError => e
      $rest_log.error("[#{request_id}] Could not update the MFA activation state: #{e}")
      status 500
      return
    end

    $rest_log.info("[#{request_id}] The state has been updated")
    status 200
  end
end

end   # module PuavoRest
