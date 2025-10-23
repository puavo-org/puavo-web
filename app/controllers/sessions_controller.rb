class SessionsController < ApplicationController
  include Puavo::LoginCustomisations
  include Puavo::Integrations     # request ID generation
  include Puavo::MFA              # MFA server request helper

  layout 'sessions'

  skip_before_action :require_puavo_authorization, :only => [ :new, :create, :mfa_ask, :mfa_post ]
  skip_before_action :require_login, :only => [ :new, :create, :mfa_ask, :mfa_post ]

  # The default mount point for Rack. This used to be a method in application_controller.rb.
  RACK_MOUNT_POINT = '/'.freeze

  def new
    # Base content
    @login_content = {
      # "prefix" must be set, because the same form is used for puavo-web and
      # puavo-rest, but their contents (CSS, etc.) are stored in different
      # places. This key tells the form where those resources are.
      "prefix" => "/login",

      "external_service_name" => I18n.t("sessions.new.external_service_name"),
      "service_title_override" => nil,
      "return_to" => params['return_to'] || params['return'] || nil,
      "organisation" => request.host,
      "display_domain" => request.host,   # used mainly in SSO code, but must be set here too
      "username_placeholder" => I18n.t("sessions.new.username_placeholder"),
      "username" => params["username"],
      "error_message" => flash[:notice],
      "topdomain" => PUAVO_ETC.topdomain,
      "text_password" => I18n.t("sessions.new.password"),
      "text_login" => I18n.t("sessions.new.login"),
      "text_help" => I18n.t("sessions.new.help"),
      "text_username_help" => I18n.t("sessions.new.username_help"),
      "text_organisation_help" => I18n.t("sessions.new.organisation_help"),
      "text_developers" => I18n.t("sessions.new.developers"),
      "text_developers_info" => I18n.t("sessions.new.developers_info"),
      "text_login_to" => I18n.t("sessions.new.login_to")
    }

    # Per-customer customisations, if any
    @login_content.merge!(customise_login_screen())

    respond_to do |format|
      format.html do
        render template: 'sessions/login_form'
      end
    end
  end

  def create
    session[:uid] = params[:username]
    session[:password_plaintext] = params[:password]

    mfa_init_session

    redirect_back_or_default RACK_MOUNT_POINT
  end

  def auth
    respond_to do |format|
      format.json { render :json => true.to_json }
    end
  end

  def show
    @user = current_user
    respond_to do |format|
      format.json  { render :json => @user.as_json(:methods => :managed_schools) }
    end
  end

  def purge_session
    # Remove dn and plaintext password values from session
    session.delete :password_plaintext
    session.delete :uid

    # Forget language changes
    session.delete :user_locale

    mfa_purge_session
  end

  def destroy
    purge_session
    redirect_to login_path
  end

  # Temporarily override the language defined in organisations.yml. The override
  # lasts until logout.
  def change_language
    unless params.include?(:lang) && Rails.configuration.available_ui_locales.include?(params[:lang])
      flash[:alert] = t('flash.session.invalid_language')
    else
      # If the new language is the organisation default, remove the custom key
      if params[:lang] == current_organisation.locale
        session.delete :user_locale
      else
        session[:user_locale] = params[:lang]
      end
    end

    redirect_back(fallback_location: "/users")
  end

  # ------------------------------------------------------------------------------------------------
  # MULTI-FACTOR AUTHENTICATION

  def _mfa_redis
    Redis::Namespace.new('puavo:mfa:login', redis: REDIS_CONNECTION)
  end

  def mfa_init_session
    session[:uuid] = nil          # we haven't authenticated the user yet, so this is unknown
    session[:mfa] = 'unknown'     # we don't know yet if the user even has MFA enabled or not
  end

  def mfa_purge_session
    session.delete :uuid
    session.delete :mfa
  end

  # Asks for the MFA code
  def mfa_ask
    request_id = generate_synchronous_call_id

    begin
      unless session.include?(:mfa) || session.include?(:uuid) || ['ask', 'fail'].include?(session[:mfa])
        # This can happen if the MFA form URL is accessed directly, or the user tries
        # to return to it
        purge_session
        mfa_error(t('sessions.new.mfa.errors.no_session'))
        return
      end

      if session[:mfa] == 'fail'
        redis = _mfa_redis

        if !session.include?(:uuid) || redis.get(session[:uuid]).nil?
          # This can happen if the Redis token expires before the form is opened
          # (because if the code was not correct, we're essentially in a loop
          # asking the code again and again, and the token can expire between the
          # previous and this iteration).
          purge_session
          mfa_error(t('sessions.new.mfa.errors.expired'))
          return
        end

        @mfa_error = t('sessions.new.mfa.incorrect_code')
      end

      mfa_form
    rescue StandardError => e
      purge_session
      logger.error("[#{request_id}] unhandled exception: #{e}")
      mfa_error(t('sessions.new.mfa.errors.fatal_error', request_id: request_id))
    end
  end

  # Validate the MFA code
  def mfa_post
    request_id = generate_synchronous_call_id
    redis = _mfa_redis

    if !session.include?(:uuid) || redis.get(session[:uuid]).nil?
      # This can happen if the Redis token expires while the form is being displayed
      purge_session
      mfa_error(t('sessions.new.mfa.errors.expired'))
      return
    end

    if params.include?('cancel')
      # Cancel the login attempt. This one is simpler to implement than on puavo-rest side,
      # because here the login form path is always fixed.
      redis.del(session[:uuid])
      purge_session
      redirect_to login_path
      return
    end

    begin
      logger.info("[#{request_id}] checking the MFA code for user #{session[:uuid]}")

      response, data = Puavo::MFA.mfa_call(request_id, :post, 'authenticate', data: {
        userid: session[:uuid],
        code: params.fetch('mfa_code', '')
      })

      logger.info("[#{request_id}] MFA server response ID: #{response.headers['X-Request-ID']}")

      if response.status == 200 && data['status'] == 'success' && data['messages'].include?('1002')
        logger.info("[#{request_id}] the code is valid")
        redis.del(session[:uuid])
        session[:mfa] = 'pass'
        redirect_back_or_default RACK_MOUNT_POINT
      elsif response.status == 403 && data['status'] == 'fail' && data['messages'].include?('2002')
        logger.info("[#{request_id}] the code is not valid")
        session[:mfa] = 'fail'

        if redis.incr(session[:uuid]) > 4
          # Too many attempts
          redis.del(session[:uuid])
          purge_session
          logger.error("[#{request_id}] too many failed MFA attempts")
          mfa_error(t('sessions.new.mfa.errors.too_many_attempts'))
          return
        end

        redirect_to mfa_ask_code_path
      else
        logger.error("[#{request_id}] unhandled MFA server response:")
        logger.error("[#{request_id}]   #{response.inspect}")
        logger.error("[#{request_id}]   #{data.inspect}")
        redis.del(session[:uuid])
        purge_session
        mfa_error(t('sessions.new.mfa.errors.mfa_server_error', request_id: request_id))
      end
    rescue StandardError => e
      redis.del(session[:uuid])
      purge_session
      logger.error("[#{request_id}] unhandled exception: #{e}")
      mfa_error(t('sessions.new.mfa.errors.fatal_error', request_id: request_id))
    end
  end

  def mfa_form
    # The form layout is the same for normal puavo-web logins and also puavo-rest's SSO logins,
    # so all these must be set. The MFA form cannot be customised yet.
    @login_content = {
      'prefix' => '/login',
      'mfa_post_uri' => mfa_post_code_path,

      # The form translations come from different places, so they cannot be embedded directly
      # into the template. (FIXME: Or can they?)
      'mfa_help' => t('sessions.new.mfa.help'),
      'mfa_help2' => t('sessions.new.mfa.help2'),
      'mfa_continue' => t('sessions.new.mfa.continue'),
      'mfa_cancel' => t('sessions.new.mfa.cancel'),
      'technical_support' => t('sessions.new.technical_support'),
    }

    respond_to do |format|
      format.html do
        render 'sessions/mfa_form'
      end
    end
  end

  def mfa_error(message)
    # The same layout is used here too
    @login_content = {
      'error_message' => message,
      'technical_support' => t('sessions.new.technical_support'),
      'prefix' => '/login',
    }

    respond_to do |format|
      format.html do
        render 'sessions/generic_error'
      end
    end
  end
end
