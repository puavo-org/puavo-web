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
      current_organisation? && @authentication.dn
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

      # OAuth Access Token
      if auth_header = request.headers["HTTP_AUTHORIZATION"]
        type, data = auth_header.split
        if type.downcase == "bearer"
          return AccessToken.decrypt_token data
        end
      end

      # Basic Auth
      #  * OAuth Client Server ID & Secrect
      #  * External Service UID & password
      #  * User UID & password
      #  * Server dn & password
      authenticate_with_http_basic do |username, password|
        logger.debug "Using basic authentication with #{ username }"

        # FIXME: move to Puavo::Authentication class (configure_ldap_connection)
        if match = username.match(/^oauth_client_id\/(.*)\/(.*)$/)

          org_key = match[1]
          oauth_client_id = match[2]

          @authentication.configure_ldap_connection(
                                                    :organisation_key => org_key
                                                    )

          oauth_client_server = OauthClient.find(:first,
                                                 :attribute => "puavoOAuthClientId",
                                                 :value => oauth_client_id)

          return {
            :dn => oauth_client_server.dn,
            :organisation_key => org_key,
            :password => password,
            :scope => oauth_client_server.puavoOAuthScope
          }

        end

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

      # Authenticate above credentials
      @authentication.authenticate

      # Set locale from user's organisation
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


    def set_organisation_to_session
      session[:organisation] = current_organisation if current_organisation
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
