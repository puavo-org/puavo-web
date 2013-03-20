# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  include Puavo::AuthenticationHelper

  helper_method :theme, :current_user, :current_organisation, :acquire_credentials, :setup_authentication, :perform_login, :require_login, :require_puavo_authorization, :show_authentication_error, :store_location, :redirect_back_or_default, :organisation_key_from_host, :set_organisation_to_session, :set_initial_locale, :remove_ldap_connection, :theme, :school_list

  protect_from_forgery # See ActionController::RequestForgeryProtection for details

  before_filter :set_initial_locale
  before_filter :setup_authentication
  before_filter :require_login
  before_filter :require_puavo_authorization
  before_filter :set_organisation_to_session
  before_filter :find_school

  after_filter :remove_ldap_connection

  # Cached schools query
  def school_list
    return @school_cache if @school_cache
    @school_cache = current_organisation.schools current_user
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



end
