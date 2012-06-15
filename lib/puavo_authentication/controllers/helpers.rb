module PuavoAuthentication
  module Controllers
    module Helpers

      attr_accessor :authentication

      def current_user

        if @authentication.nil?
          raise "Cannot call 'current_user' before 'setup_authentication'"
        end

        @authentication.current_user

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
        authenticate_with_http_basic do |username, password|
          logger.debug "Using basic authentication with #{ username }"

          # TODO: move to oauth controller
          if username.match(/^oauth_client_id\//)

            oauth_client_id = username.match(/^oauth_client_id\/(.*)/)[1]
            oauth_client_server = OauthClient.find(:first,
              :attribute => "puavoOAuthClientId",
              :value => oauth_client_id)
            raise Puavo::AuthenticationFailed, "Bad Client Id" if oauth_client_server.nil?

            return {
              :dn => oauth_client_server.dn,
              :organisation_key => organisation_key_from_host,
              :password => password,
              :scope => oauth_client_server.puavoOAuthScope
            }

          end

          uid = username
          if username.match(/^service\//)
            uid = username.match(/^service\/(.*)/)[1]
          end

          return {
            :uid => uid,
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

      end

      # Before filter
      # Setup authentication object with default credentials from
      # config/ldap.yml
      def setup_authentication

        @authentication = Puavo::Authentication.new

      end


      def perform_login(credentials)

        if @authentication && @authentication.authenticated
          logger.debug "Already required login with #{ @authentication.dn }"
          return true
        end

        if credentials.nil?
          raise Puavo::AuthenticationFailed, "No credentials supplied"
        end


        if uid = credentials[:uid]
          # Configure new organisation for default Puavo credentials. This is
          # used to fetch user dn from uid.
          @authentication.configure_ldap_connection(
            :organisation_key => credentials[:organisation_key]
          )
          credentials[:dn] = User.uid_to_dn(uid)
        end

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
        rescue Puavo::AuthenticationError => e
          logger.info "Login failed for: #{ e }"
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
          :status => 400)
        else
          store_location
          flash[:notice] = message
          redirect_to login_path
        end
      end

      def store_location
        session[:return_to] = request.request_uri
      end

      def redirect_back_or_default(default)
        redirect_to(session[:return_to] || default)
        session[:return_to] = nil
      end

      def organisation_key_from_host(host=nil)
        # <organisation key>.<domain>
        # Example: toimisto.opinsys.fi
        if match = request.host.match(/^([^\.]+)/)
          return match[1]
        end
        "kunta1" # XXX
      end


      def set_organisation_to_session
        session[:organisation] = current_organisation if current_organisation
      end

      def set_initial_locale
        # Default to English
        I18n.locale = "en"

        # TODO: set from user agent

        # Set from hostname if it is a known organisation
        # if organisation_from_host
        #   I18n.locale = organisation_from_host.locale
        # end

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
end
