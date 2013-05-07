class ProfilesController < ApplicationController
  skip_before_filter :require_puavo_authorization

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
    
    # Create params for ldap replace operation.
    modify_params = params[:user].select{ |k,v| !v.empty? }.inject([]) do |result, attribute|
      # FIXME: Is there a better solutions?
      key = String.new(attribute.first)
      key.force_encoding('utf-8')
      result.push key => attribute.last
    end

    respond_to do |format|
      if @user.ldap_modify_operation( :replace, modify_params )
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
