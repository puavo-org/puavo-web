# Legacy JWT SSO system

require "addressable/uri"
require "sinatra/r18n"
require "sinatra/cookies"

require_relative "./users"

require_relative '../lib/login/utility'
require_relative '../lib/login/login_form'
require_relative '../lib/login/jwt'
require_relative '../lib/login/session'
require_relative '../lib/login/mfa'

module PuavoRest

class SSO < PuavoSinatra
  register Sinatra::R18n
  include PuavoLoginJWT
  include PuavoLoginForm
  include PuavoLoginSession
  include PuavoLoginMFA

  # Normal SSO login form
  get '/v3/sso' do
    jwt_begin(trusted: false)
  end

  get '/oidc/sso' do
    jwt_begin(trusted: false, was_oidc: true)
  end

  # Verified SSO login form
  get '/v3/verified_sso' do
    jwt_begin(trusted: true)
  end

  get '/oidc/verified_sso' do
    jwt_begin(trusted: true, was_oidc: true)
  end

  get '/v3/sso/login' do
    sso_login_user_with_request_params(params.fetch('login_key', ''))
  end

  get '/oidc/login' do
    sso_login_user_with_request_params(params.fetch('login_key', ''))
  end

  # Handle a normal SSO login form submission
  post '/v3/sso/login' do
    handle_login_form_post
  end

  post '/oidc/login' do
    handle_login_form_post
  end

  # Handle a verified SSO login form submission
  post '/v3/verified_sso' do
    handle_login_form_post
  end

  post '/oidc/verified_sso' do
    handle_login_form_post
  end

  # Stage 2 JWT login handler
  get '/v3/sso/jwt' do
    jwt_handle_stage2
  end

  get '/oidc/jwt' do
    jwt_handle_stage2
  end

  # Show the MFA form (cannot be reached directly, as you need a valid login key for it to work)
  get '/v3/mfa' do
    mfa_ask_code
  end

  get '/oidc/mfa' do
    mfa_ask_code
  end

  # Handle the MFA form submission
  post '/v3/mfa' do
    mfa_check_code
  end

  post '/oidc/mfa' do
    mfa_check_code
  end

  # JWT SSO session logout
  get '/v3/sso/logout' do
    session_try_logout
  end

  get '/oidc/logout' do
    session_try_logout
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

  def jwt_begin(trusted: false, was_oidc: false)
    request_id = make_request_id()
    login_key = SecureRandom.hex(64)

    if was_oidc
      rlog.info("[#{request_id}] Starting an OIDC path")
    else
      rlog.info("[#{request_id}] Starting a JWT path")
    end

    begin
      jwt_initialize_login(request_id, login_key, trusted, was_oidc)
      redirect was_oidc ? "/oidc/login?login_key=#{login_key}" : "/v3/sso/login?login_key=#{login_key}"
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
