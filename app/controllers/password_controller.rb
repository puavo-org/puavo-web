# The publicly-accessible password changing and resetting forms. Allows users to change/reset
# their own password, and teachers/admins to change someone else's password.

class UserNotFound < StandardError; end
class TooManySentTokenRequest < StandardError; end
class RestConnectionError < StandardError; end
class EmptyPassword < StandardError; end
class PasswordConfirmationFailed < StandardError; end
class TokenLifetimeHasExpired < StandardError; end
class WeakPassword < StandardError; end

class PasswordController < ApplicationController
  include Puavo::Integrations
  include Puavo::Password

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

    @primary_school_id = params.fetch(:primary_school_id, -1)
    @reduced_ui = params.include?('hidetabs')

    setup_customisations()
  end

  # GET /password/edit
  # "Change someone else's password" form
  def edit
    @user = User.new

    @changing = params.fetch(:changing, '')
    @changed = params.fetch(:changed, '')

    @primary_school_id = params.fetch(:primary_school_id, -1)
    @reduced_ui = params.include?('hidetabs')

    setup_language(params.fetch(:lang, ''))
    setup_customisations()
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
      filter_multiple_attempts(request_id, nil, params['login']['uid'])
      mode = :own
    else
      logger.info "[#{request_id}] (#{Time.now}) User \"#{params['login']['uid']}\" " \
                  "is trying to change the password of user \"#{params['user']['uid']}\" " \
                  "in organisation \"#{@organisation_name}\", #{ip}"
      filter_multiple_attempts(request_id, params['login']['uid'], params['user']['uid'])
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

    @reduced_ui = params.include?('hidetabs')
    @primary_school_id = params.fetch(:primary_school_id, -1)

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

    request_id = generate_synchronous_call_id()

    if params[:forgot].empty? || params[:forgot][:email].empty?
      flash[:alert] = I18n.t('password.forgot.description')
      redirect_to forgot_password_path
      return
    end

    begin
      logger.info("[#{request_id}] A password reset for user \"#{params[:forgot][:email]}\" has been requested")
      log_request_env(request, request_id)

      user = User.find(:first, :attribute => "mail", :value => params[:forgot][:email])

      unless user
        logger.error("[#{request_id}] No user found by that email address")
        raise "No user found by email \"#{params[:forgot][:email]}\""
      end

      logger.info("[#{request_id}] Found user \"#{user.givenName} #{user.sn}\" (\"#{user.uid}\"), " \
                  "ID=#{user.puavoId}, organisation=\"#{current_organisation_domain}\"")

      db = redis_connect

      if db.get(user.puavoId)
        logger.error("[#{request_id}] This user has already received a password reset link, request rejected")
        raise "A reset link has already been sent for the specified user"
      end

      send_token_url = password_management_host + "/password/send_token"

      logger.info("[#{request_id}] Generating the reset email, see the password reset host logs at " \
                  "#{password_management_host} for details")

      rest_response = HTTP.headers(host: current_organisation_domain, 'Accept-Language': locale)
                          .post(send_token_url, params: {
                            # Most of these are just for logging purposes. Abuse cases must
                            # be traceable afterwards.
                            request_id: request_id,
                            id: user.puavoId.to_i,
                            username: user.uid,
                            email: params[:forgot][:email],
                          })

      if rest_response.status == 200
        db.set(user.puavoId, true)
        db.expire(user.puavoId, 600)
        logger.info("[#{request_id}] Redis entries saved")
      else
        logger.error("[#{request_id}] puavo-rest call failed, response code was #{rest_response.status}")
      end
    rescue => e
      logger.error("[#{request_id}] Password reset failed: #{e}")
    end

    # This always succeeds, even if an email cannot be sent. The message contains a logging ID
    # so the actual reason can be later determined.
    respond_to do |format|
      @message = I18n.t('password.successfully.send_token', :request_id => request_id)
      format.html { render :action => "successfully" }
    end
  end

  # GET /password/:jwt/reset
  # Password reset form
  def reset
    request_id = generate_synchronous_call_id()
    logger.info("[#{request_id}] Rendering the password reset form")
    log_request_env(request, request_id)

    setup_language(params.fetch(:lang, ''))
    setup_customisations()
  end

  # PUT /password/:jwt/reset
  # Reset the user's password
  def reset_update
    request_id = generate_synchronous_call_id()

    if ENV['RAILS_ENV'] == 'test'
      # The password reset requests aren't actually sent anywhere during tests, they're
      # merely mocked with webmock's stub_request(). But here's the problem: stubbing only
      # works if the request is 100% identical every time. And the request ID is a random
      # string. So during tests we have to keep the request ID fixed, otherwise one test
      # will fail every time because the mock does not recognize the request and it is
      # actually sent to a password reset host, which does not exist in test environments.
      # (TODO: Should it exist?)
      request_id = 'ABCDEFGHIJ'
    end

    logger.info("[#{request_id}] Processing a password reset form submission")
    log_request_env(request, request_id)

    setup_language(params.fetch(:lang, ''))
    setup_customisations()

    if params[:reset][:password].nil? || params[:reset][:password].empty? ||
       params[:reset][:password_confirmation].nil? || params[:reset][:password_confirmation].empty?
      # Protect against intentionally broken form
      logger.info("[#{request_id}] Empty password/password confirmation")
      raise EmptyPassword
    end

    raise PasswordConfirmationFailed if params[:reset][:password] != params[:reset][:password_confirmation]

    # Match full words in a tab-separated string of blocked passwords
    raise WeakPassword if Regexp.new("\t#{params[:reset][:password]}\t").match(Puavo::COMMON_PASSWORDS)

    change_password_url = password_management_host + "/password/change/#{ params[:jwt] }"

    logger.info("[#{request_id}] Resetting the password, see the password reset host logs at " \
                "#{password_management_host} for details")

    rest_response = HTTP.headers(host: current_organisation_domain, 'Accept-Language': locale)
                                 .put(change_password_url, json: {
                                    request_id: request_id,
                                    new_password: params[:reset][:password]
                                 })

    if rest_response.status == 404 &&
        JSON.parse(rest_response.body.readpartial)["error"] == "Token lifetime has expired"
      raise TokenLifetimeHasExpired
    end

    respond_to do |format|
      if rest_response.status == 200
        begin
          # Remove the reset flag from the user, so a new reset email can be sent. The problem is,
          # we don't know who the user was. But the reset host sends that information back to us.
          # The data is in the JWT token, but we won't decode it here.
          data = JSON.parse(rest_response.body.to_s)

          db = redis_connect
          db.del(data['id'])
          logger.info("[#{request_id}] Redis entries cleared")
          logger.info("[#{request_id}] Password reset complete for user \"#{data['uid']}\" (ID=#{data['id']})")
        rescue => e
          logger.error("[#{request_id}] Unable to parse the response received from the password reset host: #{e}")
          logger.error("[#{request_id}] Raw response data: #{rest_response.body.to_s}")
          logger.error("[#{request_id}] Redis entries not cleared")
          logger.info("[#{request_id}] Password reset complete for unknown user")
        end

        @message = I18n.t('password.successfully.update')
        format.html { render :action => "successfully" }
      else
        logger.error("[#{request_id}] Password change failed, puavo-rest returned error:")
        logger.error("[#{request_id}] #{rest_response.inspect}")
        flash[:alert] = I18n.t('flash.password.can_not_change_password', :code => request_id)
        format.html { redirect_to reset_password_path }
      end
    end
  rescue PasswordConfirmationFailed
    logger.info("[#{request_id}] Password confirmation failed")
    flash.now[:alert] = I18n.t('flash.password.confirmation_failed')
    render :action => "reset"
  rescue EmptyPassword
    logger.info("[#{request_id}] No password entered")
    flash.now[:alert] = I18n.t('flash.password.confirmation_failed')
    render :action => "reset"
  rescue WeakPassword
    logger.info("[#{request_id}] The password is weak")
    flash.now[:alert] = I18n.t('activeldap.errors.messages.password_validation.common')
    render :action => "reset"
  rescue TokenLifetimeHasExpired
    logger.info("[#{request_id}] The JWT token has expired")
    flash[:alert] = I18n.t('flash.password.token_lifetime_has_expired')
    redirect_to forgot_password_path
  end

  # "Your password has been reset" form
  def successfully
  end

  private

  def log_request_env(request, request_id)
    logger.info("[#{request_id}] REMOTE_ADDR=\"#{request.env['REMOTE_ADDR']}\"")
    logger.info("[#{request_id}] REMOTE_HOST=\"#{request.env['REMOTE_HOST']}\"")
    logger.info("[#{request_id}] REQUEST_URI=\"#{request.env['REQUEST_URI']}\"")
    logger.info("[#{request_id}] user agent=\"#{request.env['HTTP_USER_AGENT']}\"")
  end

  # Hinder password brute-forcing by imposing a 10-second wait between changing attempts
  def filter_multiple_attempts(request_id, changer, changee)
    db = Redis::Namespace.new("puavo:password_management:attempt_counter", :redis => REDIS_CONNECTION)

    if changer.nil?
      key = changee
    else
      key = "#{changer}:#{changee}"
    end

    if db.exists(key) == 1
      log_prefix = "[#{request_id}] (#{Time.now})"

      if changer.nil?
        logger.error "#{log_prefix} Too many change attempts for user \"#{changee}\", request rejected"
      else
        logger.error "#{log_prefix} User \"#{changer}\" has tried to change the password of user \"#{changee}\" too many times too quickly, request rejected"
      end

      # must setup these or the form breaks
      setup_language(params.fetch(:lang, ''))
      setup_customisations()
      @changing = changer.nil? ? changee : changer

      raise UserError, I18n.t('flash.password.too_many_attempts')
      return
    end

    # Expire automaticlly in 10 seconds
    db.set(key, true, :px => 10000, :nx => true)
  end

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
    # Try to retain the school ID across form reloads. If it cannot be accessed, use -1 for
    # organisation-level rules and hope for the best.
    @primary_school_id = params.fetch(:primary_school_id, -1)

    ruleset_name = get_school_password_requirements(@organisation_name, @primary_school_id)

    if ruleset_name
      rules = Puavo::PASSWORD_RULESETS[ruleset_name][:rules]

      logger.info("[#{request_id}] Validating the password against ruleset \"#{ruleset_name}\"")

      password_errors =
        Puavo::Password::validate_password(params[:user][:new_password], rules)

      unless password_errors.empty?
        # Combine the errors like the live validator does
        logger.error("[#{request_id}] The new password does not meet the requirements (errors=#{password_errors.join(', ')}")
        raise UserError, I18n.t('password.invalid')
      end
    end

    login_uid = params[:login][:uid]

    # If the username(s) contain the domain name, strip it out. -1 for the school ID
    # works here, because domains are always organisation-wide.
    customisations = get_school_password_form_customisations(@organisation_name, -1)
    domain = customisations[:domain]

    Array(domain || []).each do |d|
      if login_uid.end_with?(d)
        login_uid.sub!(d, '')
        break
      end
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

      Array(domain || []).each do |d|
        if target_user_username.end_with?(d)
          target_user_username.sub!(d, '')
          break
        end
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

    # Try to find the primary school ID of the user whose password is being changed.
    # If we can determine it, use it to validate the password.
    if @logged_in_user.puavoEduPersonPrimarySchool
      @primary_school_id = @logged_in_user.puavoEduPersonPrimarySchool.rdns[0]['puavoId'].to_i
    else
      @primary_school_id = @user.puavoEduPersonPrimarySchool.rdns[0]['puavoId'].to_i
    end

    password_errors = []
    new_password = params[:user][:new_password]

    if @primary_school_id
      ruleset_name = get_school_password_requirements(@organisation_name, @primary_school_id)

      if ruleset_name
        # Rule-based password validation
        logger.info("[#{request_id}] Validating the password against ruleset \"#{ruleset_name}\"")
        rules = Puavo::PASSWORD_RULESETS[ruleset_name][:rules]

        password_errors =
          Puavo::Password::validate_password(new_password, rules)

        if Puavo::PASSWORD_RULESETS[ruleset_name][:deny_names_in_passwords]
          if new_password.downcase.include?(@user.givenName.downcase) ||
             new_password.downcase.include?(@user.sn.downcase) ||
             new_password.downcase.include?(@user.uid.downcase) ||
             (mode == :other && new_password.downcase.include?(params[:login][:uid].downcase))
            password_errors << 'contains_name'
          end
        end
      end
    end

    # Reject common passwords. Match full words in a tab-separated string.
    if Puavo::COMMON_PASSWORDS.include?("\t#{new_password}\t")
      logger.error("[#{request_id}] Rejecting a common/weak password")
      password_errors << 'common'
    end

    unless password_errors.empty?
      # Combine the errors like the live validator does
      logger.error("[#{request_id}] The new password does not meet the requirements (errors=#{password_errors.join(', ')})")
      raise UserError, I18n.t('password.invalid')
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
