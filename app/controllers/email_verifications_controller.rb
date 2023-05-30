class EmailVerificationsController < ApplicationController
  include Puavo::Integrations

  skip_before_action :require_puavo_authorization

  # GET /email_verification/:token
  def edit
    @organisation = LdapOrganisation.current.cn
    @user = current_user    # needed by the form constructor

    @request_id = generate_synchronous_call_id()
    @token = params['token']
    @invalid_token = false

    logger.info("[#{@request_id}] Opening email verification form for token \"#{@token}\"")
    logger.info("[#{@request_id}] Client IP: #{request.ip}  UserAgent: \"#{request.user_agent}\"")

    @data = redis_connect.get(@token)

    if @data.nil?
      logger.error("[#{@request_id}] ERROR: No stored data found in Redis")
      @invalid_token = true
    else
      begin
        @data = JSON.parse(@data)

        # Verify the logged-in user is still the same whose data we stored earlier
        if @data['dn'] != @user.dn.to_s
          logger.error("[#{@request_id}] ERROR: DN mismatch between the stored data in Redis and the current user (the current logged-in user is not the same who created the request?)")
          logger.error("[#{@request_id}] Raw token data: #{@data.inspect}")
          logger.error("[#{@request_id}] Current user DN: #{current_user.dn.to_s}")
          @invalid_token = true
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
