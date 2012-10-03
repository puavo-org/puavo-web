class ProfilesController < ApplicationController
  # skip_before_filter :ldap_setup_connection, :find_school, :login_required

  # GET /profile
  def edit

    @user = User.find( session[:dn] )
    
    respond_to do |format|
      format.html
    end
  end
end
