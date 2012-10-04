class ProfilesController < ApplicationController
  # skip_before_filter :ldap_setup_connection, :find_school, :login_required

  # GET /profile
  def edit

    @user = User.find( session[:dn] )
    
    respond_to do |format|
      format.html
    end
  end

  # PUT /profile
  def update
    
    @user = User.find( session[:dn] )

    respond_to do |format|
      if @user.update_attributes(params[:user])
        flash[:notice] = t('flash.profile.updated')
        format.html { render :action => "edit" }
      else
        flash[:alert] = t('flash.profile.save_failed')
        format.html { render :action => "edit" }
      end
    end
  end
end
