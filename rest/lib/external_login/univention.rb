require 'json'
require 'net/http'
require 'uri'

require_relative './errors'
require_relative './service'

class UniventionDataError < ExternalLoginDataError; end
class EmptyUniventionEvent < UniventionDataError; end
class UniventionRequestError < ExternalLoginAccessError
  attr_reader :response

  def initialize(response, errmsg)
    @response = response
    super(errmsg)
  end
  def message
    "#{ super }: response code=#{ @response.code }" \
      + " #{ @response.message } :: #{ @response.body }"
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
      value
    end
  end

  class ExternalUniventionService < ExternalLoginService
    attr_reader :provisioning

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
      raise 'no provisioning configration' \
        unless univention_config['provisioning'].kind_of?(Hash)
      @provisioning = Provisioning.new(external_login,
                                       self,
                                       server_uri,
                                       univention_config['provisioning'],
                                       rlog)

      @puavo_schools_by_id = nil
      @univention_schools_by_url = {}
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

      puavo_schools_by_id
    end

    def get_userinfo_for_puavo(username)
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
        # XXX 'ldap_password_hash'    => get_attr.call('userPasswordHash'),
        'locked'                => get_attr.call('disabled'),
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
# XXX
#     check_attr.call('ldap_password_hash',
#                     "User '#{ username }' has no ldap password in Univention")
      check_attr.call('username',
                      "User '#{ username }' has no account name in Univention")

      # we apply some magicks to determine user school, groups and roles
      add_roles_and_schools!(userinfo)

      userinfo
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

      ucsschool_roles = @univention_userinfo['ucsschoolRole']
      unless ucsschool_roles.kind_of?(Array) && !ucsschool_roles.empty? then
        raise UniventionDataError,
              %Q{user "#{ @username }" has no roles in UCS@school}
      end

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

      if user_roles.empty? then
        raise UniventionDataError,
              %Q{user "#{ @userinfo }" has no roles in UCS@school} \
                + ' that actually" exist in Puavo'
      end

      user_roles
    end

    def get_user_puavo_school_dns()
      update_puavo_schools_by_id()

      user_univention_school_urls = @univention_userinfo['schools']
      check_if_some_user_school_is_not_known \
        = lambda do
            user_univention_school_urls.any? do |url|
              !@univention_schools_by_url.has_key?(url)
            end
          end
      if check_if_some_user_school_is_not_known.call() then
        raise UniventionDataError,
              %Q{user "#{ @username }" is in an unknown school}
      end

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

      univention_user_list = @provisioning.get_all_users()
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

      raise 'Univention did not list any users, something is wrong' \
        if users.empty?

      users
    end

    def get_schools_by_url
      schools_by_url = {}
      return schools_by_url     # XXX

      school_list = @provisioning.get_schools()
      school_list.each do |school|
        begin
          raise UniventionDataError,
                'school does not have a name of type string' \
            unless get_univention_attribute(school, 'name').kind_of?(String)
          raise UniventionDataError,
                'school does not have an url of type string' \
            unless get_univention_attribute(school, 'url').kind_of?(String)
          raise UniventionDataError,
                'school does not have an external id of type string' \
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
      univention_object.dig(attribute)
    end

    def set_userinfo_from_external(username, univention_userinfo)
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

  class Event
    attr_reader :sequence_number

    def initialize(event_data, login_service, rlog)
      # this should always succeed so we can acknowledge the event later
      @data            = event_data
      @login_service   = login_service
      @rlog            = rlog
      @sequence_number = @data['sequence_number']
      @validated       = false
    end

    def handle
      validate
    end

    def validate
      raise 'data is not a Hash' unless @data.kind_of?(Hash)

      check_types(@data, {
        'body'            => Hash,
        'publisher_name'  => publisher_name,
        'realm'           => 'udm',
        'sequence_number' => Integer,
        'topic'           => topic,
      })
    end

    def check_types(data, types)
      types.each do |field, constraint|
        raise "missing #{ field }" unless data.has_key?(field)
        value = data[field]
        if constraint.class == Class then
          raise UniventionDataError, "#{ field } is not #{ constraint }" \
            unless value.kind_of?(constraint)
        elsif constraint.kind_of?(Array) then
          raise UniventionDataError,
                "#{ field } is not any of #{ constraint }, but '#{ value }'" \
            unless constraint.any? { |cls| value.kind_of?(cls) }
        else
          raise UniventionDataError,
                %Q{#{ field } is not #{ constraint }, but '#{ value }'} \
            unless value == constraint
        end
      end
    end
  end

  class UserEvent < Event
    attr_reader :username

    def handle
      super
      @rlog.info("handling event number #{ @sequence_number }" \
                   + %Q{ for user "#{ username }"})

      unless is_ucsschool_user? then
        @rlog.info("ignoring event #{ @sequence_number }"            \
                     + %Q{ for user "#{ username }" because he/she} \
                     + ' has no ucsschool roles')
        return
      end
    end

    def is_being_deleted?
      @data['body']['new'].empty?
    end

    def is_ucsschool_user?
      options.any? do |opt, value|
        opt.match(/\Aucsschool/) \
          && (value.kind_of?(FalseClass) || value.kind_of?(TrueClass)) \
          && value
      end
    end

    def options
      @data['body'][subkey]['options']
    end

    def subkey
      is_being_deleted? ? 'old' : 'new'
    end

    def topic
      'users/user'
    end

    def username
      user_properties['username']
    end

    def user_properties
      @data['body'][subkey]['properties']
    end

    def validate
      return if @validated
      super

      subkey = 'new'
      check_types(@data['body'], { subkey => Hash })
      subkey = 'old' if is_being_deleted?

      check_types(@data['body'][subkey], {
        'objectType' => 'users/user',
        'properties' => Hash,
        'options'    => Hash,
      })

      check_types(@data['body'][subkey]['properties'],
                  { 'username' => String })

      @validated = true
    end
  end

  class ListenerUserEvent < UserEvent
    def handle
      super

      if is_being_deleted? then
        # XXX instead of using username, this should probably look for
        # XXX Puavo user with the same Univention Object Id?
        puavo_user = User.by_username(username)
        if puavo_user.mark_for_removal! then
          @rlog.info("puavo user '#{ puavo_user.username }' is marked" \
                       + ' for removal')
          return
        end
      end

      begin
        user = get_user
      rescue StandardError => e
        @rlog.warn("can not get user from Univention: #{ e.message }")
        return
      end

      begin
        @login_service.update_from_external(event.username, user)
      rescue StandardError => e
        @rlog.warn("can not update user to Puavo: #{ e.message }")
      end
    end

    def publisher_name
      'udm-listener'
    end
  end

  class PrefillUserEvent < UserEvent
    def handle
      super
      return self
    end

    def publisher_name
      'udm-pre-fill'
    end
  end

  class Provisioning
    SUBSCRIPTION_NAME = 'puavo'

    def initialize(external_login, login_service, server_uri,
                   provisioning_config, rlog)
      @external_login      = external_login
      @login_service       = login_service
      @server_uri          = server_uri
      @provisioning_config = provisioning_config
      @rlog                = rlog

      @admin_password = Univention::get_conf_string(@provisioning_config,
                                                    'admin_password',
                                                    'admin_password not configured')
      # new one each time, kept only in memory
      @subscription_password = SecureRandom.alphanumeric(32)
    end

    def get_all_users
      univention_user_list = []

      loop do
        begin
          subscription = get_subscription()
          event = get_and_handle_an_event(5)
        rescue EmptyUniventionEvent => e
          # no event, check subscription state
          subscription = get_subscription()
          if subscription['prefill_queue_status'] == 'done' then
            @rlog.info('no event and prefill queue status is done')
            break
          end
          next
        end

        if event.kind_of?(PrefillUserEvent) then
          user = event.user_properties
          univention_user_list << user
        else
          # XXX
          raise "GOT SOME OTHER EVENT: #{ event.inspect }"
        end
      end

      univention_user_list
    end

    def get_and_handle_an_event(timeout_seconds)
      event = nil
      begin
        event = get_next_event(timeout_seconds)
        event.handle()
        return event
      ensure
        if event then
          # Acknowledge even in case of errors.  The show must go on.
          send_acknowledgement(event)
        end
      end
    end

    def wait_for_events
      # XXX when to break out of the loop?  once a day, or in some unexpected
      # XXX events?
      loop do
        begin
          get_and_handle_an_event(60)
        rescue UniventionDataError => e
          @rlog.error("univention data error: #{ e.message }")
          sleep 2
          redo
        rescue StandardError => e
          @rlog.error("unexpected next event error: #{ e.message }")
          # in case of unexpected errors, wait a while before trying again
          sleep 10
        end
      end
    end

    def create_event_object(parsed_data)
      raise 'data is not a Hash' unless parsed_data.kind_of?(Hash)

      publisher_name = parsed_data['publisher_name']
      topic = parsed_data['topic']
      if publisher_name == 'udm-listener' && topic == 'users/user' then
        event_class = ListenerUserEvent
      elsif publisher_name == 'udm-pre-fill' && topic == 'users/user' then
        event_class = PrefillUserEvent
      else
        @rlog.warn("got an unknown event with" \
                     + " publisher_name=#{ publisher_name }" \
                     + " and topic=#{ topic }")
        event_class = Event
      end

      event_class.new(parsed_data, @login_service, @rlog)
    end

    # needs to be called only once to setup subscription
    # but if called multiple times with the same parameters it is okay
    def create_subscription
      @rlog.info('setting up provisioning subscription')

      # we set the @subscription_password here (to Univention)
      subscription_params = {
        'name': SUBSCRIPTION_NAME,
        'realms_topics': [
          { 'realm': 'udm', 'topic': 'users/user' },
        ],
        'request_prefill': true,
        'password': @subscription_password,
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
        raise UniventionRequestError.new(response,
                'failure when creating a provisioning subscription')
      end
    end

    def delete_subscription
      uri = URI("#{ subscriptions_baseuri }/#{ SUBSCRIPTION_NAME }")
      request = Net::HTTP::Delete.new(uri)
      request['Content-Type'] = 'application/json'
      request.basic_auth('admin', @admin_password)
      request.body = { 'name': 'puavo' }.to_json
      response = Univention::do_http_request(uri, request)
      unless response.is_a?(Net::HTTPSuccess) then
        raise UniventionRequestError.new(response,
                'failure when deleting a provisioning subscription')
      end
    end

    def prepare
      create_subscription
    end

    def subscriptions_baseuri
      URI("#{ @server_uri }/univention/provisioning/v1/subscriptions")
    end

    def subscription_uri
      URI("#{ subscriptions_baseuri }/#{ SUBSCRIPTION_NAME }")
    end

    def get_next_event(timeout_seconds)
      @rlog.info('making a new request for the next provisioning event')
      parsed_data = make_request('/messages/next', timeout_seconds)
      raise EmptyUniventionEvent, 'no data received' if parsed_data.nil?
      create_event_object(parsed_data)
    end

    def get_subscription
      make_request('', 60)
    end

    def make_request(subpath, timeout_seconds)
      uri = URI("#{ subscription_uri }#{ subpath }")
      uri.query = URI.encode_www_form({ 'timeout' => timeout_seconds })
      request = Net::HTTP::Get.new(uri)
      request.basic_auth(SUBSCRIPTION_NAME, @subscription_password)
      response = Univention::do_http_request(uri, request, timeout_seconds+10)

      unless response.is_a?(Net::HTTPSuccess) then
        raise UniventionRequestError.new(response,
                'failure when making a request to provisioning api')
      end

      JSON.parse(response.body)
    end

    def send_acknowledgement(event)
      seq_number = event.sequence_number
      @rlog.info("sending acknowledgement for event number #{ seq_number }" \
                   + %Q{ for user "#{ event.username }"})
      uri = URI("#{ subscription_uri }/messages/#{ seq_number }/status")
      request = Net::HTTP::Patch.new(uri)
      request['Content-Type'] = 'application/json'
      request.basic_auth(SUBSCRIPTION_NAME, @subscription_password)
      request.body = { 'status': 'ok' }.to_json
      response = Univention::do_http_request(uri, request)
      unless response.is_a?(Net::HTTPSuccess) then
        raise UniventionRequestError.new(response,
                'failure when acknowledging event number')
      end
    end
  end
end
