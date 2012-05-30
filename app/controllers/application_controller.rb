# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  before_filter :set_organisation_to_session, :set_locale
  helper_method :theme, :school_list

  helper :all # include all helpers, all the time
  protect_from_forgery # See ActionController::RequestForgeryProtection for details
  helper_method :current_user

  before_filter :setup_authentication
  before_filter :require_login
  before_filter :require_puavo_authorization
  before_filter :find_school

  after_filter :remove_ldap_connection

  filter_parameter_logging :password, :new_password, :new_password_confirmation

  # Cached schools query
  def school_list
    return @school_cache if @school_cache
    @school_cache = session[:organisation].schools current_user
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

  def theme
    session[:organisation].value_by_key('theme') or "breathe"
  end


end
