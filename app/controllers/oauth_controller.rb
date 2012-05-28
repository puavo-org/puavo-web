class OauthController < ApplicationController
  before_filter :set_organisation_to_session, :set_locale

  skip_before_filter :find_school


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
    at = AccessToken.new
    rt = RefreshToken.new
    at.userPassword = "secret"
    at.save
    # OauthClient.find()

    # at.dn, "secret"
    logger.debug "\n\nAUTHORIZE POST\n\n" + params.inspect
    render :text => 'testi'
  end

  # POST /oauth/token
  def refresh_token


    # get new accesstoken by using refresh_token and user credentials
  end


  def trusted_client_service?
    # TODO: inspect session[:oauth_params]
    false
  end

  def redirect_with_access_code
    oauth_params = session[:oauth_params]
    session.delete :oauth_params
    raise "OAuth params are not in the session" if oauth_params.nil?

    code = UUID.new.generate

    access_code = AccessCode.create(
      :access_code => code,
      :client_id =>
      oauth_params[:client_id],
      :user_dn => current_user.dn.to_s
    )

    url = url_for(:code => code, :state => oauth_params[:state] )
    redirect_to oauth_params[:redirect_uri] + url
  end


end
