require "jwt"
require "addressable/uri"
require "sinatra/r18n"
require "redcarpet"

module PuavoRest

class ExternalService < LdapHash

  ldap_map :dn, :dn
  ldap_map :cn, :name
  ldap_map :puavoServiceDomain, :domain
  ldap_map :puavoServiceSecret, :secret
  ldap_map :description, :description
  ldap_map :puavoServiceDescriptionURL, :description_url
  ldap_map :puavoServiceTrusted, :trusted
  ldap_map :puavoServicePathPrefix, :prefix, "/"

  def self.ldap_base
    "ou=Services,o=puavo"
  end

  def self.by_domain(domain)
    filter("(puavoServiceDomain=#{ escape domain })")
  end

end

class SSO < LdapSinatra
  register Sinatra::R18n

  def return_to
    Addressable::URI.parse(params["return_to"]) if params["return_to"]
  end

  def fetch_external_service
    if return_to
      LdapHash.setup(:credentials => CONFIG["server"]) do

        # Single domain might have multiple external services configured to
        # different paths. Match paths from the longest to shortest.
        ExternalService.by_domain(return_to.host).sort do |a,b|
          b["prefix"].size <=> a["prefix"].size
        end.select do |s|
          if return_to.path.to_s.empty?
            path = "/"
          else
            path = return_to.path
          end
          path.start_with?(s["prefix"])
        end.first

      end
    end

  end

  def username_placeholder
    if preferred_organisation
      t.sso.username
    else
      "#{ t.sso.username }@#{ t.sso.organisation }.#{ CONFIG["topdomain"] }"
    end
  end

  def respond_auth
    if return_to.nil?
      raise BadInput, :user => "return_to missing"
    end

    @external_service = fetch_external_service

    if @external_service.nil?
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
    school = School.by_dn(user["school_dn"])

    school_allows = Array(school["external_services"]).
      include?(@external_service["dn"])
    organisation_allows = Array(LdapHash.organisation["external_services"]).
      include?(@external_service["dn"])
    trusted = @external_service["trusted"]

    if not (trusted || school_allows || organisation_allows)
      return render_form(t.sso.service_not_activated)
    end


    jwt = JWT.encode({
      # Issued At
      "iat" => Time.now.to_i.to_s,
      # JWT ID
      "jti" => UUID.generator.generate,

      # use external_id like in Zendesk?
      # https://support.zendesk.com/entries/23675367
      "user_dn" => user["dn"],
      "id" => user["puavo_id"],
      "username" => user["username"],
      "first_name" => user["first_name"],
      "last_name" => user["last_name"],
      "user_type" => user["user_type"],
      "email" => user["email"],
      "school_name" => school["name"],
      "school_id" => school["puavo_id"],
      "organisation_name" => user["organisation"]["name"],
      "organisation_domain" => user["organisation"]["domain"],
      "external_service_path_prefix" => @external_service["prefix"]
    }, @external_service["secret"])


    r = return_to
    r.query_values = (r.query_values || {}).merge("jwt" => jwt)

    logger.info "Redirecting SSO auth #{ user["first_name"] } #{ user["last_name"] } (#{ user["dn"] } to #{ r }"
    redirect r.to_s
  end

  get "/v3/sso" do
    respond_auth
  end

  def render_form(error_message)
    if env["REQUEST_METHOD"] == "POST"
      @error_message = error_message
    end
    @external_service ||= fetch_external_service
    @organisation = preferred_organisation
    halt 401, {'Content-Type' => 'text/html'}, erb(:login_form, :layout => :layout)
  end

  def username_prefill
    [
      # what user typed last
      params["username"],
      # organisation presetting
      (@organisation ? "@#{ @organisation["domain"] }" : nil),
    ].compact.first
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
      logger.fatal "SSO: Organisation missing from username: #{ params["username"] }"
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
