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

    url = external_pw_mgmt_url

    if !url.nil? && !url.empty?
      @gsuite = true
    end

  end

  # GET /password/own
  def own
    @user = User.new
    @gsuite = false

    url = external_pw_mgmt_url

    if !url.nil? && !url.empty?
      @gsuite = true
    end
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
    flash[:alert] = message
    unless params[:user][:uid]
      redirect_to own_password_path
    else
      redirect_to password_path
    end
  end

  def external_login(username, password)
    begin
      external_login_status = rest_proxy(username, password) \
                                .post('/v3/external_login/auth').parse
      raise 'Bad structure in /v3/external_login/auth response' \
        unless external_login_status.kind_of?(Hash)
      raise 'Status string missing in /v3/external_login/auth structure' \
        unless external_login_status['status'].kind_of?(String)

      case external_login_status['status']
      when PuavoRest::ExternalLoginStatus::BADUSERCREDS,
           PuavoRest::ExternalLoginStatus::CONFIGERROR,
           PuavoRest::ExternalLoginStatus::UPDATED_BUT_FAIL,
           PuavoRest::ExternalLoginStatus::UPDATEERROR
        return :external_login_failed
      when PuavoRest::ExternalLoginStatus::UNAVAILABLE
        return :external_login_unavailable
      when PuavoRest::ExternalLoginStatus::NOCHANGE,
           PuavoRest::ExternalLoginStatus::UPDATED
        return :external_login_ok
      end

    rescue StandardError => e
      logger.error("error calling /v3/users/password: #{ e.message }")
      return :external_login_failed
    end

    # PuavoRest::ExternalLoginStatus::NOTCONFIGURED
    # intentionally ends up here and this is good.
    return nil
  end

  def change_user_password
    url = external_pw_mgmt_url
    stricter_password_requirements = !external_pw_mgmt_role.to_s.empty? \
                                       && !url.to_s.empty?
    if stricter_password_requirements then
      # External password management (read: G Suite integration) is enabled
      # for this organisation (though not necessarily for this specific user),
      # so validate the password against Google's requirements.
      new_password = params[:user][:new_password]

      if new_password.size < 8 then
        raise User::UserError,
              I18n.t('activeldap.errors.messages.password_too_short')
      end
      if new_password[0] == ' ' || new_password[-1] == ' ' then
        raise User::UserError,
              I18n.t('activeldap.errors.messages.password_whitespace')
      end
      if !new_password.ascii_only? then
        raise User::UserError,
              I18n.t('activeldap.errors.messages.password_ascii_only')
      end
    else
      url = nil
    end

    external_login_status = external_login(params[:login][:uid],
                                           params[:login][:password])

    if external_login_status then
      case external_login_status
        when :external_login_failed
          # XXX is this error message okay?
          raise User::UserError, I18n.t('flash.password.invalid_user',
                                        :uid => params[:user][:uid])
        when :external_login_ok
          true    # this is okay
        else
          # XXX is this error message okay?
          raise User::UserError, I18n.t('flash.password.failed')
      end
    end

    @logged_in_user = User.find(:first,
                                :attribute => 'uid',
                                :value     => params[:login][:uid])
    return false unless @logged_in_user \
                          && authenticate(@logged_in_user,
                                          params[:login][:password])

    @user = @logged_in_user
    if params[:user][:uid] then
      @user = User.find(:first,
                        :attribute => 'uid',
                        :value     => params[:user][:uid])
    end

    unless @user || external_login_status then
      raise User::UserError, I18n.t('flash.password.invalid_user',
                                    :uid => params[:user][:uid])
    end

    rest_params = {
                    :bind_dn              => @logged_in_user.dn.to_s,
                    :bind_dn_password     => params[:login][:password],
                    :host                 => User.configuration[:host],
                    :new_password         => params[:user][:new_password],
                    :target_user_username => params[:user][:uid],
                  }
    if @user then
      rest_params[:target_user_dn] = @user.dn.to_s
    else
      rest_params[:upstream_only]        = 'true'
    end
    rest_params[:external_pw_mgmt_url] = url if url

    res = rest_proxy.put('/v3/users/password', :params => rest_params).parse
    res = {} unless res.kind_of?(Hash)

    if res['exit_status'] == 0 && !@user && external_login_status then
      # ignore return code, try this only for side effect (possibly creates
      # new user to Puavo, and should always sync password):
      external_login(params[:user][:uid], params[:user][:new_password])
      @user = User.find(:first,
                        :attribute => 'uid',
                        :value     => params[:login][:uid])
    end

    flog.info('rest call to PUT /v3/users/password', res.merge(
      :from => 'password controller',
      :user => {
        :dn  => (@user ? @user.dn.to_s : '[dn unknown]'),
        :uid => (@user ? @user.uid     : '[uid unknown]'),
      },
      :bind_user => {
        :dn  => @logged_in_user.dn.to_s,
        :uid => @logged_in_user.uid,
      }
    ))

    if res['exit_status'] != 0 then
      logger.warn "rest call to PUT /v3/users/password failed: #{ res.inspect }"
      raise User::UserError, I18n.t('flash.password.failed')
    end

    return true
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
