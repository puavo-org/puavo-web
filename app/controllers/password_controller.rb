class UserNotFound < StandardError; end
class TooManySentTokenRequest < StandardError; end
class RestConnectionError < StandardError; end
class PasswordConfirmationFailed < StandardError; end
class TokenLifetimeHasExpired < StandardError; end

class PasswordController < ApplicationController
  before_action :set_ldap_connection
  skip_before_action :find_school, :require_login, :require_puavo_authorization

  # GET /password/edit
  def edit
    @user = User.new
    @gsuite = false

    @changing = params[:changing] || nil
    @changed = params[:changed] || nil
    session[:changing] = @changing
    session[:changed] = @changed

    url = external_pw_mgmt_url

    if !url.nil? && !url.empty?
      @gsuite = true
    end

  end

  # GET /password/own
  def own
    @user = User.new
    @gsuite = false

    @changing = params[:changing] || nil
    session[:changing] = @changed

    url = external_pw_mgmt_url

    if !url.nil? && !url.empty?
      @gsuite = true
    end
  end

  # PUT /password
  def update

    @changing = params[:login][:uid] || session[:changing] || nil
    @changed = params[:user][:uid] || session[:changed] || nil

    if params[:login][:uid].empty?
      raise User::UserError, I18n.t('flash.password.incomplete_form')
    end

    unless params[:user][:new_password] == params[:user][:new_password_confirmation]
      raise User::UserError, I18n.t('flash.password.confirmation_failed')
    end

    unless change_user_password
      raise User::UserError, I18n.t('flash.password.invalid_login', :uid => params[:login][:uid])
    end

    session[:changing] = nil
    session[:changed] = nil
    @changing = nil
    @changed = nil

    respond_to do |format|
      flash.now[:notice] = t('flash.password.successful')
      unless params[:user][:uid]
        format.html { render :action => "own" }
      else
        format.html { render :action => "edit" }
      end
    end
  rescue User::UserError => e
    error_message_and_redirect(e.message)
  end

  # GET /password/forgot
  def forgot

  end

  # PUT /password/forgot
  def forgot_send_token

    user = User.find(:first, :attribute => "mail", :value =>  params[:forgot][:email])

    send_token_url = password_management_host + "/password/send_token"

    raise UserNotFound if not user

    db = redis_connect

    raise TooManySentTokenRequest if db.get(user.puavoId)

    db.set(user.puavoId, true)
    db.expire(user.puavoId, 300)

    rest_response = HTTP.headers(:host => current_organisation_domain,
                                      "Accept-Language" => locale)
      .post(send_token_url,
            :params => { :username => user.uid })

    raise RestConnectionError if rest_response.status != 200

    respond_to do |format|
      flash[:message] = I18n.t('password.successfully.send_token')
      format.html { redirect_to successfully_password_path(:message => "send_token") }
    end
  rescue UserNotFound
    flash.now[:alert] = I18n.t('flash.password.email_not_found', :email => params[:forgot][:email])
    render :action => "forgot"
  rescue TooManySentTokenRequest
    flash.now[:alert] = I18n.t('flash.password.too_many_sent_token_request')
    render :action => "forgot"
  rescue RestConnectionError
    flash.now[:alert] = I18n.t('flash.password.connection_failed', :email => params[:forgot][:email])
    render :action => "forgot"
  end

  # GET /password/:jwt/reset
  def reset
  end

  # PUT /password/:jwt/reset
  def reset_update

    raise PasswordConfirmationFailed if params[:reset][:password] != params[:reset][:password_confirmation]

    change_password_url = password_management_host + "/password/change/#{ params[:jwt] }"

    rest_response = HTTP.headers(:host => current_organisation_domain,
                                      "Accept-Language" => locale)
      .put(change_password_url,
           :params => { :new_password => params[:reset][:password] })

    if rest_response.status == 404 &&
        JSON.parse(rest_response.body.readpartial)["error"] == "Token lifetime has expired"
      raise TokenLifetimeHasExpired
    end

    respond_to do |format|
      if rest_response.status == 200
        flash[:message] = I18n.t('password.successfully.update')
        format.html { redirect_to successfully_password_path(:message => "update") }
      else
        flash[:alert] = I18n.t('flash.password.can_not_change_password')
        format.html { redirect_to reset_password_path }
      end
    end
  rescue PasswordConfirmationFailed
    flash.now[:alert] = I18n.t('flash.password.confirmation_failed')
    render :action => "reset"
  rescue TokenLifetimeHasExpired
    flash[:alert] = I18n.t('flash.password.token_lifetime_has_expired')
    redirect_to forgot_password_path
  end

  def successfully

  end

  private

  def error_message_and_redirect(message)
    flash.now[:alert] = message
    @user = User.new
    unless params[:user][:uid]
      render :action => "own"
    else
      render :action => "edit"
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

        url = external_pw_mgmt_url
        role = external_pw_mgmt_role

        if !url.nil? && !url.empty?
          if (role.nil? || role.empty?) || (!role.nil? && !role.empty? && @user.puavoEduPersonAffiliation.include?(role))
            # External password management (read: G Suite integration) is enabled and this
            # user matches the required role, so validate the new password against Google's
            # requirements.
            new_password = params[:user][:new_password]

            if new_password.size < 8
              raise User::UserError, I18n.t("activeldap.errors.messages.password_too_short")
            elsif new_password[0] == ' ' || new_password[-1] == ' '
              raise User::UserError, I18n.t("activeldap.errors.messages.password_whitespace")
            elsif !new_password.ascii_only?
              raise User::UserError, I18n.t("activeldap.errors.messages.password_ascii_only")
            end
          else
            # An external password management URL has been specified, but this user did not
            # pass the role check, so change the password but don't synchronise it
            url = nil
          end
        end

        res = Puavo.ldap_passwd(
          User.configuration[:host],
          @logged_in_user.dn,
          params[:login][:password],
          params[:user][:new_password],
          @user.dn.to_s,
          url
        )
        flog.info "ldappasswd call", res.merge(
          :from => "password controller",
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

  def current_organisation_domain
    LdapOrganisation.first.puavoDomain
  end

  def redis_connect
    db = Redis::Namespace.new(
      "puavo:password_management:send_token",
      :redis => REDIS_CONNECTION
    )
  end
end
