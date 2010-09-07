class SessionsController < ApplicationController
  before_filter :login_required, :only => :destroy

  def new
  end

  def create
    if user = User.authenticate( params[:user][:login], params[:user][:password] )
      flash[:notice] = t('flash.session.login_successful')
      session[:dn] = user.dn
      session[:password_plaintext] = params[:user][:password]

      redirect_back_or_default schools_url
    else
      flash[:notice] = t('flash.session.failed')
      render :action => :new
    end
  end

  def destroy
    # Remove dn and plaintext password values from session
    session.delete :password_plaintext
    session.delete :dn
    flash[:notice] = t('flash.session.logout_successful')
    redirect_to login_path
  end
end
