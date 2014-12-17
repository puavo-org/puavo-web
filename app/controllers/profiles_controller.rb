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

    # TODO:: Add delete profile photo button

    @user = current_user

    current_confirm_emails = Array(@user.mail)
    @new_emails = params[:user][:mail].empty? ? [] : Array(params[:user][:mail])

    # If params not include old email, user like to remove it
    current_confirm_emails.delete_if{ |email| not @new_emails.include?(email) }
    params[:user][:mail] = current_confirm_emails

    # List of new email addresses. Require user confirm
    @new_emails.delete_if{ |email| current_confirm_emails.include?(email) }

    # Create params for ldap replace operation.
    modify_params = params[:user].select do |key, value|
      # do not update empty form values
      !value.to_s.empty?
    end.map do |attribute|

      # XXX: to avoid encoding issues with scandinavian chars
      key = String.new(attribute.first)
      key.force_encoding('utf-8')

      value = attribute.last

      if key == "jpegPhoto"
        value = User.resize_image(value.path)
      end

      { key => value }
    end

    # FIXME should be use User model
    if params[:user][:puavoLocale] && !params[:user][:puavoLocale].empty?
      modify_params.push({ "preferredLanguage" => params[:user][:puavoLocale].match(/^[a-z]{2}/)[0] })
    end

    respond_to do |format|
      if @user.ldap_modify_operation( :replace, modify_params )
        # Send confirm message to all new email address
        email_confirm_url = password_management_host + "/email_confirm"
        @new_emails.each do |email|
          rest_response = HTTP.with_headers("Host" => request.host.to_s.gsub(/^staging\-/, ""),
                                            "Accept-Language" => locale)
            .post(email_confirm_url,
                  :form => {
                    :username => @user.uid,
                    :email => email
                  })

          raise RestConnectionError if rest_response.status != 200
        end

        flash[:notice] = t('flash.profile.updated')
        format.html { redirect_to( profile_path(:emails => @new_emails) ) }
        format.js { render :text => 'window.close()' }
      else
        flash[:alert] = t('flash.profile.save_failed')
        format.html { render :action => "edit" }
        format.js
      end
    end
  end

  def show
    @new_emails = params[:emails].nil? ? [] : params[:emails]
    
    respond_to do |format|
      format.html
    end
  end

  # GET /profile/image
  def image
    @user = current_user

    send_data @user.jpegPhoto, :disposition => 'inline', :type => "image/jpeg"
  end

end
