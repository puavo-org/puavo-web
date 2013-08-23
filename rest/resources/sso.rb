require "jwt"
require "addressable/uri"
require "sinatra/r18n"
require "redcarpet"

module PuavoRest
class SSO < LdapSinatra
  register Sinatra::R18n

  def return_to
    Addressable::URI.parse(params["return_to"]) if params["return_to"]
  end
  def external_service
    (CONFIG["sso"] || {})[return_to.host] if return_to
  end

  def respond_auth
    if return_to.nil?
      raise BadInput, :user => "return_to missing"
    end

    if external_service.nil?
      raise Unauthorized,
        :user => "Unknown client service #{ return_to.host }"
    end

    begin
      auth :basic_auth, :from_post, :kerberos
    rescue KerberosError => err
      logger.info("SSO kerberos error: #{ err }")
      return render_form(t.sso.kerberos_error)
    rescue JSONError => err
      logger.info("SSO error: #{ err }")
      return render_form(t.sso.bad_username_or_pw)
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
    }, external_service["secret"])


    r = return_to
    r.query_values = (r.query_values || {}).merge("jwt" => jwt)
    redirect r.to_s
  end

  get "/v3/sso" do
    respond_auth
  end

  def render_form(error_message)
    if env["REQUEST_METHOD"] == "POST"
      @error_message = error_message
    end
    @organisation = preferred_organisation
    halt 401, {'Content-Type' => 'text/html'}, erb(:login_form, :layout => :layout)
  end

  def ensure_topdomain(org)
    return if org.nil?
    if !org.end_with?(CONFIG["topdomain"])
      return "#{ org }.#{ CONFIG["topdomain"] }"
    end
    org
  end

  def preferred_organisation
    [
      params["organisation"],
      request.host,
    ].compact.map do |org|
      ensure_topdomain(org)
    end.map do |org|
      Organisation.by_domain[org]
    end.first
  end

  post "/v3/sso" do

    if params["username"].include?("@") && params["organisation"]
      render_form(t.sso.invalid_username)
    end

    if !params["username"].include?("@") && params["organisation"].nil?
      render_form(t.sso.organisation_missing)
    end

    user_org = nil

    if params["username"].include?("@")
      _, user_org = params["username"].split("@")
      if Organisation.by_domain[ensure_topdomain(user_org)].nil?
        logger.info "Could not find organisation for domain #{ user_org }"
        render_form(t.sso.bad_username_or_pw)
      end
    end

    org = [
      user_org,
      params["organisation"],
      request.host,
    ].map do |org|
      Organisation.by_domain[ensure_topdomain(org)]
    end.compact.first


    if org
      LdapHash.setup(:organisation => org)
    else
      render_form(t.sso.no_organisation)
    end

    respond_auth
  end

  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML,
    :autolink => true,
    :prettify => true,
    :fenced_code_blocks => true,
    :space_after_headers => true
  )

  get "/v3/sso/developers" do
    File.open("doc/SSO_APP_DEVS.md", "r") do |f|
      @body = markdown.render(f.read())
      erb :developers, :layout => :layout
    end
  end

end
end
