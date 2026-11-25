# The remote recovery of one device, kept by puavo-rest. Calls are made
# with the credentials of the signed in person.
class DeviceRecovery
  CODE_GROUP_LENGTH = 4
  NO_RECOVERY_ERROR_CODE = 'RecoveryRequestNotFound'
  RECOVERABLE_DEVICE_TYPES = ['laptop', 'bootserver'].freeze

  # puavo-rest refused or failed to answer.
  class CallFailed < StandardError
    attr_reader :error_code

    # @param error_code [String, nil] puavo-rest's error code, or nil when
    #   it failed to answer
    def initialize(error_code)
      super("device recovery failed: #{ error_code }")
      @error_code = error_code
    end
  end

  # @param device [Device, Server] a device of Puavo Web
  # @return [Boolean] true when its type has remote recovery
  def self.offered_for?(device)
    RECOVERABLE_DEVICE_TYPES.include?(device.puavoDeviceType)
  end

  # @param code [String] the code as puavo-rest gives it
  # @return [String] the code as people read it, for example "ABCD EFGH"
  def self.readable_code(code)
    code.scan(/.{1,#{ CODE_GROUP_LENGTH }}/).join(' ')
  end

  # @param hostname [String] the hostname of the device
  # @param user_dn [String] the DN of the signed in person
  # @param password [String] the password of the signed in person
  def initialize(hostname, user_dn, password)
    @proxy = LdapOrganisation.current.rest_proxy(user_dn, password)
    @path = "/v3/devices/#{ ERB::Util.url_encode(hostname) }/recovery"
  end

  # @return [Hash, nil] the recovery as its owner sees it, or nil when the
  #   device has none
  # @raise [CallFailed] when puavo-rest refused or failed to answer
  def find
    call_puavo_rest(:get)
  rescue CallFailed => error
    return nil if error.error_code == NO_RECOVERY_ERROR_CODE

    raise
  end

  # Opens a recovery of the device. An earlier one ends.
  # @return [Hash] the code, serial number, state and expiry
  # @raise [CallFailed] when puavo-rest refused or failed to answer
  def open
    call_puavo_rest(:post)
  end

  # Closes the recovery of the device.
  # @raise [CallFailed] when puavo-rest refused or failed to answer
  def close
    call_puavo_rest(:delete)
  end

  private

  # @param method [Symbol] :get, :post or :delete on the recovery of the
  #   device
  # @return [Hash, nil] the answer, or nil when it has no body
  # @raise [CallFailed] when puavo-rest refused or failed to answer
  def call_puavo_rest(method)
    body = @proxy.request(method, @path).body.to_s
    body.empty? ? nil : JSON.parse(body)
  rescue PuavoRestProxy::BadStatus => error
    raise CallFailed.new(error_code_of(error.response))
  rescue HTTP::Error
    raise CallFailed.new(nil)
  end

  # @param response [HTTP::Response] a refusal of puavo-rest
  # @return [String, nil] its error code, or nil when it has none
  def error_code_of(response)
    JSON.parse(response.body.to_s).dig('error', 'code')
  rescue JSON::ParserError
    nil
  end
end
