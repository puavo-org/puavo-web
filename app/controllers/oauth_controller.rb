class OauthController < ApplicationController
  layout nil

  helper_method [:client_name, :trusted_client?]

  skip_before_filter :find_school
  skip_before_filter :require_login, :only => [:authorize, :authorize_post]
  skip_before_filter :require_puavo_authorization


  class InvalidOAuthRequest < UserError
    attr_accessor :code
    def initialize(message, code)
      super message
      @code = code || "unknown_error"
    end
  end

  rescue_from Puavo::AuthenticationFailed do |e|
    show_authentication_error "authentication_error", e.message
  end

  rescue_from InvalidOAuthRequest do |e|
    # Error Response http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-5.2
    show_authentication_error e.code, e.message
  end



  # GET /oauth/authorize
  # Authorization Endpoint http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-3.1
  def authorize
    # TODO: Kerberos

    # Save parameters given by the Client Service
    session[:oauth_params] = params

    # No need to show anything to user if the service is trusted
    if trusted_client? # && kerberos?
      return redirect_with_authorization_code
    end

    return render_login_form
  end

  @@towns = YAML.load_file("#{Rails.root}/config/towns.yml")["towns"]

  def render_login_form
    @organisations = Puavo::Organisation.all.map do |k, v|
      [v["name"], k]
    end

    @@towns.each do |name|
      @organisations.push [name, name.downcase]
    end

    @client_name = "Tuki - Zendesk"
    @client_logo = "http://cdn.zendesk.com/images/zendesk-logo.png"

    render :action => "authorize"
  end

  # POST /oauth/authorize
  def authorize_post

    if params[:cancel]
      return redirect_to session[:oauth_params][:redirect_uri]
    end

    data = params["oauth"]

    [:uid, :password].each do |key|
      if data[key].nil? || data[key].empty?
        return render_login_form
      end
    end

    begin
      perform_login(
        :uid => data[:uid],
        :password => data[:password],
        :organisation_key => params[:organisation_key]
      )
    rescue Puavo::AuthenticationError => e
      flash[:notice] = t('flash.session.failed')
      return render_login_form
    end

    redirect_with_authorization_code
  end

  def trusted_client?
    # TODO: inspect session[:oauth_params]
    false
  end

  def client_name
    # TODO: query human readable name
    session[:oauth_params][:client_id]
  end

  # POST /oauth/token
  # Token Endpoint http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-3.2
  def token

    if not authentication.oauth_client_server?
      raise InvalidOAuthRequest, "Bad OAuth Client credentials"
    end

    # Authenticated previously. Just get the client id here.
    client_id = authenticate_with_http_basic { |username, password| username }
    oauth_client_server_dn = authentication.dn
    user_dn = nil

    # Access Token Request http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.3
    if params["grant_type"] == "authorization_code"
      authorization_code = AuthorizationCode.find_by_code_and_client_id(
        params[:code], client_id)

      if authorization_code.nil?
        raise InvalidOAuthRequest "Cannot find Authorization Grant"
      end

      if authorization_code.redirect_uri != params[:redirect_uri]
        raise InvalidOAuthRequest, "redirect_uri does not match to redirect_uri given in authorization grant"
      end

      user_dn = authorization_code.user_dn

      begin
        authorization_code.consume
      rescue AuthorizationCode::Expired => e
        raise InvalidOAuthRequest.new "Authorization Code has expired", "invalid_grant"
      end


    # Refreshing an Access Token http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-6
    elsif params["grant_type"] == "refresh_token"

      begin

        refresh_token_entry = nil
        RefreshToken.find_and_validate(params[:refresh_token]) do |token, entry|
          authentication.test_bind token[:dn], token[:password]
          refresh_token_entry = entry
          user_dn = entry.puavoOAuthEduPerson
        end

      rescue RefreshToken::Expired => e
        raise InvalidOAuthRequest.new e.message, "invalid_grant"
      end


    else
      raise InvalidOAuthRequest "grant_type is missing"
    end


    access_token_entry = AccessToken.find_or_create(
      user_dn, oauth_client_server_dn, authentication.scope)

    access_token = access_token_entry.encrypt_token(
      "organisation_key" => authentication.organisation_key
    )


    refresh_token_entry ||= RefreshToken.new(
      :puavoOAuthEduPerson => user_dn,
      :puavoOAuthClient => oauth_client_server_dn
    )

    refresh_token_entry.puavoOAuthAccessToken = access_token_entry.dn

    refresh_token = refresh_token_entry.encrypt_token(
      "organisation_key" => authentication.organisation_key
    )

    # Access Token Response http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.4
    render :json => {
      :access_token => access_token,
      :refresh_token => refresh_token,
      :token_type => "Bearer",
      :expires_in => AccessToken::LIFETIME,
    }.to_json
  end


  # Redirection Endpoint http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-3.1.2
  # Authorization Request http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.1
  # Authorization Response http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.2
  def redirect_with_authorization_code

    # Authorization Grant must be given only with password authentication or
    # with kerberos ticket.
    if not authentication.user_password?
      raise Puavo::AuthenticationFailed,
        "Authorization grant can be only given with User UID and password"
    end

    oauth_params = session[:oauth_params]
    session[:oauth_params] = nil
    raise "OAuth params are not in the session" if oauth_params.nil?
    # TODO: Raise if oauth_params[:redirect_uri] is missing?
    # It's optional in the RFC but do we require it?

    code = generate_nonsense

    authorization_code = AuthorizationCode.create(
      :code => code,
      :client_id => oauth_params[:client_id],
      :user_dn => current_user.dn.to_s,
      :redirect_uri => oauth_params[:redirect_uri]
    )

    # TODO: delete session
    url = { :code => code, :state => oauth_params[:state]  }.to_query
    redirect_to oauth_params[:redirect_uri] + '?' + url
  end

  # GET/POST /oauth/ping
  def ping
    render :json => {
      :method => request.method,
      :msg => "pong"
    }.to_json
  end

  # GET/POST /oauth/whoami
  def whoami
    render :json => current_user.to_json
  end

  private

  def generate_nonsense
    logger.warn "DEPRECATED generate_nonsense"
    UUID.new.generate
  end

end
