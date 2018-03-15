require 'net/ldap'
require 'securerandom'

# ExternalLoginError means some error occurred on our side
# ExternalLoginNotConfigured means external logins are not configured
#   in whatever particular case
# ExternalLoginUnavailable means an error at external service
# ExternalLoginUserMissing means user could not found at external service
# ExternalLoginWrongPassword means user is valid but had a wrong password

class ExternalLoginError         < StandardError; end
class ExternalLoginNotConfigured < ExternalLoginError; end
class ExternalLoginUnavailable   < ExternalLoginError; end
class ExternalLoginUserMissing   < ExternalLoginError; end
class ExternalLoginWrongPassword < ExternalLoginError; end

module PuavoRest
  class ExternalLogins < PuavoSinatra
    post '/v3/external_login' do
      userinfo = nil
      user_status = nil

      begin
        username = params[:username].to_s
        if username.empty? then
          raise BadCredentials, :user => 'no username provided'
        end
        password = params[:password].to_s
        if password.empty? then
          raise BadCredentials, :user => 'no password provided'
        end

        external_login = ExternalLogin.new(CONFIG['external_login'],
                                           flog,
                                           request.host)
        external_login.setup_puavo_connection()
        external_login.check_user_is_manageable(username)

        login_service = external_login.new_external_service_handler()

        wrong_password = false
        begin
          message = 'attempting external login to service' \
                      + " '#{ login_service.service_name }' by user" \
                      + " '#{ username }'"
          flog.info('external login attempt', message)
          userinfo = login_service.login(username, password)
        rescue ExternalLoginUserMissing => e
          flog.info('user does not exist in external ldap', e.message)
          userinfo = nil
        rescue ExternalLoginWrongPassword => e
          flog.info('user provided wrong password', e.message)
          userinfo = nil
          wrong_password = true
        rescue ExternalLoginError => e
          raise e
        rescue StandardError => e
          # Unexpected errors when authenticating to external service means
          # it was not available.
          raise ExternalLoginUnavailable, e
        end

        if wrong_password then
          external_id = login_service.lookup_external_id(username)
          invalidated = external_login.maybe_invalidate_password(username,
                                                                 external_id,
                                                                 password)
          if invalidated then
            msg = 'user password invalidated'
            return json(ExternalLogin.status_updated_but_fail(msg))
          end
        elsif !userinfo then
          # no user information, but password was not wrong, therefore
          # user information is missing from external login service
          # and user must be removed from Puavo.
          user_to_remove = User.by_username(username)
          # XXX user_to_remove object does not currently support removing!
          # XXX Besides, even if the user is removed (from Puavo),
          # XXX its kerberos credentials stay, thus user may remain
          # XXX usable in some contexts!  These issues should be solved
          # XXX before enabling this:
          # XXX
          # XXX     user_to_remove.destroy if user_to_remove
          # XXX
          # XXX instead of removing we should invalidate the password
          # XXX and lock the account (or otherwise mark it for removal...
          # XXX maybe after some days/weeks/months).
          # XXX maybe_invalidate_password() does not work, because we may not
          # XXX have the correct password.  Instead we should just overwrite it
          # XXX directory.
        end

        if !userinfo then
          msg = 'could not login to external service' \
                  + " '#{ login_service.service_name }' by user" \
                  + " '#{ username }', username or password was wrong"
          return json(ExternalLogin.status_badusercreds(msg))
        end

        # update user information after successful login

        message = 'successful login to external service' \
                    + " by user '#{ userinfo['username'] }'"
        flog.info('external login successful', message)

        begin
          user_status = external_login.update_user_info(userinfo, params)
        rescue StandardError => e
          return json(ExternalLogin.status_updateerror(e.message))
        end

      rescue ExternalLoginNotConfigured => e
        flog.info('external login not configured',
                  "external login is not configured: #{ e.message }")
        user_status = ExternalLogin.status_notconfigured(e.message)
      rescue ExternalLoginUnavailable => e
        flog.warn('external login unavailable',
                  "external login is unavailable: #{ e.message }")
        user_status = ExternalLogin.status_unavailable(e.message)
      rescue StandardError => e
        raise InternalError, e
      end

      return json(user_status)
    end
  end

  class ExternalLogin
    USER_STATUS_BADUSERCREDS     = 'BADUSERCREDS'
    USER_STATUS_NOCHANGE         = 'NOCHANGE'
    USER_STATUS_NOTCONFIGURED    = 'NOTCONFIGURED'
    USER_STATUS_UNAVAILABLE      = 'UNAVAILABLE'
    USER_STATUS_UPDATED          = 'UPDATED'
    USER_STATUS_UPDATED_BUT_FAIL = 'UPDATED_BUT_FAIL'
    USER_STATUS_UPDATEERROR      = 'UPDATEERROR'

    def initialize(config, flog, host)
      # Parse config with relevant information for doing external logins.

      @flog = flog

      all_external_login_configs = config
      raise ExternalLoginNotConfigured, 'external login not configured' \
        unless all_external_login_configs

      @organisation = Organisation.by_domain(host)
      raise ExternalLoginError,
        'could not determine organisation from request host' \
          unless @organisation && @organisation.domain.kind_of?(String)

      organisation_name = @organisation.domain.split('.')[0]
      raise ExternalLoginError,
        'could not parse organisation from organisation domain' \
          unless organisation_name

      @external_login_config = all_external_login_configs[organisation_name]
      raise ExternalLoginNotConfigured,
        'external_login not configured for this organisation' \
          unless @external_login_config

      @login_service_name = @external_login_config['service']
      raise ExternalLoginError, 'external_login service not set' \
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

      @external_login_params = @external_login_config[@login_service_name]
      raise ExternalLoginError,
        'external login parameters not configured' \
          unless @external_login_params.kind_of?(Hash)

      @admin_dn = @external_login_config['admin_dn'].to_s
      raise ExternalLoginError, 'admin dn is not set' \
        if @admin_dn.empty?

      @admin_password = @external_login_config['admin_password'].to_s
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
      return true unless user

      # User is managed by external logins, if external_id is set to a
      # non-empty value.
      return true unless user.external_id.to_s.empty?

      message = "user '#{ username }' exists but does not have" \
                  + ' an external id set, refusing to manage'
      raise ExternalLoginNotConfigured, message
    end

    def new_external_service_handler()
      @external_login_class.new(@external_login_params,
                                @login_service_name,
                                @flog)
    end

    def maybe_invalidate_password(username, external_id, password)
      user = User.by_attr(:external_id, external_id)
      if !user then
        msg = "user with external id '#{ external_id }' (#{ username }?)" \
              + ' not found in Puavo, no password to invalidate'
        @flog.info(nil, msg)
        return false
      end

      # change user password to something random and just throw it away
      new_password = SecureRandom.hex(128)

      # Let the user try itself change the password to a random string with
      # his/her own credentials.  We know the password was bad with the
      # external service, so if it works here, we invalidate it, which is
      # what we want.
      res = Puavo.ldap_passwd(CONFIG['ldap'],
                              user.dn,
                              password,
                              new_password,
                              user.dn)
      case res[:exit_status]
      when Net::LDAP::ResultCodeInvalidCredentials
        # invalid credentials, which is to be expected
      when Net::LDAP::ResultCodeSuccess
        # The password was valid for Puavo, but not to external login
        # service, so we invalidated it.
        msg = 'invalidated puavo password for user with external id' \
                + " '#{ external_id }' (#{ username }?)" \
                + ' because external login failed with it'
        @flog.info(nil, msg)
        return true
      else
        msg = 'error occurred when running ldappasswd:' \
                + " (#{ res[:exit_status] }) #{ res[:stderr] }"
        @flog.warn(nil, msg)
      end

      return false
    end

    def update_user_info(userinfo, params)
      if userinfo['school_dns'].nil? then
        school_dn_param = params[:school_dn].to_s
        if !school_dn_param.empty? then
          userinfo['school_dns'] = [ school_dn_param ]
        else
          default_school_dns = @external_login_config['default_school_dns']
          if !default_school_dns.kind_of?(Array) then
            raise ExternalLoginError,
              'could not determine user school for' \
                + " '#{ userinfo['username'] }' and default school is not set"
          end
          userinfo['school_dns'] = default_school_dns
        end
      end

      if userinfo['roles'].nil? then
        role_param = params[:role].to_s
        if !role_param.empty? then
          userinfo['roles'] = [ role_param ]
        else
          default_roles = @external_login_config['default_roles']
          if !default_roles.kind_of?(Array) then
            raise ExternalLoginError,
              'could not determine user role for' \
                + " '#{ userinfo['username'] }' and default role is not set"
          end
          userinfo['roles'] = default_roles
        end
      end

      begin
        user = User.by_attr(:external_id, userinfo['external_id'])
        if !user then
          user = User.new(userinfo)
          user.save!
          @flog.info('new external login user',
                     "created a new user '#{ userinfo['username'] }'")
          return self.class.status_updated()
        elsif user.check_if_changed_attributes(userinfo) then
          user.update!(userinfo)
          user.save!
          @flog.info('updated external login user',
                     "updated user information for '#{ userinfo['username'] }'")
          return self.class.status_updated()
        else
          @flog.info('no change for external login user',
                     'no change in user information for' \
                       + " '#{ userinfo['username'] }'")
          return self.class.status_nochange()
        end
      rescue ValidationError => e
        raise ExternalLoginError,
              "error saving user because of validation errors: #{ e.message }"
      end
    end

    def self.status(status_string, msg)
      { 'msg' => msg, 'status' => status_string }
    end

    def self.status_badusercreds(msg=nil)
      status(USER_STATUS_BADUSERCREDS,
             (msg || 'auth FAILED, username or password was wrong'))
    end

    def self.status_nochange(msg=nil)
      status(USER_STATUS_NOCHANGE,
             (msg || 'auth OK, no change to user information'))
    end

    def self.status_notconfigured(msg=nil)
      status(USER_STATUS_NOTCONFIGURED,
             (msg || 'external logins not configured'))
    end

    def self.status_unavailable(msg=nil)
      status(USER_STATUS_UNAVAILABLE,
             (msg || 'external login service not available'))
    end

    def self.status_updated(msg=nil)
      status(USER_STATUS_UPDATED,
             (msg || 'auth OK, user information updated'))
    end

    def self.status_updated_but_fail(msg=nil)
      status(USER_STATUS_UPDATED_BUT_FAIL,
             (msg || 'auth FAILED, user information updated'))
    end

    def self.status_updateerror(msg=nil)
      status(USER_STATUS_UPDATEERROR,
             (msg || 'error when updating user information in Puavo'))
    end
  end

  class ExternalLoginService
    attr_reader :service_name

    def initialize(service_name, flog)
      @flog         = flog
      @service_name = service_name
    end
  end

  class ExternalLdapService < ExternalLoginService
    def initialize(ldap_config, service_name, flog)
      super(service_name, flog)

      base = ldap_config['base']
      raise ExternalLoginError, 'ldap base not configured' \
        unless base

      bind_dn = ldap_config['bind_dn']
      raise ExternalLoginError, 'ldap bind dn not configured' \
        unless bind_dn

      bind_password = ldap_config['bind_password']
      raise ExternalLoginError, 'ldap bind password not configured' \
        unless bind_password

      server = ldap_config['server']
      raise ExternalLoginError, 'ldap server not configured' \
        unless server

      @dn_mappings = ldap_config['dn_mappings']

      @ldap = Net::LDAP.new :base => base.to_s,
                            :host => server.to_s,
                            :port => (Integer(ldap_config['port']) rescue 389),
                            :auth => {
                              :method   => :simple,
                              :username => bind_dn.to_s,
                              :password => bind_password.to_s,
                            },
                            :encryption => {
                               :method      => :start_tls,
                               :tls_options => {
                                 :verify_mode => OpenSSL::SSL::VERIFY_NONE,
                               },
                               # XXX not good
                               # XXX see http://www.rubydoc.info/github/ruby-ldap/ruby-net-ldap/Net%2FLDAP:initialize
                               # XXX and http://ruby-doc.org/stdlib-2.3.0/libdoc/openssl/rdoc/OpenSSL/SSL/SSLContext.html
                               # XXX should this be configurable through
                               # XXX ldap_config?
                            }
      @ldap_userinfo = nil
      @username = nil
    end

    def login(username, password)
      # first check if user exists
      update_ldapuserinfo(username)

      user_filter = Net::LDAP::Filter.eq('sAMAccountName', username)

      # then authenticate as user
      ldap_entries = @ldap.bind_as(:filter   => user_filter,
                                   :password => password)
      if !ldap_entries then
        message = 'authentication to ldap failed:' \
                    + " #{ @ldap.get_operation_result.message }"
        code = @ldap.get_operation_result.code
        if code == Net::LDAP::ResultCodeInvalidCredentials then
          message += ' (user password was wrong)'
          raise ExternalLoginWrongPassword, message
        end

        raise ExternalLoginUnavailable, message
      end
      raise ExternalLoginUnavailable, 'ldap bind returned too many entries' \
        unless ldap_entries.length == 1

      @flog.info('authentication to ldap succeeded',
                 'authentication to ldap succeeded')

      get_userinfo(username, password)
    end

    def lookup_external_id(username)
      update_ldapuserinfo(username)

      # XXX The field name "employeeNumber" should probably be configurable.
      external_id = @ldap_userinfo \
                      && Array(@ldap_userinfo['employeeNumber']).first.to_s
      if !external_id || external_id.empty? then
        raise ExternalLoginUnavailable,
              "could not lookup external id for user '#{ username }'"
      end

      external_id
    end

    private

    def get_groups()
      # XXX not tested yet
      lookup_groups_filter \
        = Net::LDAP::Filter.eq('objectClass', 'posixGroup') \
            .&(Net::LDAP::Filter.eq('memberUid', @username))
      groups_result = @ldap.search(:filter => lookup_groups_filter)
      Hash[
        groups_result.map do |g|
          [ Array(g['cn']).first, Array(g['displayname']).first ]
        end
      ]
    end

    def get_userinfo(username, password)
      # XXX validate that these are not nonsense?

      userinfo = {
        'external_id' => lookup_external_id(username),
        'first_name'  => Array(@ldap_userinfo['givenname']).first.to_s,
        # 'groups'     => groups,       # XXX use get_groups() once it's ready
        'last_name'   => Array(@ldap_userinfo['sn']).first.to_s,
        'password'    => password,
        'username'    => Array(@ldap_userinfo['sAMAccountName']).first.to_s,
      }

      # we apply some magicks to determine user school and roles
      apply_dn_mappings!(userinfo, Array(@ldap_userinfo['dn']).first.to_s)

      # XXX We presume that ldap result strings are UTF-8.  This might be a
      # XXX wrong presumption, and this should be configurable.
      userinfo.each do |key, value|
        Array(value).map { |s| s.force_encoding('UTF-8') }
      end

      userinfo
    end

    def apply_dn_mappings!(userinfo, user_dn)
      return unless @dn_mappings

      unless @dn_mappings.kind_of?(Array) then
        raise ExternalLoginNotConfigured,
              'external_login dn_mappings is not an array'
      end

      added_roles      = []
      added_school_dns = []

      @dn_mappings.each do |dn_mapping|
        unless dn_mapping.kind_of?(Hash) then
          raise ExternalLoginNotConfigured,
                'external_login dn_mapping is not a hash'
        end

        dn_mapping.each do |dn_glob_pattern, operations_list|
          next unless File.fnmatch(dn_glob_pattern, user_dn)

          unless operations_list.kind_of?(Array) then
            raise ExternalLoginNotConfigured,
                  'external_login dn_mapping operations list' \
                    + " for dn_glob_pattern '#{ dn_glob_pattern }'" \
                    + ' is not an array'
          end

          operations_list.each do |op_item|
            unless op_item.kind_of?(Hash) then
              raise ExternalLoginNotConfigured,
                    'external_login dn_mapping operation list item' \
                      + " for dn_glob_pattern '#{ dn_glob_pattern }'" \
                      + ' is not a hash'
            end

            op_item.each do |op_name, op_params|
              if %w(add_roles add_school_dns).include?(op_name) then
                params_type_ok = op_params.kind_of?(Array) \
                                   && op_params.all? { |x| x.kind_of?(String) }
                unless params_type_ok then
                  raise ExternalLoginNotConfigured,
                        "#{ op_name } operation parameters type" \
                          + " for dn_glob_pattern '#{ dn_glob_pattern }'" \
                          + ' is not an array of strings'
                end
              end

              case op_name
              when 'add_roles'
                added_roles += op_params
              when 'add_school_dns'
                added_school_dns += op_params
              else
                raise ExternalLoginNotConfigured,
                      "unsupported operation '#{ op_name }'" \
                        + " for dn_glob_pattern '#{ dn_glob_pattern }'"
              end
            end
          end
        end
      end

      userinfo['roles'] = ((userinfo['roles'] || []) + added_roles).sort.uniq
      userinfo['school_dns'] \
        = ((userinfo['school_dns'] || []) + added_school_dns).sort.uniq
    end

    def update_ldapuserinfo(username)
      return if @username && @username == username

      user_filter = Net::LDAP::Filter.eq('sAMAccountName', username)

      ldap_entries = @ldap.search(:filter => user_filter)
      if !ldap_entries then
        msg = "ldap search for user '#{ username }' failed: " \
                + @ldap.get_operation_result.message
        raise ExternalLoginUnavailable, msg
      end

      if ldap_entries.length == 0 then
        msg = "user '#{ username }' does not exist in external ldap"
        raise ExternalLoginUserMissing, msg
      end

      if ldap_entries.length > 1
        raise ExternalLoginUnavailable, 'ldap search returned too many entries'
      end

      @flog.info('looked up user from external ldap',
                 "looked up user '#{ username }' from external ldap")
      @username = username
      @ldap_userinfo = ldap_entries.first
    end
  end
end
