require "sinatra/r18n"
require "pony"

module PuavoRest

class Password < LdapSinatra
  register Sinatra::R18n

  post "/password/send_token" do
    auth :server_auth

    # FIXME Request limit? Denial of Service?

    user = User.by_username(params["username"])

    if user.nil?
      status 404
      return json({ :status => "failed",
                    :error => "Cannot find user" })
    end

    if user.email.nil?
      status 404
      return json({ :status => "failed",
                    :error => "User does not have an email address" })
    end

    # FIXME: is correct style?
    R18n::I18n.default = language_by_locale(user.locale)

    jwt_data = {
      # Issued At
      "iat" => Time.now.to_i.to_s,

      "username" => user.username,
      "organisation_domain" => user.organisation_domain
    }

    jwt = JWT.encode(jwt_data, CONFIG["password_management"]["secret"])

    @password_reset_url = "https://#{ user.organisation_domain }/password/reset/#{ jwt }"
    @first_name = user.first_name

    message = erb(:password_email, :layout => false)

    email_options = {
      :to => user.email,
      :subject => t.password_management.subject,
      :body => message,
      :via => :smtp
    }.merge(CONFIG["password_management"]["smtp"])

    Pony.mail( email_options )

    json({ :status => 'successfully' })

  end

  end

  private

  def language_by_locale(locale)
    locale.match(/^[a-z]{2}/)[0]
  end

end
end

