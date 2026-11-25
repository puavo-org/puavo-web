# The approval of a request, signed in the name of the owner who opened
# the recovery. The key service checks it with the public half of the
# configured key.

require 'jwt'
require 'openssl'

module PuavoRest

module RecoveryApproval
  AUDIENCE = 'puavo-kps'
  ALGORITHM = 'ES256'
  CURVE = 'prime256v1'

  # A wrong key stops puavo-rest at start, not at the first join.
  PRIVATE_KEY = OpenSSL::PKey.read(
    File.read(CONFIG['recovery']['approval_private_key']))
  unless PRIVATE_KEY.is_a?(OpenSSL::PKey::EC) &&
         PRIVATE_KEY.group.curve_name == CURVE
    raise ArgumentError, 'failed to use approval_private_key: not an EC P 256 key'
  end

  # Signs the approval of the joined request, which expires with the
  # record.
  # @param recovery [DeviceRecovery] the recovery with its joined request
  # @return [String] the approval as a compact JWT
  def self.sign(recovery)
    config = CONFIG['recovery']

    claims = {
      'iss' => config['approval_issuer'],
      'aud' => AUDIENCE,
      'jti' => recovery['id'],
      'iat' => Time.now.to_i,
      'exp' => recovery['expires_at'],
      'organisation_id' => recovery['organisation_id'],
      'serial_number' => recovery['serial_number'],
      'digest' => recovery['digest'],
      'approver' => recovery['opened_by'],
    }

    header = { 'typ' => 'JWT', 'kid' => config['approval_key_id'] }
    JWT.encode(claims, PRIVATE_KEY, ALGORITHM, header)
  end
end

end
