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
  module Univention
    def self.do_http_request(uri, request, read_timeout=nil)
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = read_timeout if read_timeout
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE  # XXX
      http.request(request)
    end

    def self.get_conf_string(config, key, errmsg)
      value = config[key]
      raise ExternalLoginConfigError, errmsg \
        unless value.kind_of?(String) && !value.empty?
      return value
    end
  end

  class ExternalUniventionService < ExternalLoginService
    attr_reader :kelvin, :provisioning

    def initialize(external_login, univention_config, service_name, rlog)
      super(external_login, service_name, rlog)

      raise 'manage puavousers is not set to true' \
        unless external_login.manage_puavousers

      @extlogin_id_field \
        = Univention::get_conf_string(univention_config,
                                      'extlogin_id_field',
                                      'univention extlogin id field not configured')
      @extschool_id_field \
        = Univention::get_conf_string(univention_config,
                                      'extschool_id_field',
                                      'univention extschool id field not configured')
      @external_username_field \
        = Univention::get_conf_string(univention_config,
                                      'external_username_field',
                                      'univention extlogin name field not configured')
      server_uri = Univention::get_conf_string(univention_config,
                     'server_uri', 'univention server uri not configured')

      admin_username = Univention::get_conf_string(univention_config,
                                                   'admin_username',
                                                   'admin username not configured')
      admin_password = Univention::get_conf_string(univention_config,
                                                   'admin_password',
                                                   'admin password not configured')
      @kelvin = Kelvin.new(server_uri, admin_username, admin_password, rlog)

      raise 'no provisioning configration' \
        unless univention_config['provisioning'].kind_of?(Hash)
      @provisioning = Provisioning.new(self,
                                       server_uri,
                                       univention_config['provisioning'],
                                       rlog)

      @puavo_schools_by_id = nil
      @univention_schools_by_url = {}

      @kelvin.setup_connection()
    end

    def change_password(actor_username, actor_password, target_user_username,
                        target_user_password)
      # XXX Do nothing.  Should this actually do something?
    end

    def get_puavo_schools_by_id()
      puavo_schools_by_id = {}

      School.all.each do |school|
        external_school_id = @external_login.extschool_id(school)
        (puavo_schools_by_id[external_school_id] ||= []) << school
      end

      return puavo_schools_by_id
    end

    def get_userinfo(username)
      raise 'univention userinfo not set' \
        unless @username && @univention_userinfo

      get_attr = lambda do |attr|
                   get_univention_attribute(@univention_userinfo, attr)
                 end

      puavo_extlogin_id_field = @external_login.puavo_extlogin_id_field
      userinfo = {
        puavo_extlogin_id_field => get_attr.call(@extlogin_id_field),
        'first_name'            => get_attr.call('firstname'),
        'last_name'             => get_attr.call('lastname'),
        'ldap_password_hash'    => get_attr.call('userPasswordHash'),
        'username'              => username,
      }

      check_attr = lambda do |field, msg|
                     raise(ExternalLoginUnavailable, msg) \
                       unless userinfo[field] && !userinfo[field].empty?
                   end

      check_attr.call(puavo_extlogin_id_field,
                      "User '#{ username }' has no extlogin id in Univention")
      check_attr.call('first_name',
                      "User '#{ username }' has no first name in Univention")
      check_attr.call('last_name',
                      "User '#{ username }' has no last name in Univention")
      check_attr.call('ldap_password_hash',
                      "User '#{ username }' has no ldap password in Univention")
      check_attr.call('username',
                      "User '#{ username }' has no account name in Univention")

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

    def get_user_puavo_school_dns()
      update_puavo_schools_by_id()

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
        puavo_schools = @puavo_schools_by_id[extschool_id]
        user_puavo_schools += puavo_schools if puavo_schools
      end

      user_puavo_schools.map { |s| s.dn }
    end

    def update_school_information_and_report_connections()
      update_puavo_schools_by_id()
      update_univention_schools_by_url()

      @rlog.info('>> reporting school linkages')

      current_puavo_schools_by_id = @puavo_schools_by_id.clone

      @univention_schools_by_url.each do |school_url, univention_school_info|
        extschool_id = get_univention_attribute(univention_school_info,
                                                @extschool_id_field)
        msg = %Q{> Univention school "#{ univention_school_info['name'] }"} \
                + " (#{ extschool_id })"
        puavo_schools = current_puavo_schools_by_id.delete(extschool_id)
        if puavo_schools then
          school_names = puavo_schools.map { |s| %Q{"#{ s.name }"} }
          msg += " is connected to puavo schools: #{ school_names.join(', ') }"
        else
          msg += ' is not connected to any Puavo school'
        end
        @rlog.info(msg)
      end

      current_puavo_schools_by_id.each do |external_id, school_list|
        school_list.each do |school|
          msg = %Q{> Puavo school "#{ school.name }"} \
                  + " (external_id=#{ external_id })" \
                  + ' is not connected to any Univention school'
          @rlog.info(msg)
        end
      end
    end

    def lookup_all_users
      update_school_information_and_report_connections()

      users = {}

      univention_user_list = @kelvin.get_all_users()
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

    def get_schools_by_url
      schools_by_url = {}

      school_list = @kelvin.get_schools()
      school_list.each do |school|
        begin
          raise 'school does not have a name of type string' \
            unless get_univention_attribute(school, 'name').kind_of?(String)
          raise 'school does not have an url of type string' \
            unless get_univention_attribute(school, 'url').kind_of?(String)
          raise 'school does not have an external id of type string' \
            unless get_univention_attribute(school, @extschool_id_field) \
                     .kind_of?(String)
          schools_by_url[ school['url'] ] = school
        rescue StandardError => e
          @rlog.error("error looking up school from Univention: #{ e.message }")
        end
      end

      return schools_by_url
    end

    def get_univention_attribute(univention_object, attribute)
      case attribute
        when 'univentionObjectIdentifier', 'userPasswordHash'
          univention_object.dig('udm_properties', attribute) \
        else
          univention_object.dig(attribute)
      end
    end

    def set_userinfo(username, univention_userinfo)
      @username = username
      @univention_userinfo = univention_userinfo
    end

    def update_puavo_schools_by_id()
      return if @puavo_schools_by_id
      @puavo_schools_by_id = get_puavo_schools_by_id()
    end

    def update_univention_schools_by_url()
      @univention_schools_by_url = get_schools_by_url()
    end

    def update_univentionuserinfo(username)
      # XXX no-op but may be needed later?
      return
    end
  end

  class Kelvin
    def initialize(server_uri, admin_username, admin_password, rlog)
      @server_uri     = server_uri
      @admin_username = admin_username
      @admin_password = admin_password
      @rlog           = rlog
    end

    def setup_connection
      @token = get_token()
    end

    def get_token
      uri = URI("#{ @server_uri }/ucsschool/kelvin/token")

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request.set_form_data('username' => @admin_username,
                            'password' => @admin_password)

      response = Univention::do_http_request(uri, request)
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

    def get_something(subpath, something)
      uri = URI("#{ @server_uri }#{ subpath }")
      begin
        return do_json_request_with_token(uri)
      rescue UniventionRequestError => e
        raise "failure when requesting #{ something }: #{ e.response.code }" \
                + " #{ e.response.message } :: #{ e.response.body }"
      end
    end

    def get_all_users
      get_something('/ucsschool/kelvin/v1/users/', 'users')
    end

    def get_user(username)
      get_something("/ucsschool/kelvin/v1/users/#{ username }",
                    "user #{ username }")
    end

    def get_schools
      get_something('/ucsschool/kelvin/v1/schools/', 'schools')
    end

    def do_json_request_with_token(uri)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{ @token }"
      request['Content-Type'] = 'application/json'

      response = Univention::do_http_request(uri, request)
      raise UniventionRequestError.new(response) \
        unless response.is_a?(Net::HTTPSuccess)

      return JSON.parse(response.body)
    end
  end

  class Provisioning
    SUBSCRIPTION_NAME = 'puavo'

    def initialize(external_login_service, server_uri, provisioning_config,
                   rlog)
      @external_login_service = external_login_service
      @kelvin = external_login_service.kelvin
      @server_uri = server_uri
      @provisioning_config = provisioning_config
      @rlog = rlog

      @admin_password = Univention::get_conf_string(@provisioning_config,
                                                    'admin_password',
                                                    'admin_password not configured')
      @subscription_password \
        = Univention::get_conf_string(@provisioning_config,
                                      'subscription_password',
                                      'subscription_password not configured')
    end

    def prepare
      create_subscription
    end

    def run
      # XXX when to break out of the loop?  once a day, or in some unexpected
      # XXX events?
      loop do
        begin
          event_data = get_next_event()
          if event_data.nil? then
            @rlog.info('got a null event')
            sleep 2
            redo
          end
          validate_event_data(event_data)
          handle_event(event_data)
          acknowledge_event(event_data)
        rescue StandardError => e
          @rlog.error("next event error: #{ e.message }")
          # in case of errors, wait a while before trying again
          sleep 10
        end
      end
    end

    def handle_event(event_data)
      # XXX
      username = event_data['body']['new']['properties']['username']
      user = @external_login_service.kelvin.get_user(username)
      p user
    end

    def check_types(types, data)
      types.each do |field, class_or_value|
        raise "missing #{ field }" unless data.has_key?(field)
        if class_or_value.class == Class then
          raise "#{ field } is not #{ class_or_value }" \
            unless data[field].kind_of?(class_or_value)
        else
          raise %Q{#{ field } is not #{ class_or_value }} \
            unless data[field] == class_or_value
        end
      end
    end

    def validate_event_data(event_data)
      puts "got an event with some data :: #{ JSON.pretty_generate(event_data) }"

      main_types = {
        'body'            => Hash,
        'publisher_name'  => 'udm-listener',
        'realm'           => 'udm',
        'sequence_number' => Integer,
        'topic'           => 'users/user',
      }
      check_types(main_types, event_data)

      body_types = { 'new' => Hash }
      check_types(body_types, event_data['body'])

      new_types = {
        'objectType' => 'users/user',
        'properties' => Hash,
      }
      check_types(new_types, event_data['body']['new'])

      property_types = { 'username' => String }
      check_types(property_types, event_data['body']['new']['properties'])
    end

    def acknowledge_event(event_data)
      sequence_number = event_data['sequence_number']
      uri = URI("#{ subscription_uri }/messages/#{ sequence_number }/status")
      request = Net::HTTP::Patch.new(uri)
      request['Content-Type'] = 'application/json'
      request.basic_auth(SUBSCRIPTION_NAME, @subscription_password)
      request.body = { 'status': 'ok' }.to_json
      response = Univention::do_http_request(uri, request)
      unless response.is_a?(Net::HTTPSuccess) then
        errmsg = 'failure when acknowledging event number'       \
                   + " #{ sequence_number }: "                   \
                   + " #{ response.code } #{ response.message }" \
                   + " :: #{ response.body }"
        raise errmsg
      end
    end

    # needs to be called only once to setup subscription
    # but if called multiple times with the same parameters it is okay
    def create_subscription
      @rlog.info('setting up provisioning subscription')

      # we set the @subscription_password here (to Univention)
      subscription_params = {
        "name": SUBSCRIPTION_NAME,
        "realms_topics": [ { "realm": "udm", "topic": "users/user" } ],
        "request_prefill": false,
        "password": @subscription_password,
      }

      uri = URI(subscriptions_baseuri)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.basic_auth('admin', @admin_password)
      request.body = subscription_params.to_json

      response = Univention::do_http_request(uri, request)
      if response.is_a?(Net::HTTPConflict) then
        # Subscription already exists but with conflicting options,
        # delete the old one and try again.
        @rlog.info('> deleting existing provisioning subscription' \
                     + ' because of conflicting configuration')
        delete_subscription
        response = Univention::do_http_request(uri, request)
      end

      unless response.is_a?(Net::HTTPSuccess) then
        errmsg = 'failure when creating a provisioning subscription:' \
                   + "#{ response.code } #{ response.message }"       \
                   + " :: #{ response.body }"
        raise errmsg
      end
    end

    # not called from anywhere and normally not needed
    # but is here in case this ever becomes useful
    def delete_subscription
      uri = URI("#{ subscriptions_baseuri }/#{ SUBSCRIPTION_NAME }")
      request = Net::HTTP::Delete.new(uri)
      request['Content-Type'] = 'application/json'
      request.basic_auth('admin', @admin_password)
      request.body = { 'name': 'puavo' }.to_json
      response = Univention::do_http_request(uri, request)
      unless response.is_a?(Net::HTTPSuccess) then
        errmsg = 'failure when deleting a provisioning subscription:' \
                   + "#{ response.code } #{ response.message } :: #{ response.body }"
        raise errmsg
      end
    end

    def subscriptions_baseuri
      URI("#{ @server_uri }/univention/provisioning/v1/subscriptions")
    end

    def subscription_uri
      URI("#{ subscriptions_baseuri }/#{ SUBSCRIPTION_NAME }")
    end

    def get_next_event
      timeout_seconds = 60
      uri = URI("#{ subscription_uri }/messages/next")
      uri.query = URI.encode_www_form({ 'timeout' => timeout_seconds })
      request = Net::HTTP::Get.new(uri)
      request.basic_auth(SUBSCRIPTION_NAME, @subscription_password)
      response = Univention::do_http_request(uri, request, timeout_seconds+10)

      unless response.is_a?(Net::HTTPSuccess) then
        errmsg = 'failure when getting the next event on subscription:' \
                   + " #{ response.code } #{ response.message } "       \
                   + " :: #{ response.body }"
        raise errmsg
      end

      JSON.parse(response.body)
    end
  end
end
