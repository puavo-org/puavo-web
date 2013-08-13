require "jwt"
require "addressable/uri"

module PuavoRest
class SSO < LdapSinatra

  def respond_auth
    if params["return_to"].nil?
      raise BadInput, :user => "return_to missing"
    end

    return_url = Addressable::URI.parse(params["return_to"])
    shared_secret =  (CONFIG["sso"] || {})[return_url.host]

    if shared_secret.nil?
      raise Unauthorized,
        :user => "Unknown client service #{ return_url.host }"
    end


    begin
      auth :basic_auth, :from_post, :kerberos
    rescue JSONError => err
      @error_message = err.to_s
      halt 401, {'Content-Type' => 'text/html'}, erb(:login_form)
    end

    user = User.current

    jwt = JWT.encode({
      # Issued At
      "iat" => Time.now.to_i.to_s,
      # JWT ID
      "jti" => UUID.generator.generate,

      # use external_id like in Zendesk?
      # https://support.zendesk.com/entries/23675367
      "user_dn" => user["dn"],
      "puavo_id" => user["puavo_id"],
      "username" => user["username"],
      "first_name" => user["first_name"],
      "last_name" => user["last_name"],
      "user_type" => user["user_type"],
      "email" => user["email"],
      "organisation_name" => user["organisation"]["name"],
      "organisation_domain" => user["organisation"]["domain"],
    }, shared_secret)

    return_url.query_values = (
      return_url.query_values || {}
    ).merge("jwt" => jwt)

    redirect return_url.to_s
  end

  get "/v3/sso" do
    respond_auth
  end

  post "/v3/sso" do
    if org = params["organisation"]
        LdapHash.setup(:organisation => Organisation.by_domain[org])
    end

    respond_auth
  end

end
end
