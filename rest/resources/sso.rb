require "jwt"
require "addressable/uri"
require "sinatra/r18n"
require "redcarpet"
require "gibberish"
require_relative "./users"

require_relative "../local_store"

module PuavoRest

class ExternalService < LdapModel
  include LocalStore


  ldap_map(:dn, :dn){ |dn| Array(dn).first.downcase.strip }
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
    by_attr(:domain, domain, :multi)
  end

  def self.secret_by_share_once_token(token)
    encrypt_secret = self.new.local_store_get(token)

    return if encrypt_secret.nil?

    self.new.local_store_del(token)
    cipher = Gibberish::AES.new(token)
    cipher.dec(encrypt_secret)
  end

  def share_once_token=(token)
    cipher = Gibberish::AES.new(token)
    local_store_set(token, cipher.enc(self.secret))
    local_store_expire(token, 60*60*24*7)
  end

  def instance_key
    "external_service:"
  end

end

class SSO < LdapSinatra
  register Sinatra::R18n

  get "/v3/sso/share_once/:key" do
    content_type :txt

    if secret = ExternalService.secret_by_share_once_token(params["key"])
      secret
    else
      halt 404, "no such key"
    end
  end

  def return_to
    Addressable::URI.parse(params["return_to"]) if params["return_to"]
  end

  def fetch_external_service
    if return_to
      LdapModel.setup(:credentials => CONFIG["server"]) do

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
      "#{ t.sso.username }@#{ t.sso.organisation }.#{ topdomain }"
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
      return render_form(t.sso.kerberos_error, err)
    rescue JSONError => err
      # Pass custom error headers to the response login page
      response.headers.merge!(err.headers)
      return render_form(t.sso.bad_username_or_pw, err)
    end

    user = User.current
    primary_school = user.school

    # Read organisation data manually instead of using the cached one because
    # enabled external services might be updated.
    organisation = LdapModel.setup(:credentials => CONFIG["server"]) do
      Organisation.by_dn(LdapModel.organisation["dn"])
    end

    school_allows = Array(primary_school["external_services"]).
      include?(@external_service["dn"])
    organisation_allows = Array(organisation["external_services"]).
      include?(@external_service["dn"])
    trusted = @external_service["trusted"]

    if not (trusted || school_allows || organisation_allows)
      return render_form(t.sso.service_not_activated)
    end


    jwt_data = user.to_hash.merge({
      # Issued At
      "iat" => Time.now.to_i.to_s,
      # JWT ID
      "jti" => UUID.generator.generate,

      # use external_id like in Zendesk?
      # https://support.zendesk.com/entries/23675367

      "external_service_path_prefix" => @external_service["prefix"]
    })

    jwt = JWT.encode(jwt_data, @external_service["secret"])
    r = return_to
    r.query_values = (r.query_values || {}).merge("jwt" => jwt)

    logger.info "Redirecting SSO auth #{ user["first_name"] } #{ user["last_name"] } (#{ user["dn"] } to #{ r }"
    flog.info("sso", {
      :login_ok => true,
      :return_to => return_to,
      :jwt => jwt_data
    })
    redirect r.to_s
  end

  get "/v3/sso" do
    respond_auth
  end

  def render_form(error_message, err=nil)
    if env["REQUEST_METHOD"] == "POST"
      @error_message = error_message
      err_msg = {
        :login_ok => false,
        :reason => error_message,
        :params => params
      }
      if err
        err_msg[:error_class] = err.class.name
        err_msg[:error_message] = err.message
      end
      flog.warn "sso", err_msg
    end

    @external_service ||= fetch_external_service
    @organisation = preferred_organisation

    if !(browser.linux? && browser.gecko?)
      # Kerberos authentication works only on Opinsys desktops with Firefox.
      # Disable authentication negotiation on others since it  may cause
      # unwanted basic auth popups (at least Chrome & IE @ Windows).
      response.headers.delete("WWW-Authenticate")
    end
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

  def topdomain
    CONFIG["topdomain"]
  end

  def ensure_topdomain(org)
    return if org.nil?
    if !org.end_with?(topdomain)
      return "#{ org }.#{ topdomain }"
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
      Organisation.by_domain(org)
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
      if Organisation.by_domain(ensure_topdomain(user_org)).nil?
        logger.info "Could not find organisation for domain #{ user_org }"
        render_form(t.sso.bad_username_or_pw)
      end
    end

    org = [
      user_org,
      params["organisation"],
      request.host,
    ].map do |org|
      Organisation.by_domain(ensure_topdomain(org))
    end.compact.first


    if org
      LdapModel.setup(:organisation => org)
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
    File.open("doc/SSO_DEVELOPERS.md", "r") do |f|
      @body = markdown.render(f.read())
      erb :developers, :layout => :layout
    end
  end

end
end
