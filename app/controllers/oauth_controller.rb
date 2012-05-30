class OauthController < ApplicationController
  before_filter :set_organisation_to_session, :set_locale

  skip_before_filter :find_school
  skip_before_filter :require_puavo_authorization
  skip_before_filter :require_login, :only => :token


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

  # POST /oauth/authorize
  # This post comes from the client server
  # Here we exchange the code with the token
  def token

    oc = OauthClient.find(:first,
      :attribute => "puavoOAuthClientId",
      :value => params["client_id"])

    # Authenticate Client Server
    authentication.configure_ldap_connection oc.dn, params["client_secret"]
    begin
      authentication.authenticate
    rescue Puavo::AuthenticationError => e
      return show_authentication_error e.message
    end

    setup_authentication # restore default authentication

    ac = AccessCode.find_by_access_code_and_client_id(
      params[:code], params[:client_id])

    redirect_uri = params[:redirect_uri]
    grant_type = params[:grant_type]

    at = AccessToken.new
    access_token_password = UUID.new.generate

    at.puavoOAuthTokenId = UUID.new.generate
    at.userPassword = access_token_password
    at.puavoOAuthEduPerson = ac.user_dn
    at.puavoOAuthClient = oc.dn

    at.save!

    access_token = token_manager.encrypt(
      at.dn.to_s,
      access_token_password,
      authentication.host,
      authentication.base
    )

    rt = RefreshToken.new
    client_secret = params[:client_secret]

    refresh_token = Base64.encode64( UUID.new.generate )
    refresh_token = refresh_token_password[1..20]
    refresh_token += Base64.encode64(client_secret)

    refresh_token_password = UUID.new.generate
    rt.puavoOAuthAccessToken = at.dn
    rt.puavoOAuthTokenId = UUID.new.generate
    rt.userPassword = refresh_token_password
    rt.puavoOAuthEduPerson = ac.user_dn
    rt.puavoOAuthClient = client_dn

    rt.save!

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
    # get new accesstoken by using refresh_token and user credentials
    client_id = params[:client_id]
    client_secret = params[:client_secret]
    refresh_token = params[:refresh_token]
    
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

end
