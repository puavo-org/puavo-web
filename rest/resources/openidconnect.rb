require 'securerandom'

module PuavoRest

# TODO: Move this to the main config
OIDC_CONFIG = {
  'clients' => {
    'devel' => {
      'redirect_uris' => [
        'https://openidconnect.net/callback',
      ],
    },
  },
}.freeze

class OpenIDConnect < PuavoSinatra
  get '/oidc/authorize' do
    request_id = make_request_id

    $rest_log.info("[#{request_id}] New OpenIDConnect authentication request")

    puts params.inspect

    # ----------------------------------------------------------------------------------------------
    # Check response type

    response_type = params.fetch('response_type', nil)

    unless response_type == 'code'
      $rest_log.error("[#{request_id}] Unknown response type \"#{response_type}\", don't know how to handle it")
      status 400
      return
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client ID

    client_id = params.fetch('client_id', nil)

    $rest_log.info("[#{request_id}] client_id=\"#{client_id}\"")

    unless OIDC_CONFIG['clients'].include?(client_id)
      $rest_log.error("[#{request_id}] Unknown/invalid client")
      status 403
      return
    end

    client_config = OIDC_CONFIG['clients'][client_id].freeze

    # ----------------------------------------------------------------------------------------------
    # Verify the redirect URL(s)

    redirect_uri = params['redirect_uri']

    if client_config.fetch('redirect_uris', []).find { |uri| uri == redirect_uri }.nil?
      $rest_log.error("[#{request_id}] Redirect URI \"#{redirect_uri}\" is not allowed")
      status 403
      return
    end

    # ----------------------------------------------------------------------------------------------
    # Verify scopes

    scopes = params.fetch('scope', '').split(' ')

    unless scopes.include?('openid')
      $rest_log.error("[#{request_id}] No 'openid' found in scopes (#{scopes.inspect})")
      status 400
      return
    end

    # ----------------------------------------------------------------------------------------------
    # Build Redis data

    data = {
      'redirect_url' => redirect_uri,
      'scopes' => scopes,
      'state' => params.fetch('state', nil),
    }

    if params.include?('nonce')
      data['nonce'] = params['nonce']
    end

    # Stash the data in Redis
    key = SecureRandom.hex(64)

    redis = _oidc_redis()
    redis.set("authorize:#{key}", data, nx: true, ex: PUAVO_OIDC_LOGIN_TIME)

    # TODO: Put the user verification/login step here

    status 200
  end

private
  # TODO: Move this to the root class?
  def make_request_id
    'ABCDEGIJKLMOQRUWXYZ12346789'.split('').sample(10).join
  end

  def _oidc_redis
    Redis::Namespace.new('oidc_session', redis: REDIS_CONNECTION)
  end

end

end   # module PuavoRest
