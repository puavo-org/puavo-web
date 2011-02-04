module PuavoAuthentication
  module Controllers
    module Helpers
      def current_user
        unless session[:dn].nil?
          unless @current_user.nil?
            return @current_user
          else
            begin
              return @current_user = User.find(session[:dn]) # REST/OAuth?
            rescue
              logger.info "Session's user not found! User is removed from ldap server."
              logger.info "session[:dn]: #{session[:dn]}"
              # Delete ldap connection informations from session.
              session.delete :password_plaintext
              session.delete :dn
            end
          end
        end
        return nil
      end

      def login_required
        case request.format
        when !current_user && Mime::JSON
          logger.debug "Using HTTP basic authentication"
          password = ""

          user = authenticate_with_http_basic do |login, password|
            User.authenticate(login, password)
          end
          logger.debug "Basic Auth User: " + user.inspect
          if user
            session[:dn] = user.dn
            session[:password_plaintext] = password
            logger.debug "Logged in with http basic authentication"
          else
            request_http_basic_authentication
          end
        else
          unless current_user
            store_location
            flash[:notice] = t('must_be_logged_in')
            redirect_to login_path
            return false
          end
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
        else
          dn =  default_ldap_configuration["bind_dn"]
          password = default_ldap_configuration["password"]
        end
        logger.debug "Set host, bind_dn, base and password by user:"
        logger.debug "host: #{host}"
        logger.debug "base: #{base}"
        logger.debug "dn: #{session[:dn]}"
        #logger.debug "password: #{session[:password_plaintext]}"
        LdapBase.ldap_setup_connection(host, base, dn, password)
      end

      def remove_ldap_connection
        ActiveLdap::Base.active_connections.keys.each do |connection_name|
          ActiveLdap::Base.remove_connection(connection_name)
        end
      end

      def organisation_owner?
        Puavo::Authorization.organisation_owner?
      end

      def set_authorization_user
        Puavo::Authorization.current_user = current_user if current_user
      end
    end
  end
end
