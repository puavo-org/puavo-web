# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  include Puavo::AuthenticationHelper

  attr_reader :school
  helper_method :theme, :current_user, :current_organisation, :acquire_credentials, :setup_authentication, :perform_login, :require_login, :require_puavo_authorization, :show_authentication_error, :store_location, :redirect_back_or_default, :organisation_key_from_host, :set_organisation_to_session, :set_initial_locale, :remove_ldap_connection, :theme, :school_list, :rack_mount_point

  protect_from_forgery # See ActionController::RequestForgeryProtection for details

  before_filter :set_initial_locale
  before_filter :setup_authentication
  before_filter :require_login
  before_filter :require_puavo_authorization
  before_filter :set_organisation_to_session
  before_filter :log_request
  before_filter :find_school
  before_filter :set_menu

  after_filter :remove_ldap_connection


  def log_request
    flog.info "request"
  end

  def flog
    attrs = {
      :organisation_key => "NOT SET",
      :request => {
        :url => request.url,
        :method => request.method,
        :ip => env["HTTP_X_REAL_IP"]
      }
    }

    if current_organisation
      attrs[:organisation_key] = current_organisation.organisation_key
    end

    if @authenticated
      attrs[:user] = {
        :uid => current_user.uid,
        :dn => current_user.dn.to_s
      }
    end

    FLOG.merge(self.class.name, attrs)
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


end
