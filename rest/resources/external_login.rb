require 'date'
require 'securerandom'

require_relative '../lib/external_login'

module PuavoRest
  class ExternalLogins < PuavoSinatra
    post '/v3/external_login/auth' do
      begin
        raise ExternalLoginWrongCredentials, 'no basic auth used' \
          unless env['HTTP_AUTHORIZATION']

        auth_type, auth_data = env['HTTP_AUTHORIZATION'].split(' ', 2)
        raise ExternalLoginWrongCredentials, 'no basic auth used' \
          unless auth_type == 'Basic'

        username, password = Base64.decode64(auth_data).split(':')
        if !username || username.empty? then
          raise ExternalLoginWrongCredentials, 'no username provided'
        end
        if !password || password.empty? then
          raise ExternalLoginWrongCredentials, 'no password provided'
        end

        user_status = ExternalLogin.auth(username, password, nil, params)
      rescue ExternalLoginWrongCredentials => e
        user_status = ExternalLogin.status_badusercreds(e.message)
      rescue StandardError => e
        raise InternalError, e
      end

      json_user_status = json(user_status)
      rlog.info("returning external login status #{ json_user_status }")
      return json_user_status
    end
  end
end
