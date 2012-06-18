class SessionsController < ApplicationController
  layout 'sessions'
  skip_before_filter :require_puavo_authorization
  skip_before_filter :require_login

  def new
    # Puavo logins require always a hostname
    if request.host.match /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/
      render :text => "Host is missing", :status => 406
    end
  end

  def create
    session[:uid] = params[:user][:uid]
    session[:password_plaintext] = params[:user][:password]
    session[:login_flash] = t('flash.session.login_successful')
    redirect_back_or_default root_path
  end

  def show
    @user = User.find(session[:dn])
    respond_to do |format|
      format.json  { render :json => @user.to_json(:methods => :managed_schools) }
    end
  end

  def destroy
    # Remove dn and plaintext password values from session
    session.delete :password_plaintext
    session.delete :uid
    flash[:notice] = t('flash.session.logout_successful')
    redirect_to login_path
  end
end
