module Puavo
  module AuthenticationHelper

    attr_accessor :authentication

    def current_user

      if @authentication.nil?
        raise "Cannot call 'current_user' before 'setup_authentication'"
      end

      @authentication.current_user

    end

    def current_user?
      current_organisation? && @authentication.authenticated? && @authentication.user?
    end

    def current_organisation?
      !!@authentication && !!@authentication.current_organisation
    end


    def current_organisation
      if @authentication.nil?
        raise "Cannot call 'current_organisation' before 'setup_authentication'"
      end

      @authentication.current_organisation

    end


    # Returns user dn/uid and password for some available login mean
    def acquire_credentials

      # Basic Auth
      #  * OAuth Client Server ID & Secrect
      #  * External Service UID & password
      #  * User UID & password
      #  * Server dn & password
      authenticate_with_http_basic do |username, password|
        logger.debug "Using basic authentication with #{ username }"

        # Allow logins with dn
        if !username.to_s.empty? && (dn = ActiveLdap::DistinguishedName.parse(username) rescue nil)
          return {
            :dn => dn,
            :organisation_key => organisation_key_from_host,
            :password => password,
          }
        end

        return {
          :uid => username,
          :organisation_key => organisation_key_from_host,
          :password => password
        }
      end

      # Puavo Session (User UID & password)
      if uid = session[:uid]
        logger.debug "Using session authentication with #{ uid }"
        return {
          :uid => uid,
          :organisation_key => organisation_key_from_host,
          :password => session[:password_plaintext]
        }
      end

      raise NoCredentials, "No credentials supplied"

    end

    # Before filter
    # Setup authentication object with default credentials from
    # config/ldap.yml
    def setup_authentication

      @authentication = Puavo::Authentication.new

    end


    def perform_login(credentials)

      # Configure ActiveLdap to use the credentials
      @authentication.configure_ldap_connection credentials

      # Authenticate above credentials
      @authentication.authenticate

      # If we are already logged in and the user has changed the UI language,
      # don't set the language from organisations.yml
      if session && session[:user_locale]
        I18n.locale = session[:user_locale]
      else
        # No custom language, use the organisation default
        I18n.locale = current_organisation.locale
      end

      return true
    end

    # Before filter
    # Require user login credentials
    def require_login

      begin
        perform_login(acquire_credentials)
      rescue Puavo::NoCredentials => e
        if request.format == Mime[:json]
          render(:json => {
                   :error => e.code,
                   :message => e,
                 }.to_json,
                 :status => 401)
        else
          store_location
          redirect_to login_path
        end
        return false
      rescue Puavo::AuthenticationError => e
        logger.info "Login failed for: #{ e }"
        show_authentication_error e.code, t('flash.session.failed')
        return false
      end

      # If we have a human user logging in and their account has expired, force an immediate logout
      if @authentication.user? &&
          current_user.puavoEduPersonAccountExpirationTime &&
          Time.now.utc >= current_user.puavoEduPersonAccountExpirationTime.utc

        logger.error "Account #{current_user.uid.inspect} has expired at #{current_user.puavoEduPersonAccountExpirationTime}, login attempt rejected"

        session.delete :password_plaintext
        session.delete :uid

        return show_authentication_error 401, t('flash.your_account_has_expired')
      end

      unless @authentication.user?
        # Non-interactive logins cannot have MFA (technically, they could but it would be
        # hideously complicated)
        session[:mfa] = 'skip'
      end

      unless ['skip', 'ask', 'pass', 'fail'].include?(session[:mfa])
        # We're not in a known MFA state (this is normal immediately after the initial login),
        # so figure out what to do.

        if current_user.puavoMFAEnabled
          # We need to ask for the MFA code
          session[:mfa] = 'ask'

          # We won't have access to the UUID again for some time, so grab it while we can
          # (this is needed for the MFA server)
          session[:uuid] = current_user.puavoUuid

          # Since MFA is enabled, stash MFA tracking stuff in Redis for five minutes.
          # That's how long the user has time to enter the code.
          redis = Redis::Namespace.new('puavo:mfa:login', redis: REDIS_CONNECTION)
          redis.set(session[:uuid], '0', nx: true, ex: 60 * 5)

          # Remember the original URL the user was trying to access. We need to store this again,
          # because the redirect from the login form does not go directly to the MFA form, but
          # instead the login code calls redirect_back_or_default() (see below), which removes the
          # URL from the session data and causes a new redirect which then leads to the MFA form.
          # But fortunately we need to do this only once; entering an invalid MFA code does not
          # lose the URL because we don't call redirect_back_or_default until the code is valid.
          store_location
        else
          # MFA is not active, just continue normally
          session[:mfa] = 'skip'
        end
      end

      if ['ask', 'fail'].include?(session[:mfa])
        # We either have not asked for the MFA code yet, or it was incorrect.
        # Go to the MFA form.
        return redirect_to mfa_ask_code_path
      end

      if session[:login_flash]
        flash[:notice] = session[:login_flash]
        session.delete :login_flash
      end

      return true
    end

    # Before filter
    # Require Puavo access rights
    def require_puavo_authorization

      # Unauthorized always when not authenticated
      return false unless @authentication

      begin
        @authentication.authorize
      rescue Puavo::AuthorizationFailed => e
        logger.info "Authorization  failed: #{ e }"
        show_authentication_error "unauthorized", t('flash.session.failed')
        return false
      end
    end

    def show_authentication_error(code, message)
      session.delete :password_plaintext
      session.delete :uid
      if request.format == Mime[:json]
        render(:json => {
                 :error => code,
                 :message => message,
               }.to_json,
               :status => 401)
      else
        store_location
        flash[:notice_css_class] = "message_alert"
        flash[:notice] = message
        redirect_to login_path
      end
    end

    def store_location
      session[:return_to] = "#{request.protocol}#{request.host_with_port}#{request.fullpath}"
    end

    def redirect_back_or_default(default)
      redirect_to(session[:return_to] || default)
      session[:return_to] = nil
    end

    def organisation_key_from_host(host=nil)
      request_host = request.host.to_s.gsub(/^staging\-/, "")
      organisation_key = Puavo::Organisation.key_by_host(request_host)
      unless organisation_key
        organisation_key = Puavo::Organisation.key_by_host("*")
      end
      return organisation_key
    end


    def set_initial_locale
      # Default to English
      I18n.locale = "en"

      # TODO: set from user agent

      # Set from hostname if it is a known organisation
      if organisation = Puavo::Organisation.find_by_host(request.host)
        I18n.locale = organisation.locale
      end

    end

    def remove_ldap_connection
      Puavo::Authentication.remove_connection
    end
  end
end
