# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  helper :all # include all helpers, all the time
  helper_method :logged_in?, :current_user_displayName
  protect_from_forgery # See ActionController::RequestForgeryProtection for details

  # Scrub sensitive parameters from your log
  # filter_parameter_logging :password

  before_filter :set_organisation_to_session, :set_locale
  if defined?(Puavo::Authentication)
    before_filter :ldap_setup_connection, :login_required
  end
  before_filter :find_school

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
end
