module PuavoAuthentication
  module Controllers
    module Helpers

      def token_manager
        @token_manager ||= Puavo::OAuth::TokenManager.new Puavo::OAUTH_CONFIG["token_key"]
      end

      # Lazy getter for current user object
      def current_user

        # ExternalService has no permission to find itself.
        return if @UserClass == ExternalService

        # TODO
        if @logged_in_dn.to_s.starts_with? "puavoOAuthAccessToken"
          logger.warn "Cannot get User object for #{ @logged_in_dn }"
          return
        end

        return @current_user if @current_user

        if @logged_in_dn
          @current_user = @UserClass.find @logged_in_dn
          return @current_user
        end

        logger.info "Session's user not found! User is removed from ldap server."
        logger.info "session[:dn]: #{session[:dn]}"
        # Delete ldap connection informations from session.
        session.delete :password_plaintext
        session.delete :uid

      end

      # Returns [oauth_dn, password] if user supplied "Authorization: token <data>" header
      def oauth_credentials
        if auth_header = request.headers["HTTP_AUTHORIZATION"]
          type, data = auth_header.split
          if type.downcase == "token"
            return token_manager.decrypt data
          end
        end
        return nil
      end

      # Returns user dn and password for some available login mean
      def login_credentials

        if oc = oauth_credentials
          logger.debug "Using OAuth authentication with #{ oc[0] }"
          return oc
        end

        authenticate_with_http_basic do |uid, password|
          logger.debug "Using basic authentication with #{ uid }"

          if uid.match(/^service\//)
            uid = uid.match(/^service\/(.*)/)[1]
          end

          return User.uid_to_dn(uid), password, uid
        end

        if uid = session[:uid]
          logger.debug "Using session authentication with #{ uid }"
          return User.uid_to_dn(uid), session[:password_plaintext], uid
        end

      end


      # Authenticate filter
      def require_login

        if @authentication && @authentication.authenticated
          logger.debug "Already required login with #{ @authentication.dn }"
          return
        end

        host = session[:organisation].ldap_host
        base = session[:organisation].ldap_base

        @authentication = Puavo::Authentication.new

        # First configure ActiveLdap to use the default configuration from
        # ldap.yml. This allows Puavo to search user dn from user uids.
        default_ldap_configuration = ActiveLdap::Base.ensure_configuration
        @authentication.configure_ldap_connection(
          default_ldap_configuration["bind_dn"],
          default_ldap_configuration["password"],
          host,
          base)


        begin
          dn, password, uid = login_credentials
        rescue Puavo::UnknownUID => e
          logger.debug "Failed to get credentials: #{ e.message }"
          show_authentication_error t('flash.session.failed')
          return false
        end

        if dn.nil?
          logger.debug "No credentials supplied"
          show_authentication_error t('must_be_logged_in')
          return false
        end

        # Configure ActiveLdap to use user dn and password
        @authentication.configure_ldap_connection dn, password, host, base

        logger.debug "Going to login in with #{ dn }"
        begin
          @authentication.authenticate
        rescue Puavo::AuthenticationError => e
          logger.info "Login failed for #{ dn } (#{ uid }): #{ e }"
          show_authentication_error t('flash.session.failed')
          return false
        end

        if session[:login_flash]
          flash[:notice] = session[:login_flash]
          session.delete :login_flash
        end

        nil
      end

      def require_puavo_authorization

        return false unless @authentication

        begin
          @authentication.authorize
        rescue Puavo::AuthorizationFailed => e
          logger.info "Authorization  failed: #{ e }"
          show_authentication_error t('flash.session.failed')
          return false
        end
      end

      def show_authentication_error(msg)
        session.delete :password_plaintext
        session.delete :uid
        if request.format == Mime::JSON
          render :json => {
            :error => "authorization error",
            :message => msg,
          }.to_json
        else
          store_location
          flash[:notice] = t('flash.session.failed')
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

      def remove_ldap_connection
        Puavo::Authentication.remove_connection
      end

    end
  end
end
