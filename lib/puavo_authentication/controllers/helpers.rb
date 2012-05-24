module PuavoAuthentication
  module Controllers
    module Helpers

      # Lazy getter for current user object
      def current_user

        # ExternalService has no permission to find itself.
        return if @UserClass == ExternalService

        # TODO
        if @logged_in_dn.starts_with? "puavoOAuthAccessToken"
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

      # Returns dn and password for some available login mean
      def login_credentials

        @UserClass = User

        if auth_header = request.headers["HTTP_AUTHORIZATION"]
          type, data = auth_header.split
          type.downcase!

          if type == "token"
            credentials = ActiveSupport::JSON.decode Base64.decode64(data)
            logger.debug "Using OAuth #{ credentials }"
            return credentials["dn"], credentials["pw"]
          end

          if type == "basic"
            authenticate_with_http_basic do |uid, password|
              logger.debug "Using basic authentication with #{ uid }"

              if uid.match(/^service\//)
                uid = uid.match(/^service\/(.*)/)[1]
                # User is initialized from ExternalService in this special case
                @UserClass = ExternalService
              end

              return @UserClass.uid_to_dn(uid), password, uid
            end
          end

        end

        if uid = session[:uid]
          logger.debug "Using session authentication with #{ uid }"
          return User.uid_to_dn(uid), session[:password_plaintext], uid
        end

      end

      # Authenticate filter
      def require_login
        return if @logged_in_dn

        begin
          dn, password, uid = login_credentials
        rescue Puavo::Authentication::UnknownUID => e
          logger.debug "Failed to get credentials: #{ e.message }"
          show_authentication_error t('flash.session.failed')
          return false
        end

        if dn.nil?
          logger.debug "No credentials supplied"
          show_authentication_error t('must_be_logged_in')
          return false
        end

        logger.debug "Going to login in with #{ dn }"

        begin
          @UserClass.authorize dn, password
        rescue Puavo::Authentication::AuthenticationError => e
          logger.info "Login failed for #{ dn } (#{ uid }): #{ e }"
          show_authentication_error t('flash.session.failed')
          return false
        end

        @logged_in_dn = dn
        nil
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

      def ldap_setup_connection
        host = ""
        base = ""
        default_ldap_configuration = ActiveLdap::Base.ensure_configuration
        unless session[:organisation].nil?
          host = session[:organisation].ldap_host
          base = session[:organisation].ldap_base
        end
        if session[:dn]
          dn = session[:dn]
          password = session[:password_plaintext]
          logger.debug "Using user's credentials for LDAP connection"
        else
          logger.debug "Using Puavo credentials for LDAP connection"
          dn =  default_ldap_configuration["bind_dn"]
          password = default_ldap_configuration["password"]
        end
        logger.debug "Set host, bind_dn, base and password by user:"
        logger.debug "host: #{host}"
        logger.debug "base: #{base}"
        logger.debug "dn: #{dn}"
        LdapBase.ldap_setup_connection(host, base, dn, password)
      end

      def remove_ldap_connection
        ActiveLdap::Base.active_connections.keys.each do |connection_name|
          ActiveLdap::Base.remove_connection(connection_name)
        end
      end

      def organisation_owner?
        raise "DEPRECATED call to organisation_owner? helper. Use `current_user.organisation_owner?` instead"
      end

    end
  end
end
