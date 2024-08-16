require 'securerandom'

require_relative '../lib/login/utility'
require_relative '../lib/login/login_form'
require_relative '../lib/login/session'
require_relative '../lib/login/mfa'

module PuavoRest

class OpenIDConnect < PuavoSinatra
  register Sinatra::R18n
  include PuavoLoginForm
  include PuavoLoginSession
  include PuavoLoginMFA

  get '/oidc/authorize' do
    request_id = make_request_id
    oidc_config = CONFIG['openid_connect'].freeze

    $rest_log.info("[#{request_id}] New OpenID Connect authentication request")

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

    unless oidc_config['clients'].include?(client_id)
      $rest_log.error("[#{request_id}] Unknown/invalid client")
      status 403
      return
    end

    client_config = oidc_config['clients'][client_id]

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

    oidc_data = {
      'request_id' => request_id,
      'redirect_url' => redirect_uri,
      'scopes' => scopes,
      'state' => params.fetch('state', nil),
    }

    if params.include?('nonce')
      oidc_data['nonce'] = params['nonce']
    end

    login_key = SecureRandom.hex(8)

    begin
      # TODO: Determine the service from the client ID, not URL
      external_service = ExternalService.by_url('XXX')

      login_data = login_create_data(request_id, external_service, false, '/oidc/stage2')
      login_data['oidc'] = oidc_data

      _login_redis.set(login_key, login_data.to_json, nx: true, ex: 60 * 2)
      redirect "/v3/sso/login?login_key=#{login_key}"
    rescue StandardError => e
      # WARNING: This resuce block can only handle exceptions that happen *before* the
      # login form is rendered, because the login form renderer halts and never comes
      # back to this method.
      rlog.error("[#{request_id}] Unhandled exception in the SSO system: #{e}")
      rlog.error("[#{request_id}] #{e.backtrace.join("\n")}")
      login_clear_data(login_key)
      generic_error(t.sso.unspecified_error(request_id))
    end

    # Unreachable
  end

  get '/oidc/stage2' do
    login_key = params.fetch('login_key', '')
    login_data = login_get_data(login_key)
    request_id = login_data['request_id']
    rlog.info("[#{request_id}] OpenID Connect login stage 2 init")

    puts login_data.inspect

    halt
  end

private
  def _oidc_redis
    Redis::Namespace.new('oidc_session', redis: REDIS_CONNECTION)
  end

  # FIXME: It should not be necessary to duplicate these, especially when they're just
  # dummy placeholders (which should be fixed too)
  helpers do
    def raw(string)
      return string
    end

    def token_tag(token)
      # FIXME
    end

    def form_authenticity_token
      # FIXME
    end
  end

end

end   # module PuavoRest
