
class PasswordController < ApplicationController
  before_filter :set_ldap_connection
  skip_before_filter :find_school, :require_login, :require_puavo_authorization

  # GET /password/edit
  def edit
    @user = User.new
  end

  # GET /password/own
  def own
    @user = User.new
  end

  # PUT /password
  def update

    unless params[:user][:new_password] == params[:user][:new_password_confirmation]
      raise User::UserError, I18n.t('flash.password.confirmation_failed')
    end

    unless change_user_password
      raise User::UserError, I18n.t('flash.password.invalid_login', :uid => params[:login][:uid])
    end

    respond_to do |format|
      flash[:notice] = t('flash.password.successful')
      unless params[:user][:uid]
        format.html { render :action => "own" }
      else
        format.html { render :action => "edit" }
      end
    end
  rescue User::UserError => e
    error_message_and_redirect(e)
  end

  private

  def error_message_and_redirect(message)
    flash[:alert] = message
    unless params[:user][:uid]
      redirect_to own_password_path
    else
      redirect_to password_path
    end
  end

  def change_user_password
    if @logged_in_user = User.find(:first, :attribute => "uid", :value => params[:login][:uid])
      if authenticate(@logged_in_user, params[:login][:password])
        if params[:user][:uid]
          unless @user = User.find(:first, :attribute => "uid", :value => params[:user][:uid])
            raise User::UserError, I18n.t('flash.password.invalid_user', :uid => params[:user][:uid])
          end
        else
          @user = @logged_in_user
        end

        res = Puavo.ldap_passwd(
          User.configuration[:host],
          @logged_in_user.dn,
          params[:login][:password],
          params[:user][:new_password],
          @user.dn.to_s
        )
        flog.info "ldappasswd call", res.merge(
          :user => {
            :uid => @user.uid,
            :dn => @user.dn.to_s
          },
          :bind_user => {
            :uid => @logged_in_user.uid,
            :dn => @logged_in_user.dn.to_s
          }
        )

        if res[:exit_status] != 0
          logger.warn "ldappasswd failed: #{ res.inspect }"
          raise User::UserError, I18n.t('flash.password.failed')
        end




        return true
      end
    end

    return false
  end

  def authenticate(user, password)
    result = user.bind(password) rescue false
    user.remove_connection
    return result
  end

  def set_ldap_connection
    organisation_key = Puavo::Organisation.key_by_host(request.host)
    unless organisation_key
      organisation_key = Puavo::Organisation.key_by_host("*")
    end
    organisation_key

    default_ldap_configuration = ActiveLdap::Base.ensure_configuration
    organisation = Puavo::Organisation.find(organisation_key)
    host = organisation.ldap_host
    base = organisation.ldap_base
    dn =  default_ldap_configuration["bind_dn"]
    password = default_ldap_configuration["password"]
    LdapBase.ldap_setup_connection(host, base, dn, password)
  end
end
