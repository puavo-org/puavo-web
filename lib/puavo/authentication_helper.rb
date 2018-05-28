# XXX require '..'

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
          flog.info "Basic auth with DN", "dn" => dn
          return {
            :dn => dn,
            :organisation_key => organisation_key_from_host,
            :password => password,
          }
        end

        flog.info "Basic auth with uid", "uid" => username
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

      # We first make a /v3/external_login/auth request to puavo-rest before
      # doing the actual authentication, because user password might have been
      # updated on external login service.
      # We use request.host instead of puavoDomain from organisation info,
      # because that would require ldap access, which we can not get
      # before we have possibly updated user password from external login
      # service.  This is not optimal though, because now web requests must
      # always have the correct domain and we have no choice to fall back to
      # default domain.
      begin
        rest_proxy = PuavoRestProxy.new(request.host,
                                        credentials[:uid],
                                        credentials[:password])
        res = rest_proxy.post('/v3/external_login/auth').parse
        # XXX raise "RES_STATUS: #{ res.inspect }"
      rescue StandardError => e
        short_errmsg = 'Problem with external login auth before' \
                         + ' Puavo-authentication'
        long_errmsg = "#{ short_errmsg }: #{ e.message }"
        logger.warn(long_errmsg)
        flog.warn(short_errmsg, 'error' => long_errmsg)
      end

      # Authenticate above credentials
      @authentication.authenticate

#      # Set locale from user's organisation
      I18n.locale = current_organisation.locale

      return true
    end

    # Before filter
    # Require user login credentials
    def require_login

      begin
        perform_login(acquire_credentials)
      rescue Puavo::NoCredentials => e
        if request.format == Mime::JSON
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
        flog.info "Login authentication failed", "error" => e.message
        show_authentication_error e.code, t('flash.session.failed')
        return false
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
        flog.info "Authorization failed", "error" => e.message
        logger.info "Authorization  failed: #{ e }"
        show_authentication_error "unauthorized", t('flash.session.failed')
        return false
      end
    end

    def show_authentication_error(code, message)
      session.delete :password_plaintext
      session.delete :uid
      if request.format == Mime::JSON
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

    def theme
      if current_organisation
        theme = current_organisation.value_by_key('theme')
      end

      return theme || "breathe"
    end

  end
end
