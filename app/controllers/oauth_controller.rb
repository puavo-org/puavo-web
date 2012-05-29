class OauthController < ApplicationController
  before_filter :set_organisation_to_session, :set_locale

  skip_before_filter :find_school
  skip_before_filter :require_puavo_authorization


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


  # POST /oauth/authorize
  def code
    redirect_with_access_code
  end

  # POST /oauth/authorize
  def token
    # this post comes from the client
    # Here we exchange the code with the token
    ac = AccessCode.find_by_access_code_and_client_id_and_client_secret( 
       :access_code => params[:code], 
       :client_id => params[:client_id], 
       :client_secret => params[:client_secret]
    )
    
    redirect_uri = params[:redirect_uri]
    grant_type = params[:grant_type]

    at = AccessToken.new
    # rt = RefreshToken.new
    at.userPassword = "secret"
    # generate userPassword i.e. with UUID
    at.save
    # OauthClient.find()
    token_hash = {
         :access_token => at.token,
         :token_type => "Bearer",
         :expires_in => 3600,
         :refresh_token => nil
    }

    render :text, token_hash.to_json
    # at.dn, "secret"
  end

  # POST /oauth/token
  def refresh_token


    # get new accesstoken by using refresh_token and user credentials
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

  def ping
    render :json => {
      :method => request.method,
      :msg => "pong"
    }.to_json
  end

end
