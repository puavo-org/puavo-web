# The multi-factor authentication editor

class MfasController < ApplicationController
  include Puavo::Integrations     # request ID generation
  include Puavo::MFA              # MFA server request helper

  skip_before_action :require_puavo_authorization

  before_action do
    # We need this on every call anyway
    @request_id = generate_synchronous_call_id
  end

  # GET /mfa
  # List the existing authenticators for the current user (if any), and provide an interface
  # for creating new ones
  def show
    @organisation = LdapOrganisation.current
    @user = current_user

    unless @user.puavoUuid
      # This should not happen in production, but it has to be handled
      logger.error("[#{@request_id}] can't open the MFA editor, because the user does not have puavoUuid")
      @missing_uuid = true
    else
      @authenticators = get_authenticators(@user.puavoUuid)
    end

    # Append a "return to" link if we know where the user came from. For example, if the user's coming
    # from the profile editor, without this link they won't be able to go back there.
    if params.include?('return_to') && %w[profile puavo].include?(params['return_to'])
      @return_to = params['return_to']
    end

    respond_to do |format|
      format.html
    end
  end

  # ------------------------------------------------------------------------------------------------
  # Authentication methods

  # POST /mfa/prepare
  # Creates a new TOTP MFA key and encodes it in a QR code. The key must be verified separately.
  def prepare_totp
    mfa_operation do |result|
      result.merge!({
        keyid: nil,
        secret: nil,
        qr: nil
      })

      # Generate a new TOTP key. It has to be validated and activated separately.
      response, data = Puavo::MFA.mfa_call(@request_id, :post, 'totp/add', data: {
        'userid' => @user.puavoUuid,
        'description' => @request_data['description'][0..30]
      })

      logger.info("[#{@request_id}] MFA server response ID: #{response.headers['X-Request-ID']}")

      if response.code != 201 || data['status'] != 'success'
        unhandled_mfa_server_response('prepare(): could not request a new code from the MFA server', result, response, data)
        next
      end

      secret = data['data']['totpsecret']

      # Generate a TOTP URL...
      issuer = Puavo::CONFIG.fetch('branding', {}).fetch('manufacturer', {}).fetch('mfa_issuer', '?')
      organisation = LdapOrganisation.current.cn

      name = ERB::Util.url_encode(organisation)
      url = "otpauth://totp/#{name}?issuer=#{issuer}&secret=#{secret}"

      # ...and store it in a QR code
      stdout, stderr, status = Open3.capture3("qrencode --level M --margin=1 --type SVG --svg-path --rle \"#{url}\"")

      if status.exitstatus != 0
        logger.error("[#{@request_id}] prepare(): qrencode failed with code #{status.exitstatus}, stderr: #{stderr}")
        result[:message] = t('.server.errors.qr_code_generation_failed', request_id: @request_id)
      else
        result[:success] = true
        result[:keyid] = data['data']['keyid']
        result[:secret] = secret
        result[:qr] = 'data:image/svg+xml;base64,' + Base64.encode64(stdout)
      end
    end
  end

  # POST /mfa/verify
  # Checks if the selected MFA method works, and if it does, activates it. Upon success, returns a
  # new list of currently active authenticators.
  def verify
    mfa_operation do |result|
      result.merge!({
        code_ok: false,
        reused_key: false,
        authenticators: nil
      })

      type = @request_data['type']

      data = {
        'userid' => @user.puavoUuid,
        'code' => @request_data['code'],
      }

      case type
        when 'totp'
          data.merge!({
            'keyid' => @request_data['keyid']
          })

          url = 'totp/verify'

        when 'yubikey'
          data.merge!({
            'code' => @request_data['code'],
            'description' => @request_data['description']
          })

          url = 'yubikey/add'

        else
          raise "verify(): unknown key type \"#{type}\""
      end

      response, data = Puavo::MFA.mfa_call(@request_id, :post, url, data: data)
      logger.info("[#{@request_id}] MFA server response ID: #{response.headers['X-Request-ID']}")

      case type
        when 'totp'
          if response.code == 200 && data['status'] == 'success'
            # The TOTP code was valid
            result[:success] = true
            result[:code_ok] = true
          elsif response.code == 403 && data['status'] == 'fail'
            # The TOTP code was not valid
            result[:success] = true
          end

        when 'yubikey'
          if response.code == 201 && data['status'] == 'success'
            # The Yubikey input was valid
            result[:success] = true
            result[:code_ok] = true
          elsif response.code == 400 && data['status'] == 'error'
            # The Yubikey input was not valid
            result[:success] = true
          elsif response.code == 409 && data['status'] == 'error'
            # This Yubikey is already in use
            result[:success] = true
            result[:reused_key] = true
            result[:message] = t('.server.errors.yubikey_already_in_use')
          end
      end

      unless result[:success]
        unhandled_mfa_server_response('verify(): could not verify the code', result, response, data)
      else
        # Update the authenticator list
        authenticators = get_authenticators(@user.puavoUuid)

        if authenticators.nil?
          # Eh, it's a partial success
          result[:authenticators] = nil
        else
          result[:authenticators] = authenticators
        end

        # Activate MFA logins on the first time
        unless @user.puavoMFAEnabled
          logger.info("[#{@request_id}] a new MFA authentication method was added for this user, but MFA is not yet active on them, activating it")

          unless set_mfa_state(@user, true)
            result[:success] = false
            result[:message] = t('.server.errors.mfa_activation_error', request_id: @request_id)
          end
        end
      end
    end
  end

  # DELETE /mfa/delete
  # Deactivates an MFA authentication method. Returns a list of remaining authenticators
  # if successfull.
  def delete
    mfa_operation do |result|
      result.merge!({
        authenticators: nil
      })

      response, data = Puavo::MFA.mfa_call(@request_id, :delete, "keys/#{@user.puavoUuid}/#{@request_data['keyid']}")
      logger.info("[#{@request_id}] MFA server response ID: #{response.headers['X-Request-ID']}")

      if response.code == 200 && data['status'] == 'success'
        # Key deleted. Update the list of remaining authenticators.
        result[:success] = true

        authenticators = get_authenticators(@user.puavoUuid)

        if authenticators.nil?
          # The error message will be formatted in the client end
          logger.error("[#{@request_id}] delete(): could not get a list of current authenticators")
        else
          result[:authenticators] = authenticators
        end

        # Disable MFA logins when the last authenticator is deleted
        # FIXME: This will fail loudly if we couldn't get the list of remaining authenticators
        # (because 'authenticators' will be nil) but maybe that's okay?
        if @user.puavoMFAEnabled && authenticators[:keys].empty?
          logger.info("[#{@request_id}] the last remaining MFA authenticator was removed, deactivating MFA for this user")

          unless set_mfa_state(@user, false)
            result[:success] = false
            result[:message] = t('.server.errors.mfa_deactivation_error', request_id: @request_id)
          else
            # Delete the recovery keys too (all authenticators have been deleted). Calling mfa_operation() inside
            # mfa_operation() would cause a double rendering error, so there's no error handling here.
            logger.info("[#{@request_id}] all authenticators deleted, removing the recovery keys (if any)")
            response, data = Puavo::MFA.mfa_call(@request_id, :delete, "recovery/keys/#{@user.puavoUuid}")

            unless response.code == 200 && data['status'] == 'success'
              logger.error("[#{@request_id}] failed to delete the recovery keys:")
              logger.error("[#{@request_id}] #{data.inspect}")
            else
              # Clear the keys
              result[:authenticators][:have_recovery_keys] = false
            end
          end
        end
      elsif response.code == 404 && data['status'] == 'error'
        # Invalid key ID
        logger.error("[#{@request_id}] delete(): invalid key ID \"#{@request_data['keyid']}\", key not deleted")
        result[:message] = t('.server.errors.invalid_key', request_id: @request_id)
      else
        unhandled_mfa_server_response('delete(): could not delete the specified key', result, response, data)
      end
    end
  end

  # ------------------------------------------------------------------------------------------------
  # Recovery keys

  # GET /mfa/list_recovery_keys
  # List existing recovery keys
  def list_recovery_keys
    mfa_operation(body_data: false) do |result|
      result.merge!({
        keys: []
      })

      response, data = Puavo::MFA.mfa_call(@request_id, :get, "recovery/keys/#{@user.puavoUuid}")
      logger.info("[#{@request_id}] MFA server response ID: #{response.headers['X-Request-ID']}")

      if response.code == 200 && data['status'] == 'success'
        result[:success] = true
        result[:keys] = data['data']['recoverykeys']
      else
        unhandled_mfa_server_response('list_recovery_keys(): could not list the recovery keys', result, response, data)
      end
    end
  end

  # POST /mfa/create_recovery_keys
  # Create a new set of recovery keys
  def create_recovery_keys
    mfa_operation(body_data: false) do |result|
      result.merge!({
        keys: []
      })

      response, data = Puavo::MFA.mfa_call(@request_id, :post, 'recovery/create', data: {
        'userid' => @user.puavoUuid
      })

      logger.info("[#{@request_id}] MFA server response ID: #{response.headers['X-Request-ID']}")

      if response.code == 201 && data['status'] == 'success'
        result[:success] = true
        result[:keys] = data['data']['recoverykeys']
      else
        unhandled_mfa_server_response('create_recovery_keys(): could not create new recovery keys', result, response, data)
      end
    end
  end

  # DELETE /mfa/recovery_keys
  # Delete existing recovery keys
  def delete_recovery_keys
    mfa_operation(body_data: false) do |result|
      result.merge!({
        keys: []
      })

      response, data = Puavo::MFA.mfa_call(@request_id, :delete, "recovery/keys/#{@user.puavoUuid}")
      logger.info("[#{@request_id}] MFA server response ID: #{response.headers['X-Request-ID']}")

      if response.code == 200 && data['status'] == 'success'
        result[:success] = true
      else
        unhandled_mfa_server_response('delete_recovery_keys(): could not delete the recovery keys', result, response, data)
      end
    end
  end

  # ------------------------------------------------------------------------------------------------
  # Utility

  private

  # A common "template" for all MFA AJAX call handlers. Handles common parameters and errors in
  # a unified way. This always returns JSON. NOTE: never 'return' in the block! If you have to
  # end it prematurely, use "next".
  def mfa_operation(body_data: true, &block)
    # The standard output template. Add fields to this if needed.
    result = {
      success: false,
      message: nil,
    }

    begin
      @user = current_user

      # Not all operations receive data in the body
      if body_data
        @post_body = request.body.read
        @request_data = @post_body.nil? ? nil : JSON.parse(@post_body)
      end

      block.call(result)
    rescue HTTP::ConnectionError => e
      logger.error("[#{@request_id}] can't connect to the MFA server: #{e}")
      result[:message] = t('.server.errors.mfa_server_not_responding', request_id: @request_id)
    rescue StandardError => e
      logger.error("[#{@request_id}] unhandled exception in mfa_operation(): #{e}")
      logger.error("[#{@request_id}] #{e.backtrace.join("\n")}")
      result[:message] = t('.server.errors.unknown_server_error', request_id: @request_id)
    end

    render json: result
  end

  def get_authenticators(uuid)
    response, data = Puavo::MFA.mfa_call(@request_id, :get, "keys/#{uuid}")
      logger.info("[#{@request_id}] MFA server response ID: #{response.headers['X-Request-ID']}")

    if response.status != 200 || data['status'] != 'success'
      logger.error("[#{@request_id}] get_authenticators(): unhandled MFA server response: #{response.inspect}")
      logger.error("[#{@request_id}]   #{data.inspect}")
      return nil
    end

    # Move the key IDs inside the hashes, flatten the structure, and sort the keys by
    # creation time (oldest first)
    keys = data['data']['keys']
      .collect { |key_id, key_data| { 'key_id' => key_id }.merge(key_data) }
      .sort { |key| key['key_added'] }
      .reverse

    return {
      keys: keys,
      have_recovery_keys: data['data']['hasrecoverykeys'],
    }
  rescue HTTP::ConnectionError => e
    logger.error("[#{@request_id}] get_authenticators(): Can't connect to the MFA server: #{e}")
    nil
  rescue StandardError => e
    logger.error("[#{@request_id}] get_authenticators(): MFA server connection raised an exception: #{e}")
    nil
  end

  # Only one place has a write access to puavoMFAEnabled attribute, so call it and ask
  # for a favor
  def set_mfa_state(user, state)
    mfa_url = URI::HTTP.build(
      host: Puavo::CONFIG['mfa_management']['host'],
      port: Puavo::CONFIG['mfa_management']['port'],
      path: '/v3/mfa/change_state'
    )

    auth = Puavo::CONFIG.fetch('mfa_management', {}).fetch('auth', {})

    response = HTTP
      .basic_auth(user: auth['username'], pass: auth['password'])
      .headers(host: LdapOrganisation.current.puavoDomain)
      .post(mfa_url, json: {
        request_id: @request_id,
        user_dn: user.dn.to_s,
        user_uuid: user.puavoUuid,
        mfa_state: state
      })

    if response.status != 200
      logger.error("[#{@request_id}] set_mfa_state(): could not change the MFA state for user:")
      logger.error("[#{@request_id}]   #{response.inspect}")
      logger.error("[#{@request_id}]   #{response.body.to_s}")
      false
    else
      true
    end
  rescue StandardError => e
    logger.error("[#{@request_id}] set_mfa_state(): unhandled exception: #{e}")
    false
  end

  # All unhandled MFA server responses use the same format
  def unhandled_mfa_server_response(message, result, response, data)
    logger.error("[#{@request_id}] #{message}")
    logger.error("[#{@request_id}]   #{response.inspect}") if response
    logger.error("[#{@request_id}]   #{data.inspect}") if data
    result[:message] = t('.server.errors.unknown_server_error', request_id: @request_id)
  end
end
