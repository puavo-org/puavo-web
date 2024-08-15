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

  # Normal SSO login form
  get '/v3/sso' do
  end

  # Verified SSO login form
  get '/v3/verified_sso' do
  end

  # Handle a normal SSO login form submission
  post '/v3/sso' do
    handle_login_form_post
  end

  # Handle a verified SSO login form submission
  post '/v3/verified_sso' do
    handle_login_form_post
  end

  # SSO session logout
  get '/v3/sso/logout' do
    session_try_logout
  end

  # Show the MFA form (cannot be reached directly, as you need a valid login state for it to work)
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
