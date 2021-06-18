require 'benchmark'
require 'net/ldap'
require 'openssl'

# ExternalLoginError means some error occurred on our side
# ExternalLoginConfigError means external logins were badly configured
# ExternalLoginNotConfigured means external logins are not configured
#   in whatever particular case
# ExternalLoginUnavailable means an error at external service
# ExternalLoginUserMissing means user could not found at external service
# ExternalLoginWrongCredentials means user or password was invalid

class ExternalLoginError               < StandardError; end
class ExternalLoginConfigError         < ExternalLoginError; end
class ExternalLoginNotConfigured       < ExternalLoginError; end
class ExternalLoginPasswordChangeError < ExternalLoginError; end
class ExternalLoginUnavailable         < ExternalLoginError; end
class ExternalLoginUserMissing         < ExternalLoginError; end
class ExternalLoginWrongCredentials    < ExternalLoginError; end

module PuavoRest
  class ExternalLoginStatus
    BADUSERCREDS     = 'BADUSERCREDS'
    CONFIGERROR      = 'CONFIGERROR'
    NOCHANGE         = 'NOCHANGE'
    NOTCONFIGURED    = 'NOTCONFIGURED'
    UNAVAILABLE      = 'UNAVAILABLE'
    UPDATED          = 'UPDATED'
    UPDATED_BUT_FAIL = 'UPDATED_BUT_FAIL'
    UPDATEERROR      = 'UPDATEERROR'
    USERMISSING      = 'USERMISSING'
  end

  class ExternalLogin
    attr_reader :config

    def initialize
      # Parse config with relevant information for doing external logins.

      @rlog = $rest_log

      all_external_login_configs = CONFIG['external_login']
      unless all_external_login_configs then
        raise ExternalLoginNotConfigured, 'external login not configured'
      end

      @organisation = LdapModel.organisation
      raise ExternalLoginError,
        'could not determine organisation from request host' \
          unless @organisation && @organisation.domain.kind_of?(String)

      organisation_name = @organisation.domain.split('.')[0]
      raise ExternalLoginError,
        'could not parse organisation from organisation domain' \
          unless organisation_name

      @config = all_external_login_configs[organisation_name]
      unless @config then
        raise ExternalLoginNotConfigured,
          'external_login not configured for this organisation'
      end

      @login_service_name = @config['service']
      raise ExternalLoginConfigError, 'external_login service not set' \
        unless @login_service_name

      # More login classes could be added here in the future,
      # for other types of external logins.
      loginclass_map = {
        'external_ldap' => ExternalLdapService,
      }
      @external_login_class = loginclass_map[@login_service_name]
      raise ExternalLoginError,
        "external login '#{ @login_service_name }' is not supported" \
          unless @external_login_class

      @external_login_params = @config[@login_service_name]
      raise ExternalLoginError,
        'external login parameters not configured' \
          unless @external_login_params.kind_of?(Hash)

      @admin_dn = @config['admin_dn'].to_s
      raise ExternalLoginError, 'admin dn is not set' \
        if @admin_dn.empty?

      @admin_password = @config['admin_password'].to_s
      raise ExternalLoginError, 'admin password is not set' \
        if @admin_password.empty?
    end

    def setup_puavo_connection()
      LdapModel.setup(:credentials => {
                        :dn       => @admin_dn,
                        :password => @admin_password,
                      },
                      :organisation => @organisation)
    end

    def check_user_is_manageable(username)
      user = User.by_username(username)

      # If we do not have a user with this username, that username slot is
      # available for external logins.
      unless user then
        @rlog.info("username '#{ username }' is available for external logins")
        return true
      end

      unless user.external_id.to_s.empty? then
        # User is managed by external logins, if external_id is set to a
        # non-empty value.
        @rlog.info("username '#{ username }' has non-empty external id, ok")
        return true
      end

      message = "user '#{ username }' exists but does not have" \
                  + ' an external id set, refusing to manage'
      raise ExternalLoginNotConfigured, message
    end

    def new_external_service_handler()
      @external_login_class.new(@external_login_params,
                                @login_service_name,
                                @rlog)
    end

    def set_puavo_password(username, external_id, password, new_password,
                           fallback_to_admin_dn=false)
      begin
        users = User.by_attr(:external_id, external_id, :multiple => true)
        user = users.first
        if !user then
          msg = "user with external id '#{ external_id }' (#{ username }?)" \
                  + ' not found in Puavo, can not change/invalidate password'
          @rlog.info(msg)
          return ExternalLoginStatus::NOCHANGE
        elsif users.count > 1
          raise "multiple users with the same external id: #{ external_id }"
        end

        # Do not always use the @admin_dn to set password, because we might
        # want to invalidate password in case login to an external service
        # has failed with the password, and we want to do that only when
        # the new password is valid to Puavo.

        res = Puavo.change_passwd(:no_upstream,
                                  CONFIG['ldap'],
                                  user.dn,
                                  nil,
                                  password,
                                  user.username,
                                  new_password,
                                  '???')  # we have no request ID here
        case res[:exit_status]
        when Net::LDAP::ResultCodeInvalidCredentials
          if fallback_to_admin_dn then
            res = Puavo.change_passwd(:no_upstream,
                                      CONFIG['ldap'],
                                      @admin_dn,
                                      nil,
                                      @admin_password,
                                      user.username,
                                      new_password,
                                      '???')    # we have no request ID here
            if res[:exit_status] == Net::LDAP::ResultCodeSuccess then
              return ExternalLoginStatus::UPDATED
            end

            raise "unexpected exit code (#{ res[:exit_status] }):" \
                    " with admin dn/password: #{ res[:stderr] }"
          end
        when Net::LDAP::ResultCodeSuccess
          if password != new_password then
            return ExternalLoginStatus::UPDATED
          end
        else
          raise "unexpected exit code (#{ res[:exit_status] }): " \
                  + res[:stderr]
        end
      rescue StandardError => e
        raise ExternalLoginError,
              "error in set_puavo_password(): #{ e.message }"
      end

      return ExternalLoginStatus::NOCHANGE
    end

    def manage_groups_for_user(user, external_groups_by_type)
      external_login_status = ExternalLoginStatus::NOCHANGE

      user.schools.each do |school|
        external_groups_by_type.each do |ext_group_type, external_groups|

          if [ 'teaching group', 'year class' ].include?(ext_group_type) then
            if external_groups.count > 1 then
              @rlog.warn("trying to add '#{ user.username }' to"             \
                           + " #{ external_groups.count } groups of type"    \
                           + " '#{ ext_group_type }', which is not allowed," \
                           + ' not proceeding, check your external_login'    \
                           + ' configuration.')
              next
            end
          end

          puavo_group_list \
            = Group.by_attr(:type, ext_group_type, :multiple => true) \
                   .select { |pg| pg.external_id }

          external_groups.each do |ext_group_name, ext_group_displayname|
            @rlog.info("making sure user '#{ user.username }' belongs to" \
                         + " a puavo group '#{ ext_group_name }'" \
                         + " / #{ ext_group_displayname }")

            puavo_group = nil
            puavo_group_list.each do |candidate_puavo_group|
              next unless candidate_puavo_group.abbreviation == ext_group_name
              puavo_group = candidate_puavo_group
              if puavo_group.name != ext_group_displayname then
                @rlog.info('updating group name'                \
                             + " for '#{ puavo_group.abbreviation }'" \
                             + " from '#{ puavo_group.name }'"        \
                             + " to '#{ ext_group_displayname }'")

                puavo_group.name = ext_group_displayname
                puavo_group.save!
                external_login_status = ExternalLoginStatus::UPDATED
              end
            end

            unless puavo_group then
              @rlog.info('creating a new puavo group of type'           \
                           + " '#{ ext_group_type }' to school"         \
                           + " '#{ school.abbreviation }'"              \
                           + " with abbreviation '#{ ext_group_name }'" \
                           + " and name '#{ ext_group_displayname }'")

              puavo_group \
                = PuavoRest::Group.new(:abbreviation => ext_group_name,
                                       :external_id  => ext_group_name,
                                       :name         => ext_group_displayname,
                                       :school_dn    => school.dn,
                                       :type         => ext_group_type)
              puavo_group.save!
              external_login_status = ExternalLoginStatus::UPDATED
            end

            unless puavo_group.has?(user) then
              @rlog.info("adding user '#{ user.username }'" \
                           + " to group '#{ ext_group_displayname }'")
              puavo_group.add_member(user)
              puavo_group.save!
              external_login_status = ExternalLoginStatus::UPDATED
            end
          end

          puavo_group_list.each do |puavo_group|
            unless external_groups.has_key?(puavo_group.abbreviation) then
              if puavo_group.has?(user) then
                @rlog.info("removing user '#{ user.username }' from group" \
                             + " '#{ puavo_group.abbreviation }'")
                puavo_group.remove_member(user)
                puavo_group.save!
                external_login_status = ExternalLoginStatus::UPDATED
              end
            end
            # if puavo_group.member_dns.empty? then
            #   # We could maybe remove a puavo group here, BUT a group
            #   # is associated with a gid, which might be associated with
            #   # files, so do not do it.  Perhaps mark it for removal and
            #   # remove later?
            # end
          end
        end
      end

      return external_login_status
    end

    def update_user_info(userinfo, password, params)
      if userinfo['school_dns'].empty? then
        school_dn_param = params[:school_dn].to_s
        if !school_dn_param.empty? then
          userinfo['school_dns'] = [ school_dn_param ]
        end
      end
      if userinfo['school_dns'].empty? then
        raise ExternalLoginError,
              "could not determine user school for #{ userinfo['username'] }"
      end

      if userinfo['roles'].empty? then
        role_param = params[:role].to_s
        if !role_param.empty? then
          userinfo['roles'] = [ role_param ]
        end
      end
      if userinfo['roles'].empty? then
        raise ExternalLoginError,
              "could not determine user role for #{ userinfo['username'] }"
      end

      external_groups_by_type = userinfo.delete('external_groups')

      user_update_status = nil

      begin
        users = User.by_attr(:external_id,
                             userinfo['external_id'],
                             :multiple => true)
        user = users.first
        userinfo = adjust_userinfo(user, userinfo)

        if !user then
          user = User.new(userinfo)
          user.save!
          @rlog.info("created a new user '#{ userinfo['username'] }'")
          user_update_status = ExternalLoginStatus::UPDATED
        elsif users.count > 1 then
          raise 'multiple users with the same external id: ' \
                  + userinfo['external_id']
        elsif user.check_if_changed_attributes(userinfo) then
          user.update!(userinfo)
          user.removal_request_time = nil
          user.save!
          @rlog.info("updated user information for '#{ userinfo['username'] }'")
          user_update_status = ExternalLoginStatus::UPDATED
        else
          if user.removal_request_time then
            user.removal_request_time = nil
            user.save!
          end

          @rlog.info('no change in user information for' \
                       + " '#{ userinfo['username'] }'")
          user_update_status = ExternalLoginStatus::NOCHANGE
        end
      rescue ValidationError => e
        raise ExternalLoginError,
              "error saving user because of validation errors: #{ e.message }"
      end

      if password then
        pw_update_status = set_puavo_password(userinfo['username'],
                                              userinfo['external_id'],
                                              password,
                                              password,
                                              true)
      else
        pw_update_status = ExternalLoginStatus::NOCHANGE
      end

      mg_update_status = manage_groups_for_user(user, external_groups_by_type)

      return ExternalLoginStatus::UPDATED \
        if (user_update_status    == ExternalLoginStatus::UPDATED \
              || pw_update_status == ExternalLoginStatus::UPDATED \
              || mg_update_status == ExternalLoginStatus::UPDATED)

      return ExternalLoginStatus::NOCHANGE
    end

    def adjust_userinfo(user, userinfo)
      return userinfo unless user

      # We want to get "student" and "teacher" roles from the
      # external login information, but others such as "admin"-role
      # we want to maintain ourselves.
      new_user_roles = user.roles.reject do |role|
                         %w(student teacher).include?(role)
                       end + userinfo['roles']
      userinfo['roles'] = new_user_roles.sort.uniq

      userinfo
   end

    def self.status(status_string, msg)
      { 'msg' => msg, 'status' => status_string }
    end

    def self.status_badusercreds(msg=nil)
      status(ExternalLoginStatus::BADUSERCREDS,
             (msg || 'auth FAILED, username or password was wrong'))
    end

    def self.status_configerror(msg=nil)
      status(ExternalLoginStatus::CONFIGERROR,
             (msg || 'external logins configuration error'))
    end

    def self.status_nochange(msg=nil)
      status(ExternalLoginStatus::NOCHANGE,
             (msg || 'auth OK, no change to user information'))
    end

    def self.status_notconfigured(msg=nil)
      status(ExternalLoginStatus::NOTCONFIGURED,
             (msg || 'external logins not configured'))
    end

    def self.status_unavailable(msg=nil)
      status(ExternalLoginStatus::UNAVAILABLE,
             (msg || 'external login service not available'))
    end

    def self.status_updated(msg=nil)
      status(ExternalLoginStatus::UPDATED,
             (msg || 'auth OK, user information updated'))
    end

    def self.status_updated_but_fail(msg=nil)
      status(ExternalLoginStatus::UPDATED_BUT_FAIL,
             (msg || 'auth FAILED, user information updated'))
    end

    def self.status_updateerror(msg=nil)
      status(ExternalLoginStatus::UPDATEERROR,
             (msg || 'error when updating user information in Puavo'))
    end
  end

  class ExternalLoginService
    attr_reader :service_name

    def initialize(service_name, rlog)
      @rlog         = rlog
      @service_name = service_name
    end
  end

  class ExternalLdapService < ExternalLoginService
    def initialize(ldap_config, service_name, rlog)
      super(service_name, rlog)

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

      @external_id_field = @ldap_config['external_id_field']
      raise ExternalLoginConfigError, 'external_id_field not configured' \
        unless @external_id_field.kind_of?(String)

      @external_username_field = @ldap_config['external_username_field']
      raise ExternalLoginConfigError, 'external_username_field not configured' \
        unless @external_username_field.kind_of?(String)

      @external_password_change = @ldap_config['password_change']
      raise ExternalLoginConfigError, 'password_change style not configured' \
        unless @external_password_change.kind_of?(Hash)

      @external_ldap_subtrees = @ldap_config['subtrees']
      raise ExternalLoginConfigError, 'subtrees not configured' \
        unless @external_ldap_subtrees.kind_of?(Array) \
                 && @external_ldap_subtrees.all? { |s| s.kind_of?(String) }

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
                'password change api not configured'
      end

      return true
    end

    def lookup_external_id(username)
      update_ldapuserinfo(username)

      external_id = @ldap_userinfo \
                      && Array(@ldap_userinfo[@external_id_field]).first.to_s
      if !external_id || external_id.empty? then
        raise ExternalLoginUnavailable,
              "could not lookup external id for user '#{ username }'"
      end

      external_id
    end

    # XXX we can throw this out if we lookup all users anyway
    def user_exists?(external_id)
      user_filter = Net::LDAP::Filter.eq(@external_id_field, external_id)

      ldap_entries = ext_ldapop('user_exists?/search',
                                :search,
                                :filter => user_filter,
                                :time   => 5)
      if !ldap_entries then
        msg = "ldap search for user '#{ username }' failed: " \
                + @ldap.get_operation_result.message
        raise ExternalLoginUnavailable, msg
      end

      return false if ldap_entries.count == 0

      if ldap_entries.count > 1
        raise ExternalLoginUnavailable, 'ldap search returned too many entries'
      end

      return true
    end

    def get_userinfo(username)
      raise 'ldap userinfo not set' unless @username && @ldap_userinfo

      userinfo = {
        'external_id' => lookup_external_id(username),
        'first_name'  => Array(@ldap_userinfo['givenname']).first.to_s,
        'last_name'   => Array(@ldap_userinfo['sn']).first.to_s,
        'username'    => username,
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

      # We presume that ldap result strings are UTF-8.
      userinfo.each do |key, value|
        Array(value).map { |s| s.force_encoding('UTF-8') }
      end

      # we apply some magicks to determine user school, groups and roles
      apply_user_mappings!(userinfo,
                           [ [ Array(@ldap_userinfo['dn']),
                               @user_mappings_by_dn ],
                             [ Array(@ldap_userinfo['memberof']),
                               @user_mappings_by_memberof ]])

      userinfo
    end

    def lookup_all_users
      users = {}

      user_filter = Net::LDAP::Filter.eq(@external_id_field, '*') \
                      & Net::LDAP::Filter.eq(@external_username_field, '*')

      id_sym       = @external_id_field.downcase.to_sym
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
          external_id = Array(ldap_entry[id_sym]).first
          next unless external_id.kind_of?(String)

          userprincipalname = Array(ldap_entry[username_sym]).first
          next unless userprincipalname.kind_of?(String)

          match = userprincipalname.match(/\A(.*)@/)
          next unless match

          users[ external_id ] = {
            'ldap_entry' => ldap_entry,
            'username'   => match[1],
          }
        end
      end

      return users
    end

    def set_ldapuserinfo(username, ldap_userinfo)
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
      unless value.kind_of?(String) && !value.empty? then
        raise "add group attribute '#{ param_name }' not configured"
      end
      value.clone
    end

   def format_groupdata(groupdata_string, params)
     formatting_needed = groupdata_string.include?('%CLASSNUMBER')    \
                           || groupdata_string.include?('%GROUP')     \
                           || groupdata_string.include?('%STARTYEAR')

     return groupdata_string unless formatting_needed

     teaching_group_field = get_add_groups_param(params, 'teaching_group_field')

     ldap_attribute_value = Array(@ldap_userinfo[teaching_group_field]).first
     unless ldap_attribute_value.kind_of?(String) then
       # not all users have (teachers and such) have teaching group fields
       return nil
     end

     teaching_group_regex = get_add_groups_param(params, 'teaching_group_regex')
     match = ldap_attribute_value.match(teaching_group_regex)
     unless match && match.size == 2 then
       @rlog.warn('unexpected format in ldap attribute' \
                    + " '#{ teaching_group_field }':" \
                    + " '#{ ldap_attribute_value }'" \
                    + " (expecting a match with '#{ teaching_group_regex }'" \
                    + " that should also have one string capture)")
       return nil
     end
     teaching_group = match[1]

     groupdata_string.sub!('%GROUP', teaching_group)

     return groupdata_string unless groupdata_string.include?('%CLASSNUMBER') \
                                      || groupdata_string.include?('%STARTYEAR')

     classnum_regex = get_add_groups_param(params, 'classnumber_regex')
     match = ldap_attribute_value.match(classnum_regex)
     unless match && match.size == 2 then
       @rlog.warn('unexpected format in ldap attribute' \
                    + " '#{ teaching_group_field }':" \
                    + " '#{ ldap_attribute_value }'" \
                    + " (expecting a match with '#{ classnum_regex }'" \
                    + " that should also have one integer capture)")
       return nil
     end

     class_number = Integer(match[1])

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

      set_ldapuserinfo(nil, nil)

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
        msg = "user '#{ username }' does not exist in external ldap"
        puavouser = User.by_username(username)
        raise ExternalLoginUserMissing, msg \
          unless puavouser && puavouser.external_id

        extid_filter = Net::LDAP::Filter.eq(@external_id_field,
                                            puavouser.external_id)
        extid_ldap_entries = ext_ldapop('update_ldapuserinfo/search_extid',
                                        :search,
                                        :filter => extid_filter,
                                        :time   => 5)
        if !extid_ldap_entries then
          msg = "ldap search for external_id '#{ puavouser.external_id }'" \
                  + " failed: #{ @ldap.get_operation_result.message }"
          raise ExternalLoginUnavailable, msg
        end

        if extid_ldap_entries.count == 0 then
          msg = "user '#{ username }' (#{ puavouser.external_id }) does not" \
                  + ' exist in external ldap'
          raise ExternalLoginUserMissing, msg
        end

        # User exists in Puavo and in external ldap, but wrong username was
        # used for login (we could lookup another user in the external ldap
        # with the same external id as is associated with this username
        # in Puavo).
        raise ExternalLoginWrongCredentials, msg
      end

      if ldap_entries.count > 1
        raise ExternalLoginUnavailable, 'ldap search returned too many entries'
      end

      @rlog.info("looked up user '#{ username }' from external ldap")

      set_ldapuserinfo(username, ldap_entries.first)
    end

    def user_ldapfilter(username)
      Net::LDAP::Filter.eq(@external_username_field,
                           "#{ Net::LDAP::Filter.escape(username) }@*")

    end
  end
end
