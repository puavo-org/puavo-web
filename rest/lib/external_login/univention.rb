require 'json'

require_relative './errors'
require_relative './service'

class UniventionDataError < ExternalLoginDataError; end

module PuavoRest
  module Univention
    def self.get_conf_string(config, key, errmsg)
      value = config[key]
      raise ExternalLoginConfigError, errmsg \
        unless value.kind_of?(String) && !value.empty?
      value
    end
  end

  class ExternalUniventionService < ExternalLoginService
    OBJ_CLASS_TO_ROLE = {
      'ucsschoolAdministrator' => 'admin',
      'ucsschoolLegalGuardian' => 'parent',
      'ucsschoolStaff'         => 'staff',
      'ucsschoolStudent'       => 'student',
      'ucsschoolTeacher'       => 'teacher',
    }

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
      @connector = Connector.new(organisation, self, @rlog)
      @connector.read_current_ldap_state()
    end

    def handle_events
      @connector.handle_events()
    end

    def get_userinfo_for_puavo(username)
      raise 'univention userinfo not set' \
        unless @username && @univention_user

      puavo_extlogin_id_field = @external_login.puavo_extlogin_id_field
      userinfo = {
        puavo_extlogin_id_field => @univention_user.get(@extlogin_id_field),
        'first_name'            => @univention_user.get('givenName'),
        'last_name'             => @univention_user.get('sn'),
        'ldap_password_hash'    => @univention_user.get('userPassword'),
        'locked'                => @univention_user.is_locked?,
        'username'              => @univention_user.get('uid'),
      }

      check_attr = lambda do |field, msg|
                     raise(ExternalLoginUnavailable, msg) \
                       unless userinfo[field] && !userinfo[field].empty?
                   end

      check_attr.call(puavo_extlogin_id_field,
        "User '#{ @username }' has no extlogin id in Univention")
      check_attr.call('first_name',
        "User '#{ @username }' has no first name in Univention")
      check_attr.call('last_name',
        "User '#{ @username }' has no last name in Univention")
      check_attr.call('ldap_password_hash',
        "User '#{ @username }' has no ldap password in Univention")
      check_attr.call('username',
        "User '#{ @username }' has no account name in Univention")

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
      # the "ucsschoolExam" role-related object class is also possible,
      # but it is unclear what Puavo-role it could be mapped to
      user_object_classes = Array(@univention_user.get('objectClass'))

      user_roles = user_object_classes.map do |obj_class|
                     OBJ_CLASS_TO_ROLE[obj_class]
                   end.compact

      if user_roles.empty? then
        raise UniventionDataError,
              %Q{user "#{ @userinfo }" has no roles in UCS@school} \
                + ' that actually" exist in Puavo'
      end

      user_roles
    end

    def get_user_puavo_school_dns()
      update_puavo_schools_by_id()

      user_univention_schools_ous \
        = Array(@univention_user.get('ucsschoolSchool'))
      schools = @connector.schools.values
      user_univention_schools \
        = schools.filter do |school|
            user_univention_schools_ous.include?(school.ou)
          end

      school_ous = schools.map { |school| school.ou }
      check_if_some_user_school_is_not_known \
        = lambda do
            user_univention_schools_ous.any? { |ou| !school_ous.include?(ou) }
          end
      if check_if_some_user_school_is_not_known.call() then
        raise UniventionDataError,
              %Q{user "#{ @username }" is in an unknown school}
      end

      user_puavo_schools = []
      user_univention_schools.each do |school|
        extschool_id = school.get(@extschool_id_field)
        puavo_schools = @puavo_schools_by_id[extschool_id]
        user_puavo_schools += puavo_schools if puavo_schools
      end

      user_puavo_schools.map { |s| s.dn }
    end

    def update_school_information_and_report_connections()
      update_puavo_schools_by_id()

      @rlog.info('>> reporting school linkages')

      current_puavo_schools_by_id = @puavo_schools_by_id.clone

      @connector.schools.each do |school_id, univention_school|
        extschool_id = univention_school.get(@extschool_id_field)
        school_name = univention_school.get('displayName')
        msg = %Q{> Univention school "#{ school_name }" (#{ extschool_id })}
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

      @connector.users.each do |user_id, univention_user|
        extlogin_id = univention_user.get(@extlogin_id_field)
        next unless extlogin_id.kind_of?(String)

        username = univention_user.get(@external_username_field)
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

    def set_userinfo_from_external(username, univention_user)
      @username = username
      @univention_user = univention_user
    end

    def update_puavo_schools_by_id()
      return if @puavo_schools_by_id
      @puavo_schools_by_id = get_puavo_schools_by_id()
    end

    def update_univentionuserinfo(username)
      # XXX no-op but may be needed later?
      return
    end
  end

  class Connector
    attr_reader :groups, :schools, :users

    def initialize(organisation, login_service, rlog)
      @login_service = login_service

      begin
        @reader = IO.popen([ 'puavo-univention', organisation ])
      rescue StandardError => e
        raise "could not run puavo-univention script: #{ e.message }"
      end
      @rlog = rlog
    end

    def read_current_ldap_state
      @groups       = {}
      @schools      = {}
      @refresh_done = false
      @users        = {}

      loop do
        begin
          event = read_event()
          if event.kind_of?(RefreshDoneEvent) then
            @rlog.info('>>> ldap refresh from Univention done')
            @refresh_done = true
            break
          end
          entry = event.get_entry(false)
          sort_entry(entry)
        rescue StandardError => e
          @rlog.error('unexpected error when reading Univention ldap state: ' \
                        + e.message)
          raise e
        end
      end
    end

    def read_event
      begin
        json = @reader.gets
        raise 'EOF received when reading from puavo-univention' unless json
        return create_event_object( JSON.parse(json) )
      rescue StandardError => e
        # XXX should this tolerate some errors such as missing attributes?
        errmsg = "connector reader error: #{ e.message }"
        @rlog.error(errmsg)
        raise errmsg
      end
    end

    def handle_events
      loop do
        begin
          event = read_event()
          entry = event.get_entry(true)
          entry.handle()
        rescue StandardError => e
          errmsg = 'unexpected error when handling Univention events: ' \
                     + e.message
          @rlog.error(errmsg)
          raise errmsg
        end
      end
    end

    def sort_entry(entry)
      if entry.kind_of?(UniventionSchool) then
        @schools[ entry.id ] = entry
      end
      if entry.kind_of?(UniventionUser) then
        @users[ entry.id ] = entry
      end
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

    def check_entry(entry)
      raise 'no univentionObjectType' \
        unless entry.has_key?('univentionObjectType')
      raise 'no objectClass' unless entry.has_key?('objectClass')
    end

    def entry_class(entry)
      check_entry(entry)

      return UniventionUser if entry['univentionObjectType'] == 'users/user'
      return UniventionSchool \
        if entry['univentionObjectType'] == 'container/ou' \
             && Array(entry['objectClass']).include?('ucsschoolOrganizationalUnit')

# XXX
#     @rlog.warn(
#       "unknown Univention object type: #{ entry['univentionObjectType'] }")
      UniventionEntry
    end

    def get_entry(expect_update)
      is_update = @data['is_update']
      raise 'is_update is not a boolean value' \
        unless is_update.kind_of?(TrueClass) || is_update.kind_of?(FalseClass)
      raise 'update state did not match what we expected' \
        unless is_update == expect_update

      entry = @data['entry']
      raise 'entry is not a Hash' unless entry.kind_of?(Hash)

      entry_class(entry).new(entry, @login_service, @rlog)
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

  class UniventionEntry
    def initialize(data, login_service, rlog)
      @data          = data
      @login_service = login_service
      @rlog          = rlog
      validate
    end

    def dn
      @data['dn']
    end

    def get(key)
      # if missing, returns nil and that is okay
      @data[key]
    end

    def id
      @data['univentionObjectIdentifier']
    end

    def validate
      raise 'no univentionObjectIdentifier' \
        unless @data['univentionObjectIdentifier'].kind_of?(String)
    end
  end

  class UniventionSchool < UniventionEntry
    def ou
      get('ou')
    end
  end

  class UniventionUser < UniventionEntry
    def handle
      @login_service.update_from_external(username, self)
    end

    def is_locked?
      krb_flags = get('krb5KDCFlags')
      Integer(krb_flags) & (1 << 7) != 0
    end

    def username
      get('uid')
    end
  end
end
