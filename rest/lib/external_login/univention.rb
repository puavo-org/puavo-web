require 'json'
require 'net/http'
require 'uri'

require_relative './errors'
require_relative './service'

module PuavoRest
  class ExternalUniventionService < ExternalLoginService
    def initialize(external_login, univention_config, service_name, rlog)
      super(external_login, service_name, rlog)

      @extlogin_id_field \
        = get_conf(univention_config,
                   'extlogin_id_field',
                   'univention extlogin id field not configured')
      @external_username_field \
        = get_conf(univention_config,
                   'external_username_field',
                   'univention extlogin name field not configured')
      @server_uri = get_conf(univention_config, 'server_uri',
                             'univention server uri not configured')

      admin_username = get_conf(univention_config,
                                'admin_username',
                                'admin username not configured')
      admin_password = get_conf(univention_config,
                                'admin_password',
                                'admin password not configured')

      setup_univention_connection(@server_uri, admin_username,
                                  admin_password)
    end

    def get_conf(config, key, errmsg)
      value = config[key]
      raise ExternalLoginConfigError, errmsg \
        unless value && value.kind_of?(String) && !value.empty?
      return value
    end

    def do_http_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE  # XXX
      http.request(request)
    end

    def get_univention_token(server_uri, username, password)
      uri = URI("#{ server_uri }/ucsschool/kelvin/token")

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request.set_form_data('username' => username,
                            'password' => password)

      response = do_http_request(uri, request)
      unless response.is_a?(Net::HTTPSuccess) then
        errmsg = "failure when requesting a token: #{ response.code }" \
                   + " #{ response.message } :: #{ response.body }"
        raise errmsg
      end

      parsed_response = JSON.parse(response.body)
      raise 'no access token received' \
        unless parsed_response['access_token']                       \
                 && parsed_response['access_token'].kind_of?(String) \
                 && !parsed_response['access_token'].empty?

      return parsed_response['access_token']
    end

    def lookup_all_users
      users = {}

      univention_user_list = univention_get_users()
      univention_user_list.each do |univention_user|
        extlogin_id = univention_user[@extlogin_id_field]
        next unless extlogin_id.kind_of?(String)

        username = univention_user[@external_username_field]
        next unless username.kind_of?(String)

        users[ extlogin_id ] = {
          'user_entry' => univention_user,
          'username'   => username,
        }
      end

      p users
      raise 'not implemented'

      return users
    end

    def univention_get_users
      uri = URI("#{ @server_uri }/ucsschool/kelvin/v1/users/")

      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{ @token }"
      request['Content-Type'] = 'application/json'

      response = do_http_request(uri, request)
      unless response.is_a?(Net::HTTPSuccess) then
        errmsg = "failure when requesting users: #{ response.code }" \
                   + " #{ response.message } :: #{ response.body }"
        raise errmsg
      end

      return JSON.parse(response.body)
    end

    def setup_univention_connection(server_uri, username, password)
      @token = get_univention_token(server_uri, username, password)
    end
  end
end
