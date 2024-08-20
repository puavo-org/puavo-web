require "addressable/uri"
require "sinatra/r18n"
require "sinatra/cookies"

require_relative "./users"

require_relative '../lib/login/utility'
require_relative '../lib/login/login_form'
require_relative '../lib/login/session'
require_relative '../lib/login/mfa'

module PuavoRest

class SSO < PuavoSinatra
  register Sinatra::R18n
  include PuavoLoginForm
  include PuavoLoginSession
  include PuavoLoginMFA

  # Prepares a JWT login
  def initialize_jwt_login(request_id, login_key, is_trusted_url)
    # Retrieve the external service we're trying to login into
    if return_to.nil?
      rlog.error("[#{request_id}] there's no \"return_to\" or \"return\" in the URL (#{request.url})")
      generic_error(t.sso.jwt_missing_return_url(request_id))
    end

    external_service = fetch_external_service

    if external_service.nil?
      rlog.error("[#{request_id}] no external service could be found by domain \"#{return_to()}\"")
      generic_error(t.sso.unknown_external_service(request_id))
    end

    rlog.info("[#{request_id}] attempting to log into external service \"#{external_service.name}\" (#{external_service.dn.to_s}), login data Redis key=\"#{login_key}\"")

    # Handle trusted/non-trusted services
    if external_service.trusted != is_trusted_url
      # No mix-and-matching of service types. A trusted service must use a trusted login URL
      # (/v3/verified_sso), and a non-trusted must use a non-trusted URL (/v3/sso).
      rlog.error("[#{request_id}] trusted service type mismatch (service trusted=#{external_service.trusted}, URL verified=#{is_trusted_url})")
      generic_error(t.sso.trusted_state_mismatch(request_id))
    end

    login_data = login_create_data(request_id, external_service, is_trusted: is_trusted_url, next_stage: '/v3/sso/jwt')
    login_data['return_to'] = return_to().to_s
    login_data['original_url'] = request.url.to_s

    # Is there a session for this service?
    session = session_try_login(request_id, external_service)
    login_data['had_session'] = session[:had_session]

    if session[:had_session] && session[:redirect]
      # Restore the relevant parts of the login data from the cached data
      login_data['organisation'] = session[:data]['organisation']
      login_data['user'] = session[:data]['user']
    end

    _login_redis.set(login_key, login_data.to_json, nx: true, ex: 60 * 2)

    if session[:redirect]
      return stage2(login_key, login_data)
    end
  end

  # Normal SSO login form
  get '/v3/sso' do
    request_id = make_request_id()
    login_key = SecureRandom.hex(8)

    begin
      initialize_jwt_login(request_id, login_key, false)
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

  # Verified SSO login form
  get '/v3/verified_sso' do
    request_id = make_request_id()
    login_key = SecureRandom.hex(8)

    begin
      initialize_jwt_login(request_id, login_key, true)
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

  get '/v3/sso/login' do
    sso_login_user_with_request_params(params.fetch('login_key', ''))
  end

  # Handle a normal SSO login form submission
  post '/v3/sso/login' do
    handle_login_form_post
  end

  # Handle a verified SSO login form submission
  post '/v3/verified_sso' do
    handle_login_form_post
  end

  # Stage 2 JWT login handler
  get '/v3/sso/jwt' do
    login_key = params.fetch('login_key', '')
    login_data = login_get_data(login_key)
    request_id = login_data['request_id']
    rlog.info("[#{request_id}] JWT login stage 2 init")

    puts login_data.inspect

    # TODO: Get the organisation, user and external service from LDAP again here
    # and construct the JWT hash, then do the redirect

    halt
  end

  # SSO session logout
  get '/v3/sso/logout' do
    session_try_logout
  end

  # Show the MFA form (cannot be reached directly, as you need a valid login key for it to work)
  get '/v3/mfa' do
    mfa_ask_code
  end

  # Handle the MFA form submission
  post '/v3/mfa' do
    mfa_check_code
  end

  # Developer documentation
  get '/v3/sso/developers' do
    @body = File.read('doc/SSO_DEVELOPERS.html')
    erb :developers, :layout => :layout
  end

  # Form helpers
  # TODO: These are unused?
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

private

  def return_to
    # Support "return_to" and "return"
    if params.include?('return_to')
      Addressable::URI.parse(params['return_to'])
    elsif params.include?('return')
      Addressable::URI.parse(params['return'])
    else
      nil
    end
  end

  def fetch_external_service
    # Support "return_to" and "return"
    if params.include?('return_to')
      ExternalService.by_url(params['return_to'])
    elsif params.include?('return')
      ExternalService.by_url(params['return'])
    else
      nil
    end
  end
end
end
