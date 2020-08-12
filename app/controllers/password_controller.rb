class UserNotFound < StandardError; end
class TooManySentTokenRequest < StandardError; end
class RestConnectionError < StandardError; end
class PasswordConfirmationFailed < StandardError; end
class TokenLifetimeHasExpired < StandardError; end

class PasswordController < ApplicationController
  include Puavo::Integrations

  before_action :set_ldap_connection
  skip_before_action :find_school, :require_login, :require_puavo_authorization

  # GET /password/own
  # "Change your own password" form
  def own
    @user = User.new

    @changing = params.fetch(:changing, '')
    @changed = params.fetch(:changed, '')
    setup_language(params.fetch(:lang, ''))

    @expired = (params[:password_expired] == 'true')

    setup_customisations()
  end

  # GET /password/edit
  # "Change someone else's password" form
  def edit
    @user = User.new

    @changing = params.fetch(:changing, '')
    @changed = params.fetch(:changed, '')
    setup_language(params.fetch(:lang, ''))
    setup_customisations()
  end

  def filter_multiple_attempts(username, request_id)
      db = Redis::Namespace.new("puavo:password_management:attempt_counter", :redis => REDIS_CONNECTION)

      # if the username key exists in the database, then there have been multiple attempts lately
      if db.get(username) == "true"
        logger.error "[#{request_id}] (#{Time.now}) Too many change attempts for user \"#{username}\", request rejected"

        # must setup these or the form breaks
        setup_language(params.fetch(:lang, ''))
        setup_customisations()
        @changing = username

        raise UserError, I18n.t('flash.password.too_many_attempts')
        return
      end

      # store the username with automatic expiration in 10 seconds
      db.set(username, true, :px => 10000, :nx => true)
  end

  # PUT /password
  # "Change your own password" and "Change someone else's password" are both processed here
  def update

    ip = "REMOTE_ADDR=\"#{request.env['REMOTE_ADDR']}\" " \
         "REMOTE_HOST=\"#{request.env['REMOTE_HOST']}\" " \
         "REQUEST_URI=\"#{request.env['REQUEST_URI']}\""

    # This request ID is logged everywhere and shown to the user
    # in case something goes wrong. It can be then grepped from
    # the logs to determine why the password change failed.
    request_id = generate_synchronous_call_id()

    if params['login']['uid'] && !params['user']['uid']
      logger.info "[#{request_id}] (#{Time.now}) User \"#{params['login']['uid']}\" " \
                  "in organisation \"#{@organisation_name}\" " \
                  "is trying to change their password, #{ip}"
      filter_multiple_attempts(params['login']['uid'], request_id)
      mode = :own
    else
      logger.info "[#{request_id}] (#{Time.now}) User \"#{params['login']['uid']}\" " \
                  "is trying to change the password of user \"#{params['user']['uid']}\" " \
                  "in organisation \"#{@organisation_name}\", #{ip}"
      mode = :other
    end

    # If the field on the form was filled in, use the value from it,
    # otherwise take the value from the URL
    if params.include?(:login)
      @changing = params[:login][:uid] || ''
    else
      @changing = params.fetch(:changing, '')
    end

    # Same here
    if params.include?(:user)
      @changed = params[:user][:uid] || ''
    else
      @changed = params.fetch(:changed, '')
    end

    setup_language(params.fetch(:lang, ''))
    setup_customisations()

    if params[:login][:uid].empty?
      logger.error("[#{request_id}] The password form was not fully filled in")
      raise UserError, I18n.t('flash.password.incomplete_form')
    end

    unless params[:user][:new_password] == params[:user][:new_password_confirmation]
      logger.error("[#{request_id}] Password and password confirmation do not match")
      raise UserError, I18n.t('flash.password.confirmation_failed')
    end

    unless change_user_password(mode, request_id)
      raise UserError, I18n.t('flash.password.invalid_login', :uid => params[:login][:uid])
    end

    # remember the changer's username, but not the target username
    @changed = ''

    respond_to do |format|
      logger.error("[#{request_id}] Password successfully changed")

      flash.now[:notice] = t('flash.password.successful')

      unless params[:user][:uid]
        format.html { render :action => "own" }
      else
        format.html { render :action => "edit" }
      end
    end
  rescue UserError => e
    error_message_and_redirect(e.message)
  end

  # GET /password/forgot
  # "I forgot my password" form that asks for an email address
  def forgot
    setup_language(params.fetch(:lang, ''))
    setup_customisations()
  end

  # PUT /password/forgot
  # Send the password reset token to the specified email address
  def forgot_send_token
    setup_language(params.fetch(:lang, ''))
    setup_customisations()

    if params[:forgot].empty? || params[:forgot][:email].empty?
      flash[:alert] = I18n.t('password.forgot.description')
      redirect_to forgot_password_path
      return
    end

    user = User.find(:first, :attribute => "mail", :value =>  params[:forgot][:email])

    send_token_url = password_management_host + "/password/send_token"

    raise UserNotFound if not user

    db = redis_connect

    raise TooManySentTokenRequest if db.get(user.puavoId)

    rest_response = HTTP.headers(:host => current_organisation_domain,
                                      "Accept-Language" => locale)
      .post(send_token_url,
            :params => { :username => user.uid })

    raise RestConnectionError if rest_response.status != 200

    db.set(user.puavoId, true)
    db.expire(user.puavoId, 300)

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
  # Password reset form
  def reset
    setup_language(params.fetch(:lang, ''))
    setup_customisations()
  end

  # PUT /password/:jwt/reset
  # Reset the user's password
  def reset_update

    setup_language(params.fetch(:lang, ''))
    setup_customisations()

    raise PasswordConfirmationFailed if params[:reset][:password] != params[:reset][:password_confirmation]

    change_password_url = password_management_host + "/password/change/#{ params[:jwt] }"

    rest_response = HTTP.headers(:host => current_organisation_domain,
                                      "Accept-Language" => locale)
      .put(change_password_url,
           :json => { :new_password => params[:reset][:password] })

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

  # "Your password has been reset" form
  def successfully

  end

  private

  def error_message_and_redirect(message)
    flash.now[:alert] = message
    @user = User.new

    setup_language(params.fetch(:lang, ''))
    setup_customisations()

    unless params[:user][:uid]
      render :action => "own"
    else
      render :action => "edit"
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

  def change_user_password(mode, request_id)
    # must use -1 because password forms use global requirements
    case get_school_password_requirements(@organisation_name, -1)
      when 'Google'
        # Validate the password against Google's requirements.
        new_password = params[:user][:new_password]

        if new_password.size < 8 then
          logger.error("[#{request_id}] The new password does not meet the requirements")
          raise UserError,
                I18n.t('activeldap.errors.messages.gsuite_password_too_short')
        end
        if new_password[0] == ' ' || new_password[-1] == ' ' then
          logger.error("[#{request_id}] The new password does not meet the requirements")
          raise UserError,
                I18n.t('activeldap.errors.messages.gsuite_password_whitespace')
        end
        if !new_password.ascii_only? then
          logger.error("[#{request_id}] The new password does not meet the requirements")
          raise UserError,
                I18n.t('activeldap.errors.messages.gsuite_password_ascii_only')
        end
      when 'oulu_ad'
        # Validate the password to contain at least eight characters
        new_password = params[:user][:new_password]
        if new_password.size < 8 then
          logger.error("[#{request_id}] The new password does not meet the requirements")
          raise UserError,
                I18n.t('activeldap.errors.messages.oulu_ad_password_too_short')
        end

        # There are other limitations here too, but we cannot check for them
      when 'SixCharsMin'
        # Validate the password to contain at least six characters.
        new_password = params[:user][:new_password]
        if new_password.size < 6 then
          logger.error("[#{request_id}] The new password does not meet the requirements")
          raise UserError,
                I18n.t('activeldap.errors.messages.sixcharsmin_password_too_short')
        end
      when 'SevenCharsMin'
        # Validate the password to contain at least seven characters.
        # TODO: This is inflexible and too repetitive. We need a better system
        # for validating and enforcing password requirements.
        new_password = params[:user][:new_password]
        if new_password.size < 7 then
          logger.error("[#{request_id}] The new password does not meet the requirements")
          raise UserError,
                I18n.t('activeldap.errors.messages.sevencharsmin_password_too_short')
        end
    end

    login_uid = params[:login][:uid]

    # if the username(s) contain the domain name, strip it out
    # must use -1 because password forms use global requirements
    customisations = get_school_password_form_customisations(@organisation_name, -1)
    domain = customisations[:domain]

    if domain && login_uid.end_with?(domain)
      login_uid.remove!(domain)
    end

    external_login_status = external_login(login_uid, params[:login][:password])
    logger.warn "[#{request_id}] external_login_status: \"#{external_login_status}\""

    if external_login_status then
      case external_login_status
        when :external_login_failed
          logger.warn "[#{request_id}] External login failed"

          raise UserError,
                I18n.t('flash.password.invalid_login',
                       :uid => login_uid)
        when :external_login_ok
          true    # this is okay
        else
          logger.warn "[#{request_id}] Raising exception"

          raise UserError,
                I18n.t('flash.password.can_not_change_password',
                       :code => request_id)
      end
    end

    @logged_in_user = User.find(:first,
                                :attribute => 'uid',
                                :value     => login_uid)

    unless @logged_in_user && authenticate(@logged_in_user, params[:login][:password])
      logger.error("[#{request_id}] Can't authenticate user \"#{login_uid}\"")
      return false
    end

    # Don't let non-teachers and non-admins change other people's passwords
    if mode == :other
      wanted_roles = ['admin', 'teacher']
      user_roles = Array(@logged_in_user.puavoEdupersonAffiliation || [])

      unless (user_roles & wanted_roles).any?
        logger.error("[#{request_id}] User \"#{login_uid}\" is not an admin or a teacher")
        raise UserError, I18n.t('flash.password.go_away')
      end
    end

    @user = @logged_in_user
    if params[:user][:uid] then
      target_user_username = params[:user][:uid]

      if domain && target_user_username.end_with?(domain)
        target_user_username.remove!(domain)
      end

      @user = User.find(:first,
                        :attribute => 'uid',
                        :value     => target_user_username)
    else
      target_user_username = login_uid
    end

    unless @user || external_login_status then
      logger.error("[#{request_id}] Username \"#{target_user_username}\" is invalid")
      raise UserError, I18n.t('flash.password.invalid_user',
                                    :uid => params[:user][:uid])
    end

    rest_params = {
      :actor_username       => @logged_in_user.uid,
      :actor_password       => params[:login][:password],
      :host                 => User.configuration[:host],
      :target_user_username => target_user_username,
      :target_user_password => params[:user][:new_password],
      :request_id           => request_id,
    }

    rest_params[:mode] = (@user ? 'all' : 'upstream_only')

    logger.info("[#{request_id}] Sending a password change request to puavo-rest, target user is \"#{target_user_username}\"")

    res = rest_proxy.put('/v3/users/password', :json => rest_params).parse

    unless res.kind_of?(Hash)
      logger.warn("[#{request_id}] the puavo-rest call did not return a Hash:")
      logger.warn("[#{request_id}]   #{res.inspect}")
      res = {}
    end

    if res['exit_status'] == 0 && !@user && external_login_status then
      # ignore return code, try this only for side effect (possibly creates
      # new user to Puavo, and should always sync password):
      external_login(params[:user][:uid], params[:user][:new_password])
      @user = User.find(:first,
                        :attribute => 'uid',
                        :value     => login_uid)
    end

    full_reply = res.merge(
      :from => 'password controller',
      :user => {
        :dn  => (@user ? @user.dn.to_s : '[dn unknown]'),
        :uid => (@user ? @user.uid     : '[uid unknown]'),
      },
      :bind_user => {
        :dn  => @logged_in_user.dn.to_s,
        :uid => @logged_in_user.uid,
      }
    )

    logger.info("[#{request_id}] full reply from puavo-rest: #{full_reply}")

    if res['exit_status'] != 0
      logger.error("[#{request_id}] puavo-rest call failed with exit status #{res['exit_status']}:")

      if res.include?('stderr')
        logger.error("[#{request_id}]  stderr: \"#{res['stderr']}\"")
      end

      if res.include?('stdout')
        logger.error("[#{request_id}]  stdout: \"#{res['stdout']}\"")
      end

      case res['extlogin_status']
        when PuavoRest::ExternalLoginStatus::BADUSERCREDS
          logger.error("[#{request_id}]   external login: bad credentials")
          raise UserError,
                I18n.t('flash.password.invalid_external_login',
                       :uid => login_uid)

        when PuavoRest::ExternalLoginStatus::UPDATEERROR
          logger.error("[#{request_id}]   external login: update error")
          raise UserError,
                I18n.t('flash.password.can_not_change_upstream_password')

        when PuavoRest::ExternalLoginStatus::UPDATED
          logger.error("[#{request_id}]   external login password was updated, but some other error occurred when changing password")
          raise UserError, I18n.t('flash.password.extlogin_password_changed_but_puavo_failed')

        when PuavoRest::ExternalLoginStatus::USERMISSING
          logger.error("[#{request_id}]   external login: user not found")
          raise UserError, I18n.t('flash.password.invalid_user',
                                  :uid => params[:user][:uid])
      end

      # If there were external systems where the password change could not be
      # synchronised, they might (should) have returned an actual error code
      # indicating why the call failed. If that code exists, use it to format
      # a clean error message that can be shown to the user.
      if res.include?('sync_status')
        raise UserError, I18n.t('flash.password.failed_details',
          :details => I18n.t('flash.integrations.' + res['sync_status']),
          :code => request_id)
      end

      logger.error("[#{request_id}] Unknown password change error!")

      # just show a generic error message with the request ID, so it can be
      # grepped from the logs
      raise UserError, I18n.t('flash.password.failed_code', :code => request_id)
    end

    return true
  end

  def authenticate(user, password)
    result = user.bind(password) rescue false
    user.remove_connection
    return result
  end

  def set_ldap_connection
    req_host = request.host

    # Make the password forms work on staging servers
    if req_host.start_with?('staging-')
      req_host.remove!('staging-')
    end

    organisation_key = Puavo::Organisation.key_by_host(req_host)

    unless organisation_key
      organisation_key = Puavo::Organisation.key_by_host("*")
    end

    if @organisation_name.nil?
      logger.warn("set_ldap_connection(): @organisation_name is nil, overwriting it with '#{organisation_key}'")
      @organisation_name = organisation_key
    end

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

  def setup_language(lang)
    # use organisation default
    @language = nil

    # override
    if lang && ['en', 'fi', 'sv', 'de'].include?(lang)
      I18n.locale = lang
      @language = lang
    end
  end

  def setup_customisations
    # use -1 because we don't know what the school is
    customisations = get_school_password_form_customisations(@organisation_name, -1)

    @banner = customisations[:banner]
    @domain = customisations[:domain]
  end
end
