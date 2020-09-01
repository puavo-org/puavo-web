require "jwt"
require "addressable/uri"
require "sinatra/r18n"
require "gibberish"
require_relative "./users"

require_relative "../lib/local_store"

module PuavoRest

class ExternalService < LdapModel
  include LocalStore


  ldap_map(:dn, :dn){ |dn| Array(dn).first.downcase.strip }
  ldap_map :cn, :name
  ldap_map :puavoServiceDomain, :domain
  ldap_map :puavoServiceSecret, :secret
  ldap_map :description, :description
  ldap_map :puavoServiceDescriptionURL, :description_url
  ldap_map :puavoServiceTrusted, :trusted, LdapConverters::StringBoolean
  ldap_map :puavoServicePathPrefix, :prefix, :default => "/"

  def self.ldap_base
    "ou=Services,o=puavo"
  end

  def self.by_domain(domain)
    by_attr(:domain, domain, :multiple => true)
  end

  def self.by_url(url)
    url = Addressable::URI.parse(url.to_s)

    return LdapModel.setup(:credentials => CONFIG["server"]) do

      # Single domain might have multiple external services configured to
      # different paths. Match paths from the longest to shortest.
      ExternalService.by_domain(url.host).sort do |a,b|
        b["prefix"].size <=> a["prefix"].size
      end.select do |s|
        if url.path.to_s.empty?
          path = "/"
        else
          path = url.path
        end
        path.start_with?(s["prefix"])
      end.first
    end

  end

  # Filters a User.to_hash down to a suitable level for SSO URLs
  def filtered_user_hash(user)
    user_hash = user.to_hash

    # Remove DNs, they only take up space and aren't on the spec anyway
    user_hash['schools'].each do |s|
      s.delete('dn')

      s['groups'].each do |g|
        g.delete('dn')
      end
    end

    # Only the members that are on the spec (plus a few more)
    {
      'id' => user_hash['id'],
      'puavo_id' => user_hash['puavo_id'],
      'external_id' => user_hash['external_id'],
      'preferred_language' => user_hash['preferred_language'],
      'user_type' => user_hash['user_type'],      # unknown if actually needed
      'username' => user_hash['username'],
      'first_name' => user_hash['first_name'],
      'last_name' => user_hash['last_name'],
      'email' => user_hash['email'],
      'primary_school_id' => user_hash['primary_school_id'],
      'year_class' => user_hash['year_class'],
      'organisation_name' => user_hash['organisation_name'],
      'organisation_domain' => user_hash['organisation_domain'],
      'external_domain_username' => user_hash['external_domain_username'],
      'schools' => user_hash['schools'],
      'learner_id' => user_hash['learner_id'],
    }
  end

  def generate_login_url(user, return_to_url)
    return_to_url = Addressable::URI.parse(return_to_url.to_s)

    jwt_data = filtered_user_hash(user).merge({
      # Issued At
      "iat" => Time.now.to_i.to_s,
      # JWT ID
      "jti" => UUID.generator.generate,

      # use external_id like in Zendesk?
      # https://support.zendesk.com/entries/23675367

      "external_service_path_prefix" => prefix
    })

    jwt = JWT.encode(jwt_data, secret)
    return_to_url.query_values = (return_to_url.query_values || {}).merge("jwt" => jwt)
    return return_to_url.to_s
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

