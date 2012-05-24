class SessionsController < ApplicationController
  layout 'sessions'
  before_filter :require_login, :only => [:destroy, :show]

  def new
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
