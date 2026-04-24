require 'json'

require_relative './errors'
require_relative './service'

class UniventionDataError < ExternalLoginDataError; end

module PuavoRest
  module PrefillEvent
    def handle
      super
      return self
    end

    def publisher_name
      'udm-pre-fill'
    end
  end

  module Univention
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

      @external_username_field \
        = Univention::get_conf_string(
            univention_config,
            'external_username_field',
            'univention extlogin name field not configured')
      @extlogin_id_field = Univention::get_conf_string(
                             univention_config,
                             'extlogin_id_field',
                             'univention extlogin id field not configured')
      @extschool_id_field = Univention::get_conf_string(
                              univention_config,
                              'extschool_id_field',
                              'univention extschool id field not configured')

      @connector = nil
      @puavo_schools_by_id = nil
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

    def has_realtime?
      true
    end

    def prepare(organisation)
      @connector = Connector.new(organisation, @rlog)
      @connector.read_current()
    end

    def handle_events
      @connector.handle_events()
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
      raise 'unimplemented'

      update_school_information_and_report_connections()

      users = {}

      @provisioning.users.each do |univention_user|
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

      school_list = @provisioning.schools
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

  class Connector
    attr_reader :groups, :schools, :users

    def initialize(organisation, rlog)
      begin
        @reader = IO.popen([ 'puavo-univention', organisation ])
      rescue StandardError => e
        raise "could not run puavo-univention script: #{ e.message }"
      end
      @rlog = rlog
    end

    def read_current
      @groups       = []
      @schools      = []
      @refresh_done = false
      @users        = []

      loop do
        begin
          json = @reader.gets
          raise 'EOF received when reading from puavo-univention' unless json
          event = create_event_object( JSON.parse(json) )
          if event.kind_of?(RefreshDoneEvent) then
            @rlog.info('refresh done')
            @refresh_done = true
            break
          end
          entry = event.get_entry(false)
        rescue StandardError => e
          errmsg = "connector reader error: #{ e.message }"
          @rlog.error(errmsg)
          raise errmsg
        end
      end
    end

    def handle_events
      raise 'unimplemented'
    end

    def create_event_object(parsed_data)
      raise 'data is not a Hash' unless parsed_data.kind_of?(Hash)

      type = parsed_data['type']
      raise 'type is not a string' unless type.kind_of?(String)

      event_class = nil
      case type
      when 'entry' then
        event_class = EntryEvent
      when 'refresh_done'
        event_class = RefreshDoneEvent
      else
        raise "unknown event type: #{ type }"
      end

      event_class.new(parsed_data, @login_service, @rlog)
    end
  end

  class Event
    def initialize(data, login_service, rlog)
      @data          = data
      @login_service = login_service
      @rlog          = rlog
    end

    def get_entry(expect_update)
      is_update = @data['is_update']
      raise 'is_update is not a boolean value' \
        unless is_update.kind_of?(TrueClass) || is_update.kind_of?(FalseClass)
      raise 'update state did not match what we expected' \
        unless is_update == expect_update

      # XXX should determine what type of Entry this is

      entry = @data['entry']
      raise 'entry is not a Hash' unless entry.kind_of?(Hash)
      entry
    end
  end

  class EntryEvent < Event
    def initialize(data, login_service, rlog)
      super(data, login_service, rlog)
    end
  end

  class RefreshDoneEvent < Event
    def initialize(data, login_service, rlog)
      super(data, login_service, rlog)
    end
  end
end
