require 'json'
require 'net/http'
require 'uri'

require_relative './errors'
require_relative './service'

module PuavoRest
  class ExternalUniventionService < ExternalLoginService
    def initialize(external_login, univention_config, service_name, rlog)
      super(external_login, service_name, rlog)

      server_uri = get_conf(univention_config, 'server_uri',
                            'univention server uri not configured')
      admin_username = get_conf(univention_config,
                                'admin_username',
                                'admin username not configured')
      admin_password = get_conf(univention_config,
                                'admin_password',
                                'admin password not configured')

      setup_univention_connection(server_uri, admin_username,
                                  admin_password)
    end

    def get_conf(config, key, errmsg)
      value = config[key]
      raise ExternalLoginConfigError, errmsg \
        unless value && value.kind_of?(String) && !value.empty?
      return value
    end

    def get_univention_token(server_uri, username, password)
      uri = URI("#{ server_uri }/ucsschool/kelvin/token")

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request.set_form_data('username' => username,
                            'password' => password)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE  # XXX

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess) then
        errmsg = "failure when requesting a token: #{ response.code }" \
                   + " #{ response.message } :: #{ response.body }"
        raise errmsg
      end

      parsed_response = JSON.parse(response.body)
      raise 'no access token received' \
        unless parsed_response['access_token'] \
                 && parsed_response['access_token'].kind_of?(String)
                 && !parsed_response['access_token'].empty?

      return parsed_response['access_token']
    end

    def lookup_all_users
      users = {}

      raise 'not implemented'

      return users
    end

    def univention_get_users
      # XXX
    end

    def setup_univention_connection(server_uri, username, password)
      @token = get_univention_token(server_uri, username, password)
    end
  end
end
