class SessionsController < ApplicationController
  before_filter :login_required, :only => [:destroy, :show]

  def new
  end

  def create
    if user = User.authenticate( params[:user][:login], params[:user][:password] ) # REST/OAuth?
      flash[:notice] = t('flash.session.login_successful')
      session[:dn] = user.dn
      session[:password_plaintext] = params[:user][:password]
      session[:user_id] = user.puavoId

      #redirect_back_or_default schools_url
      redirect_back_or_default root_path
    else
      flash[:notice] = t('flash.session.failed')
      render :action => :new
    end
  end

  def show
    @user = User.find(session[:dn])
    respond_to do |format|
      format.json  { render :json => user_to_json(@user) }
    end
  end

  def destroy
    # Remove dn and plaintext password values from session
    session.delete :password_plaintext
    session.delete :dn
    session.delete :user_id
    flash[:notice] = t('flash.session.logout_successful')
    redirect_to login_path
  end

  private

  def user_to_json(user)
    user.attributes.merge( { :managed_schools => user.managed_schools.map { |s| s.attributes } } ).to_json
  end
end
