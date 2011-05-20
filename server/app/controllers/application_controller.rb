# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  # puavo_organisation plugin
  before_filter :set_organisation_to_session, :set_locale
  helper_method :theme
  # puavo_authentication plugin
  before_filter :ldap_setup_connection, :login_required
  before_filter :set_authorization_user

  helper :all # include all helpers, all the time
  helper_method :logged_in?, :current_user_displayName, :organisation_owner?, :puavo_users?

  protect_from_forgery # See ActionController::RequestForgeryProtection for details

  # Scrub sensitive parameters from your log
  filter_parameter_logging :password, :new_password, :new_password_confirmation

  before_filter :find_school

  after_filter :remove_ldap_connection

  def find_school
    if params.has_key?(:school_id)
      school_id = params[:school_id]
    elsif controller_name == 'schools' && params.has_key?(:id)
      school_id = params[:id]
    end

    unless school_id.nil?
      begin
        @school = School.find(school_id)
      rescue Exception => e
        logger.info "Incorrect school id (#{school_id})! Redirected..."
        logger.debug "Exception: " + e
        flash[:notice] = "Incorrect school id!"
        #redirect_to devices_path
      end
    end
  end

  def current_user_displayName
    if logged_in?
      return current_user.displayName
    end
    ""
  end

  def logged_in?
    if defined?(current_user) == "method"
      current_user != nil
    end
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
    PUAVO_CONFIG["puavo_users"] == "enabled" ? true : false
  end
end
