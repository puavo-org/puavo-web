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
    # TODO: handle cancel button
    redirect_with_access_code
  end

  # POST /oauth/authorize
  def token 
    logger.debug "\n\nAUTHORIZE POST\n\n" + params.inspect
    render :text => 'testi'
    # this post comes from the client
    # Here we exchange the code with the token
  end

  # POST /oauth/????
  def refresh_token
    # get new accesstoken by using refresh_token and user credentials
  end


  def trusted_client_service?
    # TODO: inspect session[:oauth_params]
    false
  end

  def redirect_with_access_code
    code = UUID.new.generate 
    access_code = AccessCode.create( :access_code => code, :client_id => params[:client_id], :user_dn => current_user.dn.to_s)
    # TODO: must consider if the redirect_url should be verified against the database
    # render :text => params.inspect
    redirect_to params[:redirect_uri] + url_for(:jee => "juu", :foo => "foobar")
  end


end
