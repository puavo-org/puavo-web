class ProfilesController < ApplicationController
  include Puavo::Integrations

  skip_before_action :require_puavo_authorization

  # GET /profile/edit
  def edit
    setup_language
    @user = current_user
    @organisation = LdapOrganisation.current.cn
    @automatic_email_addresses, @automatic_email_domain = get_automatic_email_addresses

    @have_something_to_verify = !(Array(@user.mail || []) - Array(@user.puavoVerifiedEmail || [])).empty?

    respond_to do |format|
      format.html
    end
  end

  # GET /profile/image
  def image
    @user = current_user
    send_data @user.jpegPhoto, disposition: 'inline', type: 'image/jpeg'
  end

  # POST /profile/send_verification_email
  def send_verification_email
    request_id = generate_synchronous_call_id()

    result = {
      request_id: request_id,
      success: false,
      message: nil
    }

    begin
      data = JSON.parse(request.body.read.strip)

      address = data['address']
      language = data['language']
      I18n.locale = language

      logger.info("[#{request_id}] User \"#{current_user.uid}\" (#{current_user.dn.to_s}) in organisation " \
                  "\"#{LdapOrganisation.current.cn}\" has requested a verification email to be sent to \"#{address}\"")
      logger.info("[#{request_id}] Client IP: #{request.ip}  UserAgent: \"#{request.user_agent}\"")

      if current_user.puavoVerifiedEmail && current_user.puavoVerifiedEmail.include?(address)
        logger.error("[#{request_id}] This address has already been verified!")
        raise t('profiles.edit.emails.errors.already_verified')
      end

      # You need rate limits every time you deal with emails
      redis_ratelimit = Redis::Namespace.new('puavo:email_verification:ratelimit', redis: REDIS_CONNECTION)

      if redis_ratelimit.get(current_user.puavoId.to_s)
        logger.info("[#{request_id}] A rate-limit flag is active for user #{current_user.puavoId}, stopping here")
        raise t('profiles.edit.emails.errors.verification_rate_limit', code: request_id)
      end

      # This is where the user data is stored in Redis
      redis_token = SecureRandom.hex(64)
      logger.info("[#{request_id}] Redis token: \"#{redis_token}\"")

      verify_url = email_management_host + '/email_verification/send'
      logger.info("[#{request_id}] Requesting \"#{email_management_host}\" to send the verification email")

      rest_response = HTTP
        .headers(host: LdapOrganisation.current.puavoDomain)
        .post(verify_url, json: {
          request_id: request_id,
          first_name: current_user.givenName,
          username: current_user.uid,
          dn: current_user.dn.to_s,
          email: address,
          token: redis_token,
          language: language,
        })

      if rest_response.status == 200
        logger.info("[#{request_id}] The email was sent, saving verification data in Redis")

        # Store the reset data in Redis
        data = {
          organisation: LdapOrganisation.current.puavoDomain,
          uid: current_user.uid,
          dn: current_user.dn.to_s,
          email: address,
        }

        redis_tokens = Redis::Namespace.new('puavo:email_verification:tokens', redis: REDIS_CONNECTION)
        redis_tokens.set(redis_token, data.to_json, nx: true, ex: 60 * 60)
        redis_ratelimit.set(current_user.puavoId.to_s, true, nx: false, ex: 60)
        logger.info("[#{request_id}] Redis data created")

        result[:success] = true
      else
        logger.info("[#{request_id}] The email was NOT sent, received a #{rest_response.status} response")
        result[:message] = t('profiles.edit.emails.errors.verification_not_sent', code: request_id)
      end
    rescue StandardError => e
      logger.error("[#{request_id}] ERROR: #{e}")

      result[:success] = false
      result[:message] = e
    end

    render json: result
  end

  # PUT /profile
  def update
    setup_language
    @request_id = generate_synchronous_call_id()
    @user = current_user

    @automatic_email_addresses, _ = get_automatic_email_addresses

    if @automatic_email_addresses
      # These addresses are automatic and cannot be changed. They can be verified, however.
      params[:user].delete(:mail)
    end

    @params = profile_params
    failed = []

    unless @automatic_email_addresses
      current_addresses = Array(@user.mail || []).to_set
      new_addresses = @params['mail'].split(' ')

      if current_addresses != new_addresses.to_set
        # There are changes in the addresses, send a save request to the verification server.
        # Normal user accounts do not have write access to these fields.
        change_url = email_management_host + '/email_verification/change_addresses'
        logger.info("[#{@request_id}] Email addresses have changed, requesting \"#{email_management_host}\" to change them")

        rest_response = HTTP
          .headers(host: LdapOrganisation.current.puavoDomain)
          .post(change_url, json: {
            request_id: @request_id,
            username: current_user.uid,
            dn: current_user.dn.to_s,
            emails: new_addresses
          })

        puts rest_response.inspect

        if rest_response.status == 200
          logger.info("[#{@request_id}] The email addresses were updated")
        else
          logger.info("[#{@request_id}] The email addresses were NOT updated:")
          logger.info("[#{@request_id}] #{rest_response.inspect}")
          failed << t('profiles.failed.email')
        end
      end
    end

    update_phone_number(failed)
    update_locale(failed)
    update_photo(failed)

    respond_to do |format|
      if failed.empty?
        flash[:notice] = t('profiles.show.updated')
        format.html { redirect_to(profile_path(lang: @language)) }
      else
        flash[:alert] = t('profiles.show.partially_failed_code', request_id: @request_id, failed: failed.join(', '))
        format.html { redirect_to(profile_path(lang: @language)) }
      end
    end
  end

  # We get here after the profile has been updated
  def show
    setup_language

    respond_to do |format|
      format.html
    end
  end

  private

  def update_phone_number(failed)
    return unless @params.include?('telephoneNumber')

    modify = []

    if @params['telephoneNumber'].nil? || @params['telephoneNumber'].strip.empty?
      modify << { 'telephoneNumber' => [] }
    else
      n = @params['telephoneNumber'].strip
      modify << { 'telephoneNumber' => n } unless n.strip == '-'
    end

    begin
      @user.ldap_modify_operation(:replace, modify)
    rescue StandardError => e
      logger.error("[#{@request_id}] Could not save the phone number: #{e}")
      failed << t('profiles.failed.phone')
      false
    end
  end

  def update_locale(failed)
    return unless @params.include?('puavoLocale')

    modify = []

    if @params['puavoLocale'].nil? || @params['puavoLocale'].empty?
      modify << { 'puavoLocale' => [] }
      modify << { 'preferredLanguage' => [] }
    else
      modify << { 'puavoLocale' => @params['puavoLocale'] }
      modify << { 'preferredLanguage' => @params['puavoLocale'].match(/^[a-z]{2}/)[0] }
    end

    begin
      @user.ldap_modify_operation(:replace, modify)
    rescue StandardError => e
      logger.error("[#{@request_id}] Could not update the locale: #{e}")
      failed << t('profiles.failed.locale')
      false
    end
  end

  def update_photo(failed)
    modify = []

    if @params.include?('jpegPhoto')
      begin
        modify << { 'jpegPhoto' => User.resize_image(@params['jpegPhoto'].path) }
      rescue => e
        logger.error("[#{@request_id}] Could not resize the uploaded profile picture: #{e}")
        failed << t('profiles.failed.photo_save')
        return false
      end
    end

    if @params.include?('removePhoto')
      modify << { 'jpegPhoto' => [] }
    end

    begin
      @user.ldap_modify_operation(:replace, modify)
    rescue StandardError => e
      logger.error("[#{@request_id}] Could not update the profile picture: #{e}")
      false
    end
  end

  def profile_params
    params.require(:user).permit(
      :puavoLocale,
      :jpegPhoto,
      :telephoneNumber,
      :mail,
      :removePhoto
    ).to_h
  end

  def setup_language
    # use organisation default
    @language = I18n.locale

    # override
    if params[:lang] && ['en', 'fi', 'sv', 'de'].include?(params[:lang])
      I18n.locale = params[:lang]
      @language = params[:lang]
    end
  end
end
