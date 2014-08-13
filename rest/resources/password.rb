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

    @password_reset_url = "https://#{ user.organisation_domain }/password/change/#{ jwt }"
    @first_name = user.first_name

    message = erb(:password_email, :layout => false)

    email_options = {
      :to => user.email,
      :subject => t.password_management.subject,
      :body => message,
      :via => :smtp
    }.merge(CONFIG["password_management"]["smtp"]).recursive_symbolize_keys!

    Pony.mail( email_options )

    json({ :status => 'successfully' })

  end

  put "/password/change/:jwt" do
    auth :server_auth

    if params[:new_password].nil? || params[:new_password].empty?
      status 404
      return json({ :status => "failed",
                    :error => "Invalid new password" })
    end

    begin
      jwt_data = JWT.decode(params[:jwt], CONFIG["password_management"]["secret"])
    rescue JWT::DecodeError
      status 404
      return json({ :status => "failed",
                    :error => "Invalid jwt token" })
    end

    if Time.at( jwt_data["iat"].to_i + 24*60*60 ) < Time.now
      status 404
      return json({ :status => "failed",
                    :error => "Token lifetime has expired" })
    end

    if jwt_data["organisation_domain"] != request.host
      status 404
      return json({ :status => "failed",
                    :error => "Invalid organisation domain" })

    end

    user = User.by_username(jwt_data["username"])

    if user.nil?
      status 404
      return json({ :status => "failed",
                    :error => "Cannot find user" })
    end

    # Change password
  end

  private

  def language_by_locale(locale)
    begin
      locale.match(/^[a-z]{2}/)[0]
    rescue NoMethodError
      return "en"
    end
  end

end
end

