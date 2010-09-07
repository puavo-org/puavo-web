class PasswordController < ApplicationController
  before_filter :login_required, :except => [:edit, :update]

  # GET /:school_id/password
  def edit
    @user = User.new
  end

  # PUT /:school_id/password
  def update
    if @user = User.authenticate(params[:login][:username], params[:login][:password])
      # Using user's dn and password for ldap conenction when change ldap password
      session[:dn] = @user.dn
      session[:password_plaintext] = params[:login][:password]
      ldap_setup_connection
    else
      raise "Couldn't find user"
    end

    respond_to do |format|
      if @user.update_attributes(params[:user])
        flash[:notice_css_class] = "notice"
        flash[:notice] = t('flash.password.successful')
      else
        flash[:notice_css_class] = "notice_error"
        flash[:notice] = t('flash.password.failed')
      end
      session.delete :password_plaintext
      session.delete :dn
      format.html { render :action => "edit" }
    end
  rescue User::PasswordChangeFailed => e
    logger.debug "Execption: " + e.to_s
    error_message_and_redirect(e)
  rescue Exception => e
    logger.debug "Execption: " + e.to_s
    error_message_and_redirect(t('flash.password.invalid_login'))
  end

  private

  def error_message_and_redirect(message)
    flash[:notice_css_class] = "notice_error"
    flash[:notice] = message
    redirect_to password_path
  end
end
