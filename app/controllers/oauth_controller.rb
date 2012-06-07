class OauthController < ApplicationController

  before_filter :set_organisation_to_session, :set_locale

  skip_before_filter :find_school
  skip_before_filter :require_puavo_authorization, :except => [:ping, :whoami]

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

    # Authorization Grant must be given only with password authentication or
    # with kerberos ticket. TODO: Kerberos ticket
    if not authentication.user_password?
      raise Puavo::AuthenticationFailed,
        "Authorization grant can be only given with User UID and password"
    end

    # Save parameters given by the Client Service
    session[:oauth_params] = params

    # No need to show anything to user if the service is trusted
    return redirect_with_authorization_code if trusted_client_service?

    # If service is not trusted show a form to user where she/he can choose to trust it
    respond_to do |format|
      format.html
    end

  end

  # POST /oauth/???
  # TODO: a route
  def handle_form_accept
    # TODO: handle cancel button
    redirect_with_authorization_code
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
      user_dn, oauth_client_server_dn)

    access_token = access_token_entry.encrypt_token(
      "host" => authentication.host,
      "base" => authentication.base
    )


    refresh_token_entry ||= RefreshToken.new(
      :puavoOAuthEduPerson => user_dn,
      :puavoOAuthClient => oauth_client_server_dn
    )

    refresh_token_entry.puavoOAuthAccessToken = access_token_entry.dn

    refresh_token = refresh_token_entry.encrypt_token(
      "host" => authentication.host,
      "base" => authentication.base
    )

    # Access Token Response http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.4
    render :json => {
      :access_token => access_token,
      :refresh_token => refresh_token,
      :token_type => "Bearer",
      :expires_in => 3600,
    }.to_json
  end

  def trusted_client_service?
    # TODO: inspect session[:oauth_params]
    true
  end

  # Redirection Endpoint http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-3.1.2
  # Authorization Request http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.1
  # Authorization Response http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.2
  def redirect_with_authorization_code
    oauth_params = session[:oauth_params]
    session.delete :oauth_params
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
