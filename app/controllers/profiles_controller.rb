class ProfilesController < ApplicationController
  include Puavo::Integrations

  skip_before_action :require_puavo_authorization

  # GET /profile/edit
  def edit
    setup_language

    @user = current_user
    @automatic_email_addresses, @automatic_email_domain = get_automatic_email_addresses

    respond_to do |format|
      format.html
    end
  end

  # PUT /profile
  def update
    # TODO:: Add delete profile photo button
    setup_language

    request_id = generate_synchronous_call_id()

    @user = current_user

    @automatic_email_addresses, @automatic_email_domain = get_automatic_email_addresses

    if @automatic_email_addresses
      params[:user].delete(:mail)
    end

    pp = profile_params
    modify_params = []

    # ldap_modify_operation() wants these in a weird array format
    modify_params << { 'mail' => pp['mail'] } unless @automatic_email_addresses
    modify_params << { 'telephoneNumber' => pp['telephoneNumber'] }

    if pp['puavoLocale'] && !pp['puavoLocale'].empty?
      modify_params << { 'puavoLocale' => pp['puavoLocale'] }
      modify_params << { 'preferredLanguage' => pp['puavoLocale'].match(/^[a-z]{2}/)[0] }
    else
      # Allow reset (ie. set to "default")
      modify_params << { 'puavoLocale' => '' }
      modify_params << { 'preferredLanguage' => '' }
    end

    if pp['jpegPhoto']
      begin
        modify_params << { 'jpegPhoto' => User.resize_image(pp['jpegPhoto'].path) }
      rescue => e
        logger.error("[#{request_id}] Could not resize the uploaded profile picture: #{e}")
        flash[:alert] = t('profiles.show.photo_failed')
      end
    end

    respond_to do |format|
      begin
        if @user.ldap_modify_operation(:replace, modify_params)
          flash[:notice] = t('profiles.show.updated')
          format.html { redirect_to(profile_path()) }
        else
          flash[:alert] = t('profiles.show.save_failed')
          format.html { redirect_to(profile_path()) }
        end
      rescue => e
        flash[:alert] = t('profiles.show.save_failed_code', :request_id => request_id)
        logger.error("[#{request_id}] Profile save failed: #{e}")
        format.html { redirect_to(profile_path()) }
      end
    end
  end

  # We get here after the profile has been updated
  def show
    respond_to do |format|
      format.html
    end
  end

  # GET /profile/image
  def image
    @user = current_user
    send_data @user.jpegPhoto, :disposition => 'inline', :type => 'image/jpeg'
  end

  private

  def profile_params
    params.require(:user).permit(
      :puavoLocale,
      :jpegPhoto,
      :telephoneNumber,
      :mail,
    ).to_h
  end

  def setup_language
    # use organisation default
    @language = nil

    # override
    if params[:lang] && ['en', 'fi', 'sv', 'de'].include?(params[:lang])
      I18n.locale = params[:lang]
      @language = params[:lang]
    end
  end
end
