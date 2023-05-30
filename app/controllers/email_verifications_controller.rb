class EmailVerificationsController < ApplicationController
  include Puavo::Integrations

  # I don't know 100% if this works:
  skip_before_action :find_school, :require_login, :require_puavo_authorization

  # Method stolen from password_controller.rb, then modified a bit
  def set_ldap_connection(req_host)
    # Make the password forms work on staging servers
    if req_host.start_with?('staging-')
      req_host.remove!('staging-')
    end

    organisation_key = Puavo::Organisation.key_by_host(req_host)

    unless organisation_key
      organisation_key = Puavo::Organisation.key_by_host("*")
    end

    default_ldap_configuration = ActiveLdap::Base.ensure_configuration
    organisation = Puavo::Organisation.find(organisation_key)
    host = organisation.ldap_host
    base = organisation.ldap_base
    dn =  default_ldap_configuration["bind_dn"]
    password = default_ldap_configuration["password"]
    LdapBase.ldap_setup_connection(host, base, dn, password)
  end

  # GET /email_verification/:token
  def edit
    @request_id = generate_synchronous_call_id()
    @token = params['token']
    @invalid_token = false

    @language = params['lang'] || nil
    I18n.locale = params['lang'] || nil

    logger.info("[#{@request_id}] Opening email verification form for token \"#{@token}\"")
    logger.info("[#{@request_id}] Client IP: #{request.ip}  UserAgent: \"#{request.user_agent}\"")

    @data = redis_connect.get(@token)

    if @data.nil?
      logger.error("[#{@request_id}] ERROR: No stored data found in Redis")
      @invalid_token = true
    else
      begin
        @data = JSON.parse(@data)

        if @data
          # If the token isn't valid, we only display an error message
          set_ldap_connection(@data['organisation'])
          @organisation = LdapOrganisation.first
          I18n.locale = params['lang'] || nil
        end
      rescue StandardError => e
        logger.error("[#{@request_id}] ERROR: Cannot parse the stored data: #{e}")
        logger.error("[#{@request_id}] Raw token data: #{@data.inspect}")
        @invalid_token = true
      end
    end

    respond_to do |format|
      format.html
    end
  end

  # PUT /email_verification/:token
  def update
    request_id = generate_synchronous_call_id()
    token = params['token']
    I18n.locale = params['lang'] || nil

    logger.info("[#{request_id}] Confirming email verification, token \"#{token}\"")
    logger.info("[#{request_id}] Client IP: #{request.ip}  UserAgent: \"#{request.user_agent}\"")

    # Get data from Redis
    redis = redis_connect
    data = redis.get(token)

    if data.nil?
      logger.error("[#{request_id}] ERROR: No stored data found in Redis")
      flash[:alert] = t('email_verifications.expired_token', code: request_id)
    else
      begin
        data = JSON.parse(data)
      rescue StandardError => e
        logger.error("[#{request_id}] ERROR: Cannot parse the stored data: #{e}")
        logger.error("[#{request_id}] Raw token data: #{data.inspect}")
        flash[:alert] = t('email_verifications.expired_token', code: request_id)
        data = nil
      end
    end

    # Verify the address
    if data
      begin
        logger.info("[#{request_id}] Marking address \"#{data['email']}\" as verified for user \"#{data['dn']}\" (#{data['uid']}) in organisation \"#{data['organisation']}\"")

        verify_url = email_management_host + '/email_verification/verify'
        logger.info("[#{request_id}] Sending request to \"#{email_management_host}\"")

        rest_response = HTTP
          .headers(host: data['organisation'])
          .put(verify_url, json: {
            request_id: request_id,
            username: data['uid'],
            dn: data['dn'],
            email: data['email'],
          })

        if rest_response.status == 200
          logger.info("[#{request_id}] The address has been verified, removing Redis data")
          redis.del(token)
          flash[:notice] = t('email_verifications.verification_complete')
        else
          logger.error("[#{request_id}] ERROR: Received an error status: #{rest_response.inspect}")
          flash.clear
          flash[:alert] = t('email_verifications.verification_failed', code: request_id)
        end
      rescue StandardError => e
        logger.error("[#{request_id}] ERROR: Failed to mark the address as verified: #{e}")
        flash.clear
        flash[:alert] = t('email_verifications.verification_failed', code: request_id)
      end
    end

    respond_to do |format|
      format.html { redirect_to(email_verification_completed_path()) }
    end
  end

  private

  def redis_connect
    Redis::Namespace.new('puavo:email_verification:tokens', redis: REDIS_CONNECTION)
  end
end
