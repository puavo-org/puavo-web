class PasswordController < ApplicationController
  skip_before_filter :ldap_setup_connection, :find_school, :login_required

  # GET /:school_id/password
  def edit
    @user = User.new
  end

  # PUT /:school_id/password
  def update

    unless params[:user][:new_password] == params[:user][:new_password_confirmation]
      raise I18n.t('flash.password.confirmation_failed')
    end

    unless change_user_password
      raise I18n.t('flash.password.invalid_login', :uid => params[:login][:uid])
    end

    respond_to do |format|
      flash[:notice] = t('flash.password.successful')
      format.html { render :action => "edit" }
    end
  rescue User::PasswordChangeFailed => e
    logger.debug "Execption: " + e.to_s
    error_message_and_redirect(e)
  rescue Exception => e
    logger.debug "Execption: " + e.to_s
    error_message_and_redirect(e)
  end

  private

  def error_message_and_redirect(message)
    flash[:notice] = message
    redirect_to password_path
  end

  def change_user_password
    default_ldap_configuration = ActiveLdap::Base.ensure_configuration
    host = session[:organisation].ldap_host
    base = session[:organisation].ldap_base
    dn =  default_ldap_configuration["bind_dn"]
    password = default_ldap_configuration["password"]
    LdapBase.ldap_setup_connection(host, base, dn, password)

    if @logged_in_user = User.find(:first, :attribute => "uid", :value => params[:login][:uid])
      if ( @logged_in_user.bind(params[:login][:password]) rescue nil )
        if @user = User.find(:first, :attribute => "uid", :value => params[:user][:uid])
          system( 'ldappasswd', '-x', '-Z',
                  '-h', User.configuration[:host],
                  '-D', @logged_in_user.dn.to_s,
                  '-w', params[:login][:password],
                  '-s', params[:user][:new_password],
                  @user.dn.to_s )
          if $?.exitstatus != 0
            raise User::PasswordChangeFailed, I18n.t('flash.password.failed')
          end
          return true 
        else
          raise I18n.t('flash.password.invalid_user', :uid => params[:user][:uid])
        end
      end
    end

    return false
  end
end
