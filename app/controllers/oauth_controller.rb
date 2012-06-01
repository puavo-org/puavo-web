class OauthController < ApplicationController

  before_filter :set_organisation_to_session, :set_locale

  skip_before_filter :find_school
  skip_before_filter :require_puavo_authorization, :except => [:ping, :whoami]

  class InvalidOAuthRequest < UserError
  end

  rescue_from Puavo::AuthenticationFailed do |e|
    show_authentication_error e.message
  end



  # GET /oauth/authorize
  def authorize
    # Save parameters given by the Client Service
    session[:oauth_params] = params

    # No need to show anything to user if the service is trusted
    return redirect_with_access_code if trusted_client_service?

    # If service is not trusted show a form to user where she/he can choose to trust it
    respond_to do |format|
      format.html
    end

  end

  # POST /oauth/???
  # TODO: a route
  def handle_form_accept
    # TODO: handle cancel button
    redirect_with_access_code
  end

  # http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-3.2
  #
  # POST /oauth/authorize
  # This post comes from the client server
  # Here we exchange the code with the token
  def token

    if not authentication.oauth_client?
      raise InvalidOAuthRequest, "Bad OAuth Client credentials"
    end

    # Authenticated previously. Just get the client id here.
    client_id = authenticate_with_http_basic { |username, password| username }

    access_code = AccessCode.find_by_access_code_and_client_id(
      params[:code], client_id)

    if access_code.nil?
      raise InvalidOAuthRequest "Cannot find Authorization Grant"
    end


    access_token, refresh_token = create_tokens access_code.user_dn, authentication.dn

    redirect_uri = params[:redirect_uri]
    grant_type = params[:grant_type]


    token_hash = {
         :access_token => access_token,
         :token_type => "Bearer",
         :expires_in => 3600,
         :refresh_token => refresh_token
    }

    render :json => token_hash.to_json
  end

  # POST /oauth/token
  def refresh_token

    if not authentication.oauth_client?
      raise InvalidOAuthRequest, "Bad OAuth Client credentials: #{ authentication.dn }"
    end

    # get new accesstoken by using refresh_token and user credentials
    refresh_token_dn, password = token_manager.decrypt params[:refresh_token]

    # Authenticate Refresh Token
    authentication.configure_ldap_connection refresh_token_dn, password
    authentication.authenticate
    setup_authentication


    refresh_token_entry = RefreshToken.find(refresh_token_dn)
    user_dn = refresh_token_entry.puavoOAuthEduPerson

    access_token, refresh_token = create_tokens user_dn, authentication.dn

    token_hash = {
         :access_token => access_token,
         :token_type => "Bearer",
         :expires_in => 3600,
         :refresh_token => refresh_token
    }

    render :json => token_hash.to_json
  end

  def create_tokens( user_dn, oauth_client_server_dn )
    access_token_entry = AccessToken.new
    access_token_password = UUID.new.generate

    access_token_entry.puavoOAuthTokenId = UUID.new.generate
    access_token_entry.userPassword = access_token_password
    access_token_entry.puavoOAuthEduPerson = user_dn
    access_token_entry.puavoOAuthClient = oauth_client_server_dn

    access_token_entry.save!

    access_token = token_manager.encrypt(
      access_token_entry.dn.to_s,
      access_token_password,
      authentication.host,
      authentication.base
    )

    refresh_token_entry = RefreshToken.new
    refresh_token_password = UUID.new.generate


    refresh_token_entry.puavoOAuthAccessToken = access_token_entry.dn
    refresh_token_entry.puavoOAuthTokenId = UUID.new.generate
    refresh_token_entry.userPassword = refresh_token_password
    refresh_token_entry.puavoOAuthEduPerson = user_dn
    refresh_token_entry.puavoOAuthClient = oauth_client_server_dn

    refresh_token_entry.save!

    refresh_token = token_manager.encrypt(
      refresh_token_entry.dn.to_s,
      refresh_token_password,
      authentication.host,
      authentication.base
    )

    return access_token, refresh_token
  end

  def trusted_client_service?
    # TODO: inspect session[:oauth_params]
    true
  end

  def redirect_with_access_code
    oauth_params = session[:oauth_params]
    session.delete :oauth_params
    raise "OAuth params are not in the session" if oauth_params.nil?

    code = UUID.new.generate

    access_code = AccessCode.create(
      :access_code => code,
      :client_id => oauth_params[:client_id],
      :user_dn => current_user.dn.to_s
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

end
