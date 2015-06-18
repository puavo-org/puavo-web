require "sinatra/r18n"

module PuavoRest

class EmailConfirm < PuavoSinatra
  register Sinatra::R18n

  post "/email_confirm" do
    auth :pw_mgmt_server_auth

    # FIXME: validate email address?

    user = User.by_username(params["username"])

    if user.nil?
      status 404
      return json({ :status => "failed",
                    :error => "Cannot find user" })
    end

    jwt_data = {
      # Issued At
      "iat" => Time.now.to_i.to_s,

      "username" => user.username,
      "organisation_domain" => user.organisation_domain,
      "email" => params["email"]
    }

    jwt = JWT.encode(jwt_data, CONFIG["email_confirm"]["secret"])

    @email_confirm_url = "https://#{ user.organisation_domain }/users/email_confirm/#{ jwt }"
    @first_name = user.first_name

    message = erb(:email_confirm, :layout => false)

    $mailer.send( :to => params["email"],
                  :subject => t.email_confirm.subject,
                  :body => message )

    json({ :status => 'successfully' })

  end

end
end

