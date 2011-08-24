# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  before_filter :set_organisation_to_session, :set_locale
  helper_method :theme

  before_filter :ldap_setup_connection
  helper :all # include all helpers, all the time
  protect_from_forgery # See ActionController::RequestForgeryProtection for details
  helper_method :current_user, :ldap_setup_connection, :organisation_owner?

  before_filter :find_school
  before_filter :login_required
  before_filter :set_authorization_user

  after_filter :remove_ldap_connection

  filter_parameter_logging :password, :new_password, :new_password_confirmation

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
        flash[:error] = "Incorrect school id!"
        redirect_to schools_path
      end
    end
  end

  def theme
    session[:organisation].value_by_key('theme') or "gray"
  end
end
