require 'benchmark'
require 'net/ldap'
require 'openssl'

require_relative './errors'
require_relative './service'

module PuavoRest
  class ExternalLdapService < ExternalLoginService
    def initialize(external_login, ldap_config, service_name, rlog)
      super(external_login, service_name, rlog)

      # this is a reference to configuration, do not modify!
      @ldap_config = ldap_config

      raise ExternalLoginConfigError, 'ldap base not configured' \
        unless @ldap_config['base']

      raise ExternalLoginConfigError, 'authentication method not configured' \
        unless @ldap_config['authentication_method']

      case @ldap_config['authentication_method']
        when 'certificate'
          raise ExternalLoginConfigError,
                'ldap connection certificate not configured' \
            unless @ldap_config['connection_cert']
          raise ExternalLoginConfigError,
                'ldap connection certificatge key not configured' \
            unless @ldap_config['connection_key']
        when 'user_credentials'
          raise ExternalLoginConfigError, 'ldap bind dn not configured' \
            unless @ldap_config['bind_dn']
          raise ExternalLoginConfigError, 'ldap bind password not configured' \
            unless @ldap_config['bind_password']
        else
          errmsg = 'unsupported authentication method' \
                     + " '#{ @ldap_config['authentication_method'] }'" \
                     + ' to external ldap'
          raise ExternalLoginConfigError, errmsg
      end

      raise ExternalLoginConfigError, 'ldap server not configured' \
        unless @ldap_config['server']

      if @external_login.manage_puavousers then
        user_mappings = @ldap_config['user_mappings']
        raise ExternalLoginConfigError, 'user_mappings configured wrong' \
          unless user_mappings.nil? || user_mappings.kind_of?(Hash)

        @user_mapping_defaults = (user_mappings && user_mappings['defaults']) \
                                   || {}
        @user_mappings_by_dn = (user_mappings && user_mappings['by_dn']) || []
        @user_mappings_by_memberof \
          = (user_mappings && user_mappings['by_memberof']) || []

        raise ExternalLoginConfigError, 'user_mappings/by_dn is not an array' \
          unless @user_mappings_by_dn.kind_of?(Array)
        raise ExternalLoginConfigError, \
              'user_mappings/by_memberof is not an array' \
          unless @user_mappings_by_memberof.kind_of?(Array)
        raise ExternalLoginConfigError, 'user_mappings/defaults is not a hash' \
          unless @user_mapping_defaults.kind_of?(Hash)
      end

      @extlogin_id_field = @ldap_config['extlogin_id_field']
      raise ExternalLoginConfigError, 'extlogin_id_field not configured' \
        unless @extlogin_id_field.kind_of?(String)

      # external_learner_id_field is not mandatory
      @external_learner_id_field = @ldap_config['external_learner_id_field']

      @external_username_field = @ldap_config['external_username_field']
      raise ExternalLoginConfigError, 'external_username_field not configured' \
        unless @external_username_field.kind_of?(String)

      @external_password_change = @ldap_config['password_change']
      raise ExternalLoginConfigError, 'password_change style not configured' \
        unless @external_password_change.kind_of?(Hash)

      if @external_login.manage_puavousers then
        @external_ldap_subtrees = @ldap_config['subtrees']
        raise ExternalLoginConfigError, 'subtrees not configured' \
          unless @external_ldap_subtrees.kind_of?(Array) \
                   && @external_ldap_subtrees.all? { |s| s.kind_of?(String) }
      end

      setup_ldap_connection(@ldap_config['bind_dn'],
                            @ldap_config['bind_password'])

      @ldap_userinfo = nil
      @username = nil
    end

    def setup_ldap_connection(bind_dn, bind_password)
      connection_args = {
        :base => @ldap_config['base'].to_s,
        :host => @ldap_config['server'].to_s,
        :port => (Integer(@ldap_config['port']) rescue 389),
      }

      case @ldap_config['authentication_method']
        when 'certificate'
          connection_args[:auth] = {
            :method             => :sasl,
            :mechanism          => 'EXTERNAL',
            :challenge_response => lambda { '' },
            :initial_credential => '',
          }
        when 'user_credentials'
          connection_args[:auth] = {
            :method   => :simple,
            :username => bind_dn,
            :password => bind_password,
          }
      end

      # XXX the use of OpenSSL::SSL::VERIFY_NONE is not so good
      # XXX see http://www.rubydoc.info/github/ruby-ldap/ruby-net-ldap/Net%2FLDAP:initialize
      # XXX and http://ruby-doc.org/stdlib-2.3.0/libdoc/openssl/rdoc/OpenSSL/SSL/SSLContext.html
      # XXX should this be configurable through
      # XXX ldap_config?
      case @ldap_config['encryption_method']
        when 'none'
          true
        when 'simple_tls'
          connection_args[:encryption] = {
            :method      => :simple_tls,
            :tls_options => { :verify_mode => OpenSSL::SSL::VERIFY_NONE, } # XXX
          }
        when 'start_tls'
          connection_args[:encryption] = {
            :method      => :start_tls,
            :tls_options => { :verify_mode => OpenSSL::SSL::VERIFY_NONE, } # XXX
          }
        else
          raise ExternalLoginConfigError,
                'unsupported encryption method:' \
                  + " '#{ @ldap_config['encryption_method'] }'"
      end

      if @ldap_config['authentication_method'] == 'certificate' then
        cert = OpenSSL::X509::Certificate.new(@ldap_config['connection_cert'])
        key  = OpenSSL::PKey::RSA.new(@ldap_config['connection_key'])
        connection_args[:encryption][:tls_options][:cert] = cert
        connection_args[:encryption][:tls_options][:key]  = key
      end

      @ldap = Net::LDAP.new(connection_args)
    end

    # for now, only benchmark ldap operations, but we may also need
    # to add a timeout here
    def ext_ldapop(oplabel, method, *args)
      result = nil
      op_time = Benchmark.realtime do
        result = @ldap.send(method, *args)
      end
      @rlog.info("#{ oplabel } to external ldap took" \
                   + " #{ sprintf('%.3f', op_time) } seconds")

      return result
    end

    def login(username, password)
      # first check if user exists
      update_ldapuserinfo(username)

      bind_ok = ext_ldapop('login/bind_as',
                           :bind_as,
                           :filter   => user_ldapfilter(username),
                           :password => password)
      if !bind_ok then
        raise ExternalLoginWrongCredentials,
              "binding as '#{ username }' to external ldap failed:" \
                + ' user and/or password is wrong'
      end

      @rlog.info('authentication to ldap succeeded')

      get_userinfo(username)
    end

    def change_password(actor_username, actor_password, target_user_username,
                        target_user_password)
      if @external_password_change['api'] == 'do-nothing' then
        raise ExternalLoginNotConfigured,
              'password changes are disabled in configuration'
      end

      update_ldapuserinfo(target_user_username)

      target_dn = Array(@ldap_userinfo['dn']).first.to_s
      if target_dn.empty? then
        raise "LDAP information for user '#{ target_user_username }' has no DN"
      end

      actor_info = ext_ldapop('change_password/bind_as',
                              :bind_as,
                              :filter   => user_ldapfilter(actor_username),
                              :password => actor_password)
      if !actor_info then
        raise ExternalLoginWrongCredentials,
              "binding as '#{ actor_username }' to external ldap failed:" \
                + ' user and/or password is wrong'
      end

      # Setup a new ldap connection with actor_dn to make sure that only
      # the permissions of the actor are used when passwords are changed.
      actor_dn = actor_info.first.dn
      raise ExternalLoginPasswordChangeError,
            'could not find actor user dn in external ldap' \
        unless actor_dn.kind_of?(String)

      # these raise exceptions if password change fails
      case @external_password_change['api']
        when 'google'
          raise ExternalLoginPasswordChangeError,
                'password change to google systems is not supported'
        when 'microsoft-ad'
          setup_ldap_connection(actor_dn, actor_password)
          change_microsoft_ad_password(target_dn, target_user_password)
        when 'openldap'
          setup_ldap_connection(actor_dn, actor_password)
          bind_user = ext_ldapop('change_password/search',
                                 :search,
                                 :filter   => user_ldapfilter(actor_username),
                                 :password => actor_password,
                                 :time     => 5)
          if !bind_user || bind_user.count != 1 then
            raise ExternalLoginPasswordChangeError,
                  'could not find user in openldap to bind with'
          end
          res = Puavo::LdapPassword.change_ldap_passwd(CONFIG['ldap'],
                                                       bind_user.first.dn.to_s,
                                                       actor_password,
                                                       target_dn,
                                                       target_user_password)
          raise ExternalLoginPasswordChangeError, res[:stderr] \
            unless res[:exit_status] == 0
        else
          raise ExternalLoginPasswordChangeError,
                'unsupported password change api'
      end

      return true
    end

    def lookup_extlogin_id(username)
      update_ldapuserinfo(username)

      extlogin_id = @ldap_userinfo \
                      && Array(@ldap_userinfo[@extlogin_id_field]).first.to_s
      if !extlogin_id || extlogin_id.empty? then
        raise(ExternalLoginUnavailable,
              "could not lookup extlogin id (#{ @extlogin_id_field })" \
                + " for user '#{ username }'")
      end

      extlogin_id
    end

    def get_userinfo(username)
      raise 'ldap userinfo not set' unless @username && @ldap_userinfo

      # Use .dup here for userinfo values so that we can use force_encoding
      # (that may fail on frozen strings).

      puavo_extlogin_id_field = @external_login.puavo_extlogin_id_field
      userinfo = {
        puavo_extlogin_id_field => lookup_extlogin_id(username).dup,
        'first_name' => Array(@ldap_userinfo['givenname']).first.to_s.dup,
        'last_name'  => Array(@ldap_userinfo['sn']).first.to_s.dup,
        'username'   => username.dup,
      }

      if userinfo['first_name'].empty? then
        raise ExternalLoginUnavailable,
              "User '#{ username }' has no first name in external ldap"
      end

      if userinfo['last_name'].empty? then
        raise ExternalLoginUnavailable,
              "User '#{ username }' has no last name in external ldap"
      end

      if userinfo['username'].empty? then
        raise ExternalLoginUnavailable,
              "User '#{ username }' has no account name external ldap"
      end

      if @external_learner_id_field \
        && puavo_extlogin_id_field != 'learner_id' then
          userinfo['learner_id'] \
            = Array(@ldap_userinfo[@external_learner_id_field]).first.to_s.dup
      end

      # We presume that ldap result strings are UTF-8.
      userinfo.each do |key, value|
        Array(value).map { |s| s.force_encoding('UTF-8') }
      end

      begin
        # This presumes that if "pwdLastSet"-attribute exists it has
        # AD-like semantics.  Google LDAP does not have this attribute
        # so do not show errors in case it is missing.
        ad_pwd_last_set = Array(@ldap_userinfo['pwdLastSet']).first
        if ad_pwd_last_set then
          pwd_last_set \
            = (Time.new(1601, 1, 1) + (ad_pwd_last_set.to_i)/10000000).to_i
          raise 'pwdLastSet value is clearly wrong' if pwd_last_set < 1000000000
          userinfo['password_last_set'] = pwd_last_set
        end
      rescue StandardError => e
        @rlog.warn('error looking up pwdLastSet in AD for user ' \
                     + "#{ userinfo['username'] }: #{ e.message }")
      end

      # we apply some magicks to determine user school, groups and roles
      if @external_login.manage_puavousers then
        apply_user_mappings!(userinfo,
                             [ [ Array(@ldap_userinfo['dn']),
                                 @user_mappings_by_dn ],
                               [ Array(@ldap_userinfo['memberof']),
                                 @user_mappings_by_memberof ]])
      end

      userinfo
    end

    def lookup_all_users
      users = {}

      user_filter = Net::LDAP::Filter.eq(@extlogin_id_field, '*') \
                      & Net::LDAP::Filter.eq(@external_username_field, '*')

      id_sym       = @extlogin_id_field.downcase.to_sym
      username_sym = @external_username_field.downcase.to_sym

      @external_ldap_subtrees.each do |subtree|
        ldap_entries = ext_ldapop('lookup_all_users/search',
                                  :search,
                                  :base   => subtree,
                                  :filter => user_filter,
                                  :time   => 5)
        if !ldap_entries then
          msg = "ldap search for all users failed: " \
                  + @ldap.get_operation_result.message
          raise ExternalLoginUnavailable, msg
        end

        ldap_entries.each do |ldap_entry|
          extlogin_id = Array(ldap_entry[id_sym]).first
          next unless extlogin_id.kind_of?(String)

          userprincipalname = Array(ldap_entry[username_sym]).first
          next unless userprincipalname.kind_of?(String)

          match = userprincipalname.match(/\A(.*)@/)
          next unless match

          users[ extlogin_id ] = {
            'user_entry' => ldap_entry,
            'username'   => match[1],
          }
        end
      end

      return users
    end

    def set_userinfo(username, ldap_userinfo)
      @username = username
      @ldap_userinfo = ldap_userinfo
    end

    private

    def change_microsoft_ad_password(target_dn, target_user_password)
      encoded_password = ('"' + target_user_password + '"') \
                         .encode('utf-16le')        \
                         .force_encoding('utf-8')

      # We are doing the password change operation twice because at least
      # on some ldap servers (Microsoft AD, possibly depending on
      # configuration) the old password is still valid for five minutes on
      # ldap operations :-(
      ops = [ [ :replace, :unicodePwd, encoded_password ],
              [ :replace, :unicodePwd, encoded_password ] ]
      change_ok = ext_ldapop('change_microsoft_ad_password/modify',
                             :modify,
                             :dn         => target_dn,
                             :operations => ops)
      if !change_ok then
        raise ExternalLoginPasswordChangeError,
              @ldap.get_operation_result.error_message \
                + ' (maybe server password policy does not accept it?)'
      end

      return true
    end

    def apply_user_mappings!(userinfo, user_attrs_and_mapping_lists)
      added_roles      = []
      added_school_dns = []
      external_groups  = {
                           'administrative group' => {},
                           'teaching group'       => {},
                           'year class'           => {},
                         }

      user_attrs_and_mapping_lists.each do |user_attribute_and_mapping_lists|
        user_attribute_list, mapping_list = * user_attribute_and_mapping_lists

        mapping_list.each do |user_mapping|
          unless user_mapping.kind_of?(Hash) then
            raise ExternalLoginConfigError,
                  'external_login user_mapping is not a hash'
          end

          user_mapping.each do |glob_pattern, operations_list|
            next unless user_attribute_list.any? do |user_attribute|
                          File.fnmatch(glob_pattern, user_attribute)
                        end

            unless operations_list.kind_of?(Array) then
              raise ExternalLoginConfigError,
                    'external_login user_mapping operations list' \
                      + " for glob_pattern '#{ glob_pattern }'" \
                      + ' is not an array'
            end

            operations_list.each do |op_item|
              unless op_item.kind_of?(Hash) then
                raise ExternalLoginConfigError,
                      'external_login user_mapping operation list item' \
                        + " for glob_pattern '#{ glob_pattern }'" \
                        + ' is not a hash'
              end

              op_item.each do |op_name, op_params|
                case op_name
                when 'add_roles', 'add_school_dns'
                  raise ExternalLoginConfigError,
                        "#{ op_name } operation parameters type" \
                          + " for glob_pattern '#{ glob_pattern }'" \
                          + ' is not an array of strings' \
                    unless op_params.kind_of?(Array) \
                             && op_params.all? { |x| x.kind_of?(String) }
                end

                case op_name
                when 'add_administrative_group'
                  new_group = apply_add_groups('administrative group',
                                               op_params)
                  external_groups['administrative group'].merge!(new_group)
                when 'add_roles'
                  added_roles += op_params
                when 'add_school_dns'
                  added_school_dns += op_params
                when 'add_teaching_group'
                  new_group = apply_add_groups('teaching group', op_params)
                  external_groups['teaching group'].merge!(new_group)
                when 'add_year_class'
                  new_group = apply_add_groups('year class', op_params)
                  external_groups['year class'].merge!(new_group)
                else
                  raise ExternalLoginConfigError,
                        "unsupported operation '#{ op_name }'" \
                          + " for glob_pattern '#{ glob_pattern }'"
                end
              end
            end
          end
        end
      end

      userinfo['external_groups'] = external_groups
      userinfo['roles']           = added_roles.sort.uniq
      userinfo['school_dns']      = added_school_dns.sort.uniq

      # apply defaults in case we have empty roles and/or school_dns
      %w(roles school_dns).each do |attr|
        if userinfo[attr].empty? then
          unless @user_mapping_defaults[attr].kind_of?(Array) then
            raise "userinfo attribute '#{ attr }' default is of wrong type" \
                    + ' or is not set when needed'
          end
          userinfo[attr] = @user_mapping_defaults[attr]
        end
      end

      userinfo['primary_school_dn'] = (!added_school_dns.empty? \
                                         ? added_school_dns     \
                                         : userinfo['school_dns']).first
    end

    def get_add_groups_param(params, param_name)
      value = params[param_name] || @user_mapping_defaults[param_name]
      return nil unless value.kind_of?(String) && !value.empty?
      value.clone
    end

   def format_groupdata(groupdata_string, params)
     formatting_needed = groupdata_string.include?('%CLASSNUMBER')    \
                           || groupdata_string.include?('%GROUP')     \
                           || groupdata_string.include?('%STARTYEAR')

     return groupdata_string unless formatting_needed

     teaching_group = nil
     teaching_group_field = get_add_groups_param(params, 'teaching_group_field')
     if teaching_group_field then
       teaching_group_value = Array(@ldap_userinfo[teaching_group_field]).first
       if teaching_group_value.kind_of?(String) then
         teaching_group_regex \
           = get_add_groups_param(params, 'teaching_group_regex') || /^(.*)$/
         match = teaching_group_value.match(teaching_group_regex)
         if match && match.size == 2 then
           teaching_group = match[1]
         else
           @rlog.warn('unexpected format in ldap attribute' \
                        + " '#{ teaching_group_field }':" \
                        + " '#{ teaching_group_value }'" \
                        + " (expecting a match with '#{ teaching_group_regex }'" \
                        + ' that should also have one string capture)')
         end
       end
     end

     if groupdata_string.include?('%GROUP') then
       unless teaching_group then
         @rlog.warn('could not determine teaching group')
         return nil
       end
       groupdata_string.sub!('%GROUP', teaching_group)
     end

     return groupdata_string unless groupdata_string.include?('%CLASSNUMBER') \
                                      || groupdata_string.include?('%STARTYEAR')

     yearclass = nil
     yearclass_field = get_add_groups_param(params, 'yearclass_field')
     if yearclass_field then
       yearclass_value = Array(@ldap_userinfo[yearclass_field]).first
       if yearclass_value.kind_of?(String) then
         yearclass_regex = get_add_groups_param(params, 'yearclass_regex') \
                             || /^(.*)$/
         match = yearclass_value.match(yearclass_regex)
         if match && match.size == 2 then
           yearclass = match[1]
         else
           @rlog.warn('unexpected format in ldap attribute' \
                        + " '#{ yearclass_field }':" \
                        + " '#{ yearclass_value }'" \
                        + " (expecting a match with '#{ yearclass_regex }'" \
                        + ' that should also have one string capture)')
         end
       end
     end

     if !yearclass && teaching_group_value then
       classnumber_regex = get_add_groups_param(params, 'classnumber_regex')
       if classnumber_regex then
         match = teaching_group_value.match(classnumber_regex)
         if match && match.size == 2 then
           yearclass = match[1]
         else
           @rlog.warn('unexpected format in teaching group' \
                        + " '#{ teaching_group }':" \
                        + " (expecting a match with '#{ classnumber_regex }'" \
                        + ' that should also have one string capture)')
         end
       end
     end

     unless yearclass then
       @rlog.warn('could not determine year class')
       return nil
     end

     begin
       class_number = Integer(yearclass)
     rescue StandardError => e
       @rlog.warn("could not convert '#{ yearclass }' to integer")
       return nil
     end

     today = Date.today
     class_yearbase = today.year + (today.month < 8 ? 0 : 1)

     groupdata_string.sub('%CLASSNUMBER', class_number.to_s) \
                     .sub('%STARTYEAR', (class_yearbase - class_number).to_s)
    end

    def apply_add_groups(group_type, params)
      group = {}

      begin
        unless params.kind_of?(Hash) then
          raise 'group mapping parameters is not a hash'
        end

        # these are mandatory
        displayname_format = get_add_groups_param(params, 'displayname')
        name_format        = get_add_groups_param(params, 'name')
        raise 'group attribute "displayname" not configured' \
          unless displayname_format
        raise 'group attribute "name" not configured' \
          unless name_format

        displayname = format_groupdata(displayname_format, params)
        return {} unless displayname

        unsanitized_name = format_groupdata(name_format, params)
        return {} unless unsanitized_name

        # group name sanitation is the same as in PuavoImport.sanitize_name
        name = unsanitized_name.downcase \
                               .gsub(/[åäö ]/,
                                     'å' => 'a',
                                     'ä' => 'a',
                                     'ö' => 'o',
                                     ' ' => '-') \
                               .gsub(/[^a-z0-9-]/, '')

        if name && displayname then
          group = { name => displayname }
        end
      rescue StandardError => e
        raise ExternalLoginConfigError, e.message
      end

      return group
    end

    def update_ldapuserinfo(username)
      return if @username && @username == username

      set_userinfo(nil, nil)

      ldap_entries = ext_ldapop('update_ldapuserinfo/search_username',
                                :search,
                                :filter => user_ldapfilter(username),
                                :time   => 5)
      if !ldap_entries then
        msg = "ldap search for user '#{ username }' failed: " \
                + @ldap.get_operation_result.message
        raise ExternalLoginUnavailable, msg
      end

      if ldap_entries.count == 0 then
        # ExternalLoginUserMissing means that user is missing in external ldap
        # and it can be removed from Puavo in case it exists there.
        puavouser = User.by_username(username)
        raise ExternalLoginUserMissing,
              "user '#{ username }' does not exist in Puavo" unless puavouser

        extlogin_id = @external_login.extlogin_id(puavouser)
        raise ExternalLoginUserMissing,
              "user '#{ username }' does not exist in external ldap" \
          unless extlogin_id

        extid_filter = Net::LDAP::Filter.eq(@extlogin_id_field, extlogin_id)
        extid_ldap_entries = ext_ldapop('update_ldapuserinfo/search_extid',
                                        :search,
                                        :filter => extid_filter,
                                        :time   => 5)
        if !extid_ldap_entries then
          msg = "ldap search for extlogin_id '#{ extlogin_id }'" \
                  + " failed: #{ @ldap.get_operation_result.message }"
          raise ExternalLoginUnavailable, msg
        end

        if extid_ldap_entries.count == 0 then
          msg = "user '#{ username }' (#{ extlogin_id }) does not" \
                  + ' exist in external ldap'
          raise ExternalLoginUserMissing, msg
        end

        # User exists in Puavo and in external ldap, but wrong username was
        # used for login (we could lookup another user in the external ldap
        # with the same extlogin id as is associated with this username
        # in Puavo).
        raise ExternalLoginWrongCredentials, msg
      end

      if ldap_entries.count > 1 then
        raise ExternalLoginUnavailable, 'ldap search returned too many entries'
      end

      @rlog.info("looked up user '#{ username }' from external ldap")

      set_userinfo(username, ldap_entries.first)
    end

    def user_ldapfilter(username)
      Net::LDAP::Filter.eq(@external_username_field,
                           "#{ Net::LDAP::Filter.escape(username) }@*")

    end
  end
end
