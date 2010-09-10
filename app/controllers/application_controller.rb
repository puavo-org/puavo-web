# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  before_filter :set_organisation_to_session, :set_locale
  helper_method :theme

  before_filter :ldap_setup_connection
  helper :all # include all helpers, all the time
  protect_from_forgery # See ActionController::RequestForgeryProtection for details
  helper_method :current_user, :ldap_setup_connection

  before_filter :find_school
  before_filter :login_required

  private

  def find_school
    if params.has_key?(:school_id)
      school_id = params[:school_id]
    elsif controller_name == 'schools' && params.has_key?(:id)
      school_id = params[:id]
    end

    unless school_id.nil?
      begin
        @school = School.find(school_id)
      rescue
        logger.info "Incorrect school id! Redirected..."
        flash[:notice] = "Incorrect school id!"
        redirect_to schools_path
      end
    end
  end

  def current_user
    unless session[:dn].nil?
      unless @current_user.nil?
        return @current_user
      else
        begin
          return @current_user = User.find(session[:dn])
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
      password = ""
      user = authenticate_with_http_basic do |login, password|
        User.authenticate(login, password)
      end
      if user
        session[:dn] = user.dn
        session[:password_plaintext] = password
      else
        request_http_basic_authentication
      end
    else
      unless current_user
        store_location
        flash[:notice] = "You must be logged in"
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

  def theme
    # session[:theme] ? session[:theme] : "tea"
    "gray"
  end
end
