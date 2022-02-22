require "sinatra/r18n"

module PuavoRest

class Password < PuavoSinatra
  register Sinatra::R18n

  # Generate and send a password reset email
  post "/password/send_token" do
    auth :pw_mgmt_server_auth

    # FIXME Request limit? Denial of Service?

    request_id = params.fetch('request_id', '???')

    email = params['email']

    $rest_log.info("[#{request_id}] User \"#{params['username']}\" (ID=#{params['id']}) is requesting " \
                   "their password to be reset, email address is \"#{email}\", source IP=\"#{request.ip}\"")

    user = User.by_username(params["username"])

    if user.nil?
      # Should not happen, as the user has already been validated,
      # but it doesn't hurt to double-check
      $rest_log.error("[#{request_id}] The user does not exist")
      status 404
      return json({ :status => "failed",
                    :error => "Cannot find the user" })
    end

    if user.email.nil?
      status 404
      return json({ :status => "failed",
                    :error => "User does not have an email address" })
    end

    jwt_data = {
      iat: Time.now.to_i,
      id: user.id.to_i,
      uid: user.username,
      domain: user.organisation_domain
    }

    jwt = JWT.encode(jwt_data, CONFIG["password_management"]["secret"])

    $rest_log.info("[#{request_id}] The generated JWT is #{jwt}")

    @password_reset_url = "https://#{ user.organisation_domain }/users/password/#{ jwt }/reset"
    @first_name = user.first_name

    message = erb(:password_email, :layout => false)

    # The email address has been validated. It really does belong to someone in the system.
    $mailer.send( :to => email,
                  :subject => t.password_management.subject,
                  :body => message )

    $rest_log.info("[#{request_id}] The email has been sent")

    json({ :status => 'successfully' })
  end

  # Perform the password reset
  put "/password/change/:jwt" do
    auth :pw_mgmt_server_auth

    if json_params["new_password"].nil? || json_params["new_password"].empty?
      status 404
      return json({ :status => "failed",
                    :error  => "Invalid new password" })
    end

    request_id = json_params.fetch('request_id', '???')

    $rest_log.info("[#{request_id}] Received a password reset request")

    begin
      jwt_data = JWT.decode(params[:jwt], CONFIG["password_management"]["secret"])[0]
    rescue JWT::DecodeError => e
      $rest_log.error("[#{request_id}] The JWT paylod cannot be decoded: #{e}")
      status 404
      return json({ :status => "failed",
                    :error => "Invalid JWT token" })
    end

    lifetime =  CONFIG["password_management"]["lifetime"]

    if Time.at( jwt_data["iat"] + lifetime ) < Time.now
      $rest_log.error("[#{request_id}] The JWT has expired")
      status 404
      return json({ :status => "failed",
                    :error => "Token lifetime has expired" })
    end

    if jwt_data["domain"] != request.host
      $rest_log.error("[#{request_id}] Invalid organisation domain in the JWT")
      status 404
      return json({ :status => "failed",
                    :error => "Invalid organisation domain" })
    end

    $rest_log.info("[#{request_id}] Resetting the password for user \"#{jwt_data['uid']}\" (ID=#{jwt_data['id']})")

    user = User.by_username(jwt_data['uid'])

    if user.nil? then
      # This can happen, if the user is removed from puavo at the right moment
      $rest_log.error("[#{request_id}] The user does not exist")
      status 404
      return json({ :status => "failed",
                    :error => "Cannot find the user" })
    end

    res = Puavo.change_passwd(:no_upstream,
                              CONFIG['ldap'],
                              PUAVO_ETC.ds_pw_mgmt_dn,
                              nil,
                              PUAVO_ETC.ds_pw_mgmt_password,
                              user.username,
                              json_params['new_password'],
                              request_id)

    rlog.info("changed user password for '#{ user.username }' (DN #{user.dn.to_s})")

    if res[:exit_status] != 0
      $rest_log.error("[#{request_id}] Puavo.change_passwd() failed with error code #{res[:exit_status]}")
      status 404
      return json({ :status => "failed",
                    :error => "Cannot change password for user: #{ user.username }" })
    end

    @first_name = user.first_name

    # This email address has to be correct, since it was validated less than 10 minutes ago
    # when the reset email was sent to it. If someone changes/removes the password during
    # those 10 minutes, that's too bad.
    email = user.email

    message = erb(:password_has_been_reset, :layout => false)

    $rest_log.info("[#{request_id}] The password has been reset, sending the confirmation email to \"#{email}\"")

    $mailer.send( :to => email,
                  :subject => t.password_management.subject,
                  :body => message )

    $rest_log.info("[#{request_id}] The email has been sent")

    # The puavo-web controller that calls us does not actually know who the user is.
    # It could decode the JWT, but it doesn't. So send the user information back,
    # so it can finish the operation.
    json({ :status => 'successfully', uid: user.username, id: user.id.to_i })
  end

end
end

