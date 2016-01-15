# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  include Puavo::AuthenticationHelper

  attr_reader :school
  helper_method( :theme, :current_user, :current_organisation,
                 :current_organisation?, :acquire_credentials,
                 :setup_authentication, :perform_login, :require_login,
                 :require_puavo_authorization,
                 :show_authentication_error, :store_location,
                 :redirect_back_or_default, :organisation_key_from_host,
                 :set_initial_locale, :remove_ldap_connection, :theme,
                 :school_list, :rack_mount_point, :password_management_host )

  protect_from_forgery # See ActionController::RequestForgeryProtection for details

  before_filter do
    response.headers["X-puavo-web-version"] = "#{ PuavoUsers::VERSION } #{ PuavoUsers::GIT_COMMIT }"
  end

  before_filter :set_initial_locale
  before_filter :setup_authentication
  before_filter :require_login
  before_filter :require_puavo_authorization
  before_filter :log_request
  before_filter :find_school
  before_filter :set_menu

  after_filter :remove_ldap_connection

  if ENV["RAILS_ENV"] == "production"
    rescue_from Exception do |error|
      @request = request
      @error = error
      @error_uuid = (0...25).map{ ('a'..'z').to_a[rand(26)] }.join
      flog.error("unhandled exception", {
        :parameters => params,
        :error => {
          :uuid => @error_uuid,
          :code => @error.class.name,
          :message => @error.message,
          :backtrace => @error.backtrace
        }
      })
      logger.error @error.message
      logger.error @error.backtrace.join("\n")

      render :status => 500, :layout => false, :template => "errors/sorry.html.erb"
    end
  end

  def log_request
    flog.info "request", :parameters => params
  end

  def user_store
    @user_store ||= Redis::Namespace.new(
      "puavo:user:#{ current_user.dn.to_s.downcase }",
      :redis => REDIS_CONNECTION
    )
  end

  def flog
    attrs = {
      :controller => self.class.name,
      :organisation_key => "NOT SET",
      :request => {
        :url => request.url,
        :method => request.method,
        :ip => env["HTTP_X_REAL_IP"]
      }
    }

    if current_organisation?
      attrs[:organisation_key] = current_organisation.organisation_key
    end

    if current_user?
      attrs[:credentials] = {
        :username => current_user.uid,
        :dn => current_user.dn.to_s.downcase!
      }
    end

    FLOG.merge(attrs)
  end

  # Cached schools query
  def school_list
    return @school_cache if @school_cache
    @school_cache = current_organisation.schools current_user
  end

  def rack_mount_point
    "/users"
  end

  def handle_date_multiparameter_attribute(object_params, attribute)
    if !object_params[:"#{attribute}(1i)"].nil? && !object_params[:"#{attribute}(1i)"].empty? &&
       !object_params[:"#{attribute}(2i)"].nil? && !object_params[:"#{attribute}(2i)"].empty? &&
       !object_params[:"#{attribute}(3i)"].nil? && !object_params[:"#{attribute}(3i)"].empty?

      object_params[attribute] = Time.local( object_params[:"#{attribute}(1i)"].to_i, 
                                             object_params[:"#{attribute}(2i)"].to_i,
                                             object_params[:"#{attribute}(3i)"].to_i )
    end
  end

  def puavo_users?
    # FIXME
    logger.warn "Deprecated call to puavo_users?"
    return true
    # PUAVO_CONFIG["puavo_users"] == "enabled" ? true : false
  end

  def password_management_host
    url = "http://" +
      Puavo::CONFIG["password_management"]["host"]

    if Puavo::CONFIG["password_management"]["port"]
      url += ":" + Puavo::CONFIG["password_management"]["port"].to_s
    end

    return url
  end

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
        flash[:alert] = "Incorrect school id!"
        redirect_to schools_path
      end
    end
  end

  def set_menu
    # TODO: Where this should be required?
    # It must be require after all controllers are defined
    require_relative "../../lib/puavo_menu"

    @menu_items = PuavoMenu.new(self).children
    @child_items = []
    @menu_items.each do |i|
      @child_items = i.children if i.active?
    end

  end

  # Render generic error page in the current url with a error message
  def render_error_page(msg="Unkown error")
    @error_message = msg
    render :status => 404, :template => "/errors/generic.html.erb"
  end

  def new_group_management?
    current_organisation.value_by_key("new_group_management")
  end
end