class SSO < PuavoSinatra
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
    # Support "return_to" and "return"
    if params.include?('return_to')
      Addressable::URI.parse(params['return_to'])
    elsif params.include?('return')
      Addressable::URI.parse(params['return'])
    else
      nil
    end
  end

  def fetch_external_service
    # Support "return_to" and "return"
    if params.include?('return_to')
      ExternalService.by_url(params['return_to'])
    elsif params.include?('return')
      ExternalService.by_url(params['return'])
    else
      nil
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


    url = @external_service.generate_login_url(user, return_to)
    flog.info('redirecting sso auth',
              "redirecting sso auth #{ user['username'] } (#{ user['dn'] }) to #{ url }")

    flog.info('sso login ok', 'sso login ok', {
                :return_to => return_to,
                :external_service => @external_service.to_hash,
                :user => user
              })

    flog.info('sso', nil, {
      :login_ok => true,
      :return_to => return_to
    })

    redirect url
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
        err_msg[:meta] = err.meta
        err_msg[:organisation_domain] = Organisation.current.domain
        flog_err_msg = "sso error: #{ error_message } / #{ err.message }"
      else
        flog_err_msg = "sso error: #{ error_message }"
      end
      flog.warn('sso error', flog_err_msg, err_msg)
    end

    @external_service ||= fetch_external_service
    @organisation = preferred_organisation

    if !(browser.linux?)
      # Kerberos authentication works only on Opinsys desktops with Firefox.
      # Disable authentication negotiation on others since it  may cause
      # unwanted basic auth popups (at least Chrome & IE @ Windows).
      response.headers.delete("WWW-Authenticate")
    end

    # Base content
    @login_content = {
      # "prefix" must be set, because the same form is used for puavo-web and
      # puavo-rest, but their contents (CSS, etc.) are stored in different
      # places. This key tells the form where those resources are.
      "prefix" => "/v3/login",

      "external_service_name" => @external_service["name"],
      "service_title_override" => nil,
      "return_to" => params['return_to'] || params['return'] || nil,
      "organisation" => @organisation ? @organisation.domain : nil,
      "display_domain" => request["organisation"],
      "username_placeholder" => username_placeholder,
      "username" => params["username"],
      "error_message" => @error_message,
      "topdomain" => topdomain,
      "text_password" => t.sso.password,
      "text_login" => t.sso.login,
      "text_help" => t.sso.help,
      "text_username_help" => t.sso.username_help,
      "text_organisation_help" => t.sso.organisation_help,
      "text_developers" => t.sso.developers,
      "text_developers_info" => t.sso.developers_info,
      "support_info" => t.sso.support_info,
      "text_login_to" => t.sso.login_to
    }

    org_name = nil

    flog.info(nil, 'Trying to figure out the organisation name for this SSO request')

    if request['organisation']
      # Find the organisation that matches this request
      req_organisation = request['organisation']

      flog.info(nil, "The request includes organisation name \"#{req_organisation}\"")

      # If external domains are specified, then try doing a reverse lookup
      # (ie. convert the external domain back into an organisation name)
      if CONFIG.include?('external_domain')
        CONFIG['external_domain'].each do |name, external|
          if external == req_organisation
            flog.info(nil, "Found a reverse mapping from external domain \"#{external}\" " \
                      "to \"#{name}\", using it instead")
            req_organisation = name
            break
          end
        end
      end

      # Find the organisation
      if ORGANISATIONS.include?(req_organisation)
        # This name probably came from the reverse mapping above
        flog.info(nil, "Organisation \"#{req_organisation}\" exists, using it")
        org_name = req_organisation
      else
        # Look for LDAP host names
        ORGANISATIONS.each do |name, data|
          if data['host'] == req_organisation
            flog.info(nil, "Found a configured organisation \"#{name}\"")
            org_name = name
            break
          end
        end
      end

      unless org_name
        flog.warn(nil, "Did not find the request organisation \"#{req_organisation}\" in organisations.yml")
      end

    else
      flog.warn(nil, 'There is no organisation name in the request')
    end

    # No organisation? Is this a development/testing environment?
    unless org_name
      if ORGANISATIONS.include?('hogwarts')
        flog.info(nil, 'This appears to be a development environment, using hogwarts')
        org_name = 'hogwarts'
      end
    end

    flog.info(nil, "Final organisation name is \"#{org_name}\"")

    begin
      # Any per-organisation login screen customisations?
      customisations = ORGANISATIONS[org_name]['login_screen']
      customisations = {} unless customisations.class == Hash
    rescue StandardError => e
      customisations = {}
    end

    unless customisations.empty?
      flog.info(nil, "Organisation \"#{org_name}\" has login screen customisations enabled")
    end

    # Apply per-customer customisations
    if customisations.include?('css')
      @login_content['css'] = customisations['css']
    end

    if customisations.include?('upper_logo')
      @login_content['upper_logo'] = customisations['upper_logo']
    end

    if customisations.include?('header_text')
      @login_content['header_text'] = customisations['header_text']
    end

    if customisations.include?('service_title_override')
      @login_content['service_title_override'] = customisations['service_title_override']
    end

    if customisations.include?('bottom_logos')
      @login_content['bottom_logos'] = customisations['bottom_logos']
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

    CONFIG["external_domain"]&.each do |k, e|
      if e == org
        org = k + "." + topdomain
        break
      end
    end

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
      flog.error('sso error',
                 "organisation missing from username: #{ params['username'] }")
      render_form(t.sso.organisation_missing)
    end

    user_org = nil

    if params["username"].include?("@")
      _, user_org = params["username"].split("@")
      if Organisation.by_domain(ensure_topdomain(user_org)).nil?
        flog.info('sso error',
                  "could not find organisation for domain #{ user_org }")
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

  get "/v3/sso/developers" do
    @body = File.read("doc/SSO_DEVELOPERS.html")
    erb :developers, :layout => :layout
  end

  helpers do
    def raw(string)
      return string
    end

    def token_tag(token)
      # FIXME
    end

    def form_authenticity_token
      # FIXME
    end

  end

end
end
