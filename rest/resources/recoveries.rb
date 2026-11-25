require 'base64'
require 'time'

require_relative '../lib/device_recovery'
require_relative '../lib/recovery_approval'

module PuavoRest

# Remote recovery of devices that failed to unlock their disk. An
# organisation owner opens a recovery of a device, the device joins with
# the code of the opening, and the key service fetches the request and
# returns the key encrypted to the device.
class Recoveries < PuavoSinatra
  KEY_SERVICE_SCOPE = 'puavo.recovery.kps'
  RECOVERABLE_DEVICE_TYPES = ['laptop', 'bootserver'].freeze
  JSON_CONTENT_TYPE = 'application/json'

  # Device calls. No credentials: the request id is the device's secret.

  post '/v3/recovery/requests' do
    serial_number = text_param('serial_number')
    code = text_param('code')
    request_fields = {
      'organisation_id' => text_param('organisation_id'),
      'bundle' => binary_param('bundle', DeviceRecovery::MAX_BUNDLE_SIZE),
      'return_public_key' => binary_param(
        'return_public_key', DeviceRecovery::MAX_RETURN_KEY_SIZE),
    }
    require_return_key(request_fields['return_public_key'])

    # A device without a recovery is answered before LDAP is read and
    # before the lock is taken.
    domain = Organisation.current.domain
    DeviceRecovery.find(domain, serial_number)

    # The same answer as for no recovery, so a guesser learns nothing. Not
    # counted as a wrong code: the code was not tried.
    if request_fields['organisation_id'] != own_organisation_id
      raise RecoveryRequestNotFound, user: 'no such recovery'
    end

    outcome = nil
    recovery = DeviceRecovery.lock(domain, serial_number) do |locked_recovery|
      if locked_recovery.nil?
        raise RecoveryRequestNotFound, user: 'no such recovery'
      end

      outcome = locked_recovery.join(code, request_fields)
    end

    rlog.info("recovery of serial #{ serial_number.inspect } joined: " \
              "#{ outcome }")
    status(outcome == DeviceRecovery::JoinOutcome::REPEATED ? 200 : 201)
    json recovery.device_view.slice('id', 'state', 'expires_at',
                                    'poll_seconds')
  end

  get '/v3/recovery/requests/:id' do
    json find_own_request.device_view
  end

  delete '/v3/recovery/requests/:id' do
    id = params['id']
    recovery = DeviceRecovery.lock_by_request_id(id) do |locked_recovery|
      require_own_organisation(locked_recovery)
      locked_recovery.cancel
    end

    rlog.info("recovery request of serial " \
              "#{ recovery['serial_number'].inspect } deleted by the device")
    status 200
  end

  # Opening calls, made by Puavo Web as the signed in person.

  post '/v3/devices/:hostname/recovery' do
    auth :basic_auth
    require_owner

    device = Host.by_hostname!(params['hostname'])
    unless RECOVERABLE_DEVICE_TYPES.include?(device.type)
      raise UnsupportedDeviceType,
            user: "remote recovery is not for the device type #{ device.type }"
    end

    serial_number = serial_number_of(device)
    opened_by = User.current.username
    recovery = DeviceRecovery.open(Organisation.current.domain,
                                   serial_number, opened_by)

    rlog.info("recovery of #{ params['hostname'] } opened by #{ opened_by }")
    json recovery.owner_view.slice('code', 'serial_number', 'state',
                                   'expires_at')
  end

  get '/v3/devices/:hostname/recovery' do
    auth :basic_auth
    require_owner

    json DeviceRecovery.find(Organisation.current.domain,
                             device_serial_number).owner_view
  end

  delete '/v3/devices/:hostname/recovery' do
    auth :basic_auth
    require_owner

    DeviceRecovery.close(Organisation.current.domain, device_serial_number)
    rlog.info("recovery of #{ params['hostname'] } closed by " \
              "#{ User.current.username }")
    status 200
  end

  # Key service calls, with an OAuth 2 access token from the client
  # credentials grant.

  get '/v3/recovery/queue' do
    oauth2 scopes: [KEY_SERVICE_SCOPE]
    auth :oauth2_token

    queued = DeviceRecovery.oldest_queued_requests(allowed_domains)
    json({ 'requests' => queued.map(&:key_service_view) })
  end

  put '/v3/recovery/requests/:id/result' do
    oauth2 scopes: [KEY_SERVICE_SCOPE]
    auth :oauth2_token

    error = key_service_error
    if error && body_params.key?('result')
      raise BadInput, user: 'either result or error, not both'
    end

    unless error
      result = Base64.strict_encode64(
        binary_param('result', DeviceRecovery::MAX_RESULT_SIZE))
    end
    domains = allowed_domains

    id = params['id']
    recovery = DeviceRecovery.lock_by_request_id(id) do |locked_recovery|
      if domains && !domains.include?(locked_recovery['domain'])
        raise RecoveryRequestNotFound, user: 'no such recovery request'
      end

      if error
        locked_recovery.store_error(error)
      else
        locked_recovery.store_result(result)
      end
    end

    rlog.info("recovery request of serial " \
              "#{ recovery['serial_number'].inspect } #{ recovery['state'] }")
    json({ 'state' => recovery['state'] })
  end

  private

  # @return [Array<String>, nil] the organisation domains the key service
  #   token serves, or nil for all
  def allowed_domains
    LdapModel.settings[:credentials][:access_token]
             .fetch('allowed_organisations', nil)
  end

  # @return [Hash] the body, which must be a JSON object
  # @raise [BadInput] when it is not
  def body_params
    return @body_params if @body_params

    unless request.content_type.to_s.downcase.start_with?(JSON_CONTENT_TYPE)
      raise BadInput, user: 'the body must be JSON'
    end

    parsed = JSON.parse(request.body.read)
    unless parsed.is_a?(Hash)
      raise BadInput, user: 'the body must be a JSON object'
    end

    @body_params = parsed
  rescue JSON::ParserError
    raise BadInput, user: 'the body is not JSON'
  end

  # @param name [String] a field of the body
  # @return [String] its text
  # @raise [BadInput] when it is missing, empty or too long
  def text_param(name)
    text_value(body_params, name)
  end

  # @param object [Hash] a JSON object
  # @param name [String] a field of it
  # @return [String] its text
  # @raise [BadInput] when it is missing, empty or too long
  def text_value(object, name)
    value = object[name]
    if !value.is_a?(String) || value.empty? ||
       value.bytesize > DeviceRecovery::MAX_TEXT_FIELD_SIZE
      raise BadInput, user: "#{ name } is missing or malformed"
    end

    value
  end

  # @param name [String] a base64 field of the body
  # @param max_size [Integer] the most bytes it may hold
  # @return [String] its bytes
  # @raise [BadInput] when it is missing, empty, too large or not base64
  def binary_param(name, max_size)
    encoded = body_params[name]
    raise BadInput, user: "#{ name } is missing" unless encoded.is_a?(String)

    value = Base64.strict_decode64(encoded)
    if value.empty? || value.bytesize > max_size
      raise BadInput, user: "#{ name } is empty or too large"
    end

    value
  rescue ArgumentError
    raise BadInput, user: "#{ name } is not base64"
  end

  # Accepts only an RSA public key of the agreed size and exponent, as DER
  # SubjectPublicKeyInfo.
  # @param return_key_der [String] the return key of the device, binary
  # @raise [BadInput] when it is anything else
  def require_return_key(return_key_der)
    key = OpenSSL::PKey.read(return_key_der)
    if key.public_to_der != return_key_der || !key.is_a?(OpenSSL::PKey::RSA) ||
       key.n.num_bits != DeviceRecovery::RETURN_KEY_BITS ||
       key.e != DeviceRecovery::RETURN_KEY_EXPONENT
      bits = DeviceRecovery::RETURN_KEY_BITS
      raise BadInput, user: "return_public_key is not an RSA #{ bits } key"
    end
  rescue OpenSSL::PKey::PKeyError
    raise BadInput, user: 'return_public_key is not a public key'
  end

  # @return [Hash, nil] the error the key service reports instead of a
  #   result, with 'code' and 'message', or nil
  # @raise [BadInput] when it is malformed
  def key_service_error
    error = body_params['error']
    return nil if error.nil?
    raise BadInput, user: 'error must be an object' unless error.is_a?(Hash)

    message = error['message']
    if !message.is_a?(String) ||
       message.bytesize > DeviceRecovery::MAX_TEXT_FIELD_SIZE
      raise BadInput, user: 'error message is missing or too long'
    end

    { 'code' => text_value(error, 'code'), 'message' => message }
  end

  # @return [DeviceRecovery] the recovery that holds the request whose id is
  #   in the path, in this organisation
  # @raise [RecoveryRequestNotFound] when there is none
  def find_own_request
    recovery = DeviceRecovery.find_by_request_id(params['id'])
    require_own_organisation(recovery)
    recovery
  end

  # @param recovery [DeviceRecovery]
  # @raise [RecoveryRequestNotFound] when it is of another organisation
  def require_own_organisation(recovery)
    return if recovery['domain'] == Organisation.current.domain

    raise RecoveryRequestNotFound, user: 'no such recovery request'
  end

  # The organisation id inside the organisation's recovery public key,
  # read fresh because the key may change after puavo-rest started.
  # @return [String, nil]
  def own_organisation_id
    organisation = LdapModel.setup(credentials: CONFIG['server']) do
      Organisation.current(:no_cache)
    end

    key = organisation.device_recovery_public_key
    key.is_a?(Hash) ? key['organisation_id'] : nil
  end

  # @raise [Forbidden] when the signed in person is not an owner
  def require_owner
    return if Organisation.current(:no_cache).owner.include?(User.current.dn)

    raise Forbidden, user: 'only organisation owners open recoveries'
  end

  # @return [String] the serial number of the device whose hostname is in
  #   the path
  # @raise [DeviceWithoutSerialNumber] when it has none
  def device_serial_number
    serial_number_of(Host.by_hostname!(params['hostname']))
  end

  # @param device [Device, BootServer]
  # @return [String] its serial number
  # @raise [DeviceWithoutSerialNumber] when it has none
  def serial_number_of(device)
    serial_number = device.serial_number
    if serial_number.to_s.empty?
      raise DeviceWithoutSerialNumber, user: 'the device has no serial number'
    end

    serial_number
  end
end

end
