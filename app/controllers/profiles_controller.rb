class ProfilesController < ApplicationController
  # skip_before_filter :ldap_setup_connection, :find_school, :login_required

  # GET /profile/edit
  def edit

    @user = current_user

    @data_remote = true if params[:'data-remote']
    
    respond_to do |format|
      format.html
    end
  end

  # PUT /profile
  def update
    
    @user = current_user

    respond_to do |format|
      if @user.update_attributes(params[:user])
        flash[:notice] = t('flash.profile.updated')
        format.html { redirect_to( profile_path ) }
        format.js { render :text => 'window.close()' }
      else
        flash[:alert] = t('flash.profile.save_failed')
        format.html { render :action => "edit" }
        format.js
      end
    end
  end

  def show
    
    respond_to do |format|
      format.html
    end
  end
end
