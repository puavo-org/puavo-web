require 'json'
require 'net/http'
require 'uri'

require_relative './errors'
require_relative './service'

class UniventionRequestError < StandardError
  attr_reader :response

  def initialize(response)
    @response = response
    super("Error with response: #{ response.message }")
  end
end

module PuavoRest
  class ExternalUniventionService < ExternalLoginService
    def initialize(external_login, univention_config, service_name, rlog)
      super(external_login, service_name, rlog)

      raise 'manage puavousers is not set to true' \
        unless external_login.manage_puavousers

      @extlogin_id_field \
        = get_conf_string(univention_config,
                          'extlogin_id_field',
                          'univention extlogin id field not configured')
      @extschool_id_field \
        = get_conf_string(univention_config,
                          'extschool_id_field',
                          'univention extschool id field not configured')
      @external_username_field \
        = get_conf_string(univention_config,
                          'external_username_field',
                          'univention extlogin name field not configured')
      @server_uri = get_conf_string(univention_config, 'server_uri',
                                    'univention server uri not configured')

      admin_username = get_conf_string(univention_config,
                                       'admin_username',
                                       'admin username not configured')
      admin_password = get_conf_string(univention_config,
                                       'admin_password',
                                       'admin password not configured')

      @puavo_schools_by_id = get_puavoschools_by_id()
      @univention_schools_by_url = {}

      setup_univention_connection(@server_uri, admin_username,
                                  admin_password)
    end

    def get_conf_string(config, key, errmsg)
      value = config[key]
      raise ExternalLoginConfigError, errmsg \
        unless value.kind_of?(String) && !value.empty?
      return value
    end

    def get_puavoschools_by_id()
      puavo_schools_by_id = {}

      School.all.each do |school|
        external_school_id = @external_login.extschool_id(school)
        next unless external_school_id.kind_of?(String)
        puavo_schools_by_id[external_school_id] = school
      end

      return puavo_schools_by_id
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
        unless parsed_response['access_token'].kind_of?(String) \
                 && !parsed_response['access_token'].empty?

      return parsed_response['access_token']
    end

    def get_userinfo(username)
      raise 'univention userinfo not set' \
        unless @username && @univention_userinfo

      puavo_extlogin_id_field = @external_login.puavo_extlogin_id_field
      userinfo = {
        puavo_extlogin_id_field => lookup_extlogin_id_by_username(username),
        'first_name' => @univention_userinfo['firstname'],
        'last_name'  => @univention_userinfo['lastname'],
        'username'   => username,
      }

      if !userinfo['first_name'] || userinfo['first_name'].empty? then
        raise ExternalLoginUnavailable,
              "User '#{ username }' has no first name in Univention"
      end

      if !userinfo['last_name'] || userinfo['last_name'].empty? then
        raise ExternalLoginUnavailable,
              "User '#{ username }' has no last name in Univention"
      end

      if !userinfo['username'] || userinfo['username'].empty? then
        raise ExternalLoginUnavailable,
              "User '#{ username }' has no account name in Univention"
      end

      # we apply some magicks to determine user school, groups and roles
      add_roles_and_schools!(userinfo)

      return userinfo
    end

    def add_roles_and_schools!(userinfo)
      added_school_dns  = []
      external_groups   = {
                            'administrative group' => {},
                            'teaching group'       => {},
                            'year class'           => {},
                          }
      primary_school_dn = nil

      added_roles = get_user_roles()
      added_school_dns = get_user_puavo_school_dns()

      userinfo['external_groups'] = external_groups
      userinfo['roles']           = added_roles.sort.uniq
      userinfo['school_dns']      = added_school_dns.sort.uniq

      # XXX could we look this up in a different way?
      primary_school_dn = userinfo['school_dns'].first
      userinfo['primary_school_dn'] = primary_school_dn
    end

    def get_user_roles()
      user_roles = []

      ucsschool_roles = @univention_userinfo['ucsschool_roles']
      raise 'user has no roles in UCS@school' \
        unless ucsschool_roles.kind_of?(Array) && !ucsschool_roles.empty?

      # UCS@school supports separate roles for each school but Puavo does
      # not, so dismiss school information in roles
      ucsschool_roles.each do |ucs_role|
        case ucs_role
          when /\Alegal_guardian:/
            user_roles << 'parent'
          when /\Astaff:/
            user_roles << 'staff'
          when /\Astudent:/
            user_roles << 'student'
          when /\Ateacher:/
            user_roles << 'teacher'
        end
      end

      raise 'user has no roles in UCS@school that actually exist in Puavo' \
        if user_roles.empty?

      return user_roles
    end

    def get_univention_school_info(uri_string)
      return do_univention_json_request_with_token(uri_string)
    end

    def get_user_puavo_school_dns()
      user_univention_school_urls = @univention_userinfo['schools']
      check_schools = lambda do
                        user_univention_school_urls.any? do |url|
                          !@univention_schools_by_url.has_key?(url)
                        end
                      end
      update_univention_schools_by_url() if check_schools.call()
      raise 'user is in an unknown school' if check_schools.call()

      user_univention_schools \
        = @univention_schools_by_url.values_at(*user_univention_school_urls)

      user_puavo_schools = []
      @univention_schools_by_url.each do |school_url, univention_school_info|
        extschool_id = get_univention_attribute(univention_school_info,
                                                @extschool_id_field)
        # XXX if not found, some warning should be raised?
        next unless extschool_id
        puavo_school = @puavo_schools_by_id[extschool_id]
        # XXX if not found, some warning should be raised?
        user_puavo_schools << puavo_school if puavo_school
      end

      user_puavo_schools.map { |s| s.dn }
    end

    def lookup_all_users
      users = {}
      update_univention_schools_by_url()

      univention_user_list = univention_get_users()
      univention_user_list.each do |univention_user|
        extlogin_id = get_univention_attribute(univention_user,
                                               @extlogin_id_field)
        next unless extlogin_id.kind_of?(String)

        username = univention_user[@external_username_field]
        next unless username.kind_of?(String)

        users[ extlogin_id ] = {
          'user_entry' => univention_user,
          'username'   => username,
        }
      end

      return users
    end

    def get_univention_attribute(univention_object, attribute)
      attribute == 'univentionObjectIdentifier'            \
        ? univention_object.dig('udm_properties', attribute) \
        : univention_object.dig(attribute)
    end

    def lookup_extlogin_id_by_username(username)
      update_univentionuserinfo(username)

      extlogin_id = get_univention_attribute(@univention_userinfo,
                                             @extlogin_id_field)
      if !extlogin_id || extlogin_id.empty? then
        raise(ExternalLoginUnavailable,
              "could not lookup extlogin id (#{ @extlogin_id_field })" \
                + " for user '#{ username }'")
      end

      extlogin_id
    end

    def set_userinfo(username, univention_userinfo)
      @username = username
      @univention_userinfo = univention_userinfo
    end

    def setup_univention_connection(server_uri, username, password)
      @token = get_univention_token(server_uri, username, password)
    end

    def do_univention_json_request_with_token(uri_string)
      uri = URI(uri_string)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{ @token }"
      request['Content-Type'] = 'application/json'

      response = do_http_request(uri, request)
      raise UniventionRequestError.new(response) \
        unless response.is_a?(Net::HTTPSuccess)

      return JSON.parse(response.body)
    end

    def univention_get_schools_by_url
      schools_by_url = {}

      school_list = univention_get_something('/ucsschool/kelvin/v1/schools/',
                                             'schools')
      school_list.each do |school|
        url = school['url']
        next unless url.kind_of?(String)        # XXX what if this is not?
        schools_by_url[url] = school
      end

      return schools_by_url
    end

    def univention_get_something(subpath, something)
      uri_string = "#{ @server_uri }#{ subpath }"
      begin
        return do_univention_json_request_with_token(uri_string)
      rescue UniventionRequestError => e
        raise "failure when requesting #{ something }: #{ e.response.code }" \
                + " #{ e.response.message } :: #{ e.response.body }"
      end
    end

    def univention_get_users
      univention_get_something('/ucsschool/kelvin/v1/users/', 'users')
    end

    def update_univention_schools_by_url()
      @univention_schools_by_url = univention_get_schools_by_url()
    end

    def update_univentionuserinfo(username)
      # XXX no-op but may be needed later?
      return
    end
  end
end
