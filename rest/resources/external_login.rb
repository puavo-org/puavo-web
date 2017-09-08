def no_verbose(&block)
  old_verbose = $VERBOSE
  $VERBOSE = nil
  yield
  $VERBOSE = old_verbose
end

# Silence deprecated warning.  Remove once not needed anymore
# (but now it shows up constantly in the logs).
no_verbose { require 'mechanize' }
require 'net/ldap'
require 'securerandom'

# ExternalLoginError means some error occurred on our side
# ExternalLoginNotConfigured means external logins are not configured
#   in whatever particular case
# ExternalLoginUnavailable means an error at external service
# ExternalLoginWrongPassword means user is valid but had a wrong password

class ExternalLoginError         < StandardError; end
class ExternalLoginNotConfigured < ExternalLoginError; end
class ExternalLoginUnavailable   < ExternalLoginError; end
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
        rescue ExternalLoginWrongPassword => e
          wrong_password = true
        rescue ExternalLoginError => e
          raise e
        rescue StandardError => e
          # Unexpected errors when authenticating to external service means
          # it was not available.
          raise ExternalLoginUnavailable, e
        end

        if wrong_password then
          if external_login.maybe_invalidate_password(username, password) then
            msg = 'user password invalidated'
            return json(external_login.status_updated_but_fail(msg))
          end
          userinfo = nil
        end

        if !userinfo then
          msg = 'could not login to external service' \
                  + " '#{ login_service.service_name }' by user" \
                  + " '#{ username }'"
          raise Unauthorized, :user => msg
        end

        # update user information after successful login

        message = 'successful login to external service' \
                    + " by user '#{ userinfo['username'] }'"
        flog.info('external login successful', message)

        school_dn = params[:school_dn].to_s
        user_status = external_login.update_user_info(userinfo, school_dn)

      rescue ExternalLoginNotConfigured => e
        flog.info('external login not configured',
                  "external login is not configured: #{ e.message }")
        user_status = external_login.status_notconfigured(e.message)
      rescue ExternalLoginUnavailable => e
        flog.warn('external login unavailable',
                  "external login is unavailable: #{ e.message }")
        user_status = external_login.status_unavailable(e.message)
      rescue ExternalLoginError => e
        flog.error('external login error',
                   "external login error: #{ e.message }")
        raise InternalError, e
      rescue StandardError => e
        raise InternalError, e
      end

      return json(user_status)
    end
  end

  class ExternalLogin
    USER_STATUS_NOCHANGE         = 'NOCHANGE'
    USER_STATUS_NOTCONFIGURED    = 'NOTCONFIGURED'
    USER_STATUS_UNAVAILABLE      = 'UNAVAILABLE'
    USER_STATUS_UPDATED          = 'UPDATED'
    USER_STATUS_UPDATED_BUT_FAIL = 'UPDATED_BUT_FAIL'

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

      loginclass_map = {
        'external_ldap'  => ExternalLdapService,
        'external_wilma' => ExternalWilmaService,
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
      return true if !user.external_id.to_s.empty?

      message = "user '#{ username }' exists but does not have" \
                  + ' an external id set, refusing to manage'
      raise ExternalLoginNotConfigured, message
    end

    def new_external_service_handler()
      @external_login_class.new(@external_login_params,
                                @login_service_name,
                                @flog)
    end

    def maybe_invalidate_password(username, password)
      user = User.by_username(username)
      if !user then
        msg = "user '#{ username }' not found in Puavo," \
                + ' no password to invalidate'
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
      when 49
        # 49 exit status means invalid credentials, which is to be expected
      when 0
        # The password was valid for Puavo, but not to external login
        # service, so we invalidated it.
        msg = "invalidated puavo password for user '#{ username }'," \
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

    def update_user_info(userinfo, school_dn)
      if userinfo['school_dns'].nil? then
        if !school_dn.empty? then
          userinfo['school_dns'] = [ school_dn ]
        else
          default_school_dns = @external_login_config['default_school_dns']
          if !default_school_dns.kind_of?(Array) then
            raise ExternalLoginError,
              "school dn is not known for '#{ userinfo['username'] }'" \
                + ' and default school is not set'
          end
          userinfo['school_dns'] = default_school_dns
        end
      end

      if userinfo['roles'].nil? then
        default_roles = @external_login_config['default_roles']
        if !default_roles.kind_of?(Array) then
          raise ExternalLoginError,
            "role is not known for '#{ userinfo['username'] }'" \
              + ' and default role is not set'
        end
        userinfo['roles'] = default_roles
      end

      begin
        user = User.by_attr(:external_id, userinfo['external_id'])
        if !user then
          user = User.new(userinfo)
          user.save!
          @flog.info('new external login user',
                     "created a new user '#{ userinfo['username'] }'")
          return status_updated()
        elsif user.check_if_changed_attributes(userinfo) then
          user.update!(userinfo)
          user.save!
          @flog.info('updated external login user',
                     "updated user information for '#{ userinfo['username'] }'")
          return status_updated()
        else
          @flog.info('no change for external login user',
                     'no change in user information for' \
                       + " '#{ userinfo['username'] }'")
          return status_nochange()
        end
      rescue ValidationError => e
        raise ExternalLoginError,
              "error saving user because of validation errors: #{ e.message }"
      end
    end

    def status(status_string, msg)
      { 'msg' => msg, 'status' => status_string }
    end

    def status_nochange(msg=nil)
      status(USER_STATUS_NOCHANGE,
             (msg || 'auth OK, no change to user information'))
    end

    def status_notconfigured(msg=nil)
      status(USER_STATUS_NOTCONFIGURED,
             (msg || 'external logins not configured'))
    end

    def status_unavailable(msg=nil)
      status(USER_STATUS_UNAVAILABLE,
             (msg || 'external login service not available'))
    end

    def status_updated(msg=nil)
      status(USER_STATUS_UPDATED,
             (msg || 'auth OK, user information updated'))
    end

    def status_updated_but_fail(msg=nil)
      status(USER_STATUS_UPDATED_BUT_FAIL,
             (msg || 'auth FAILED, user information updated'))
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

      @ldap = Net::LDAP.new :base => base.to_s,
                            :host => server.to_s,
                            :port => (Integer(ldap_config['port']) rescue 636),
                            :auth => {
                              :method   => :simple,
                              :username => bind_dn.to_s,
                              :password => bind_password.to_s,
                            },
                            :encryption => :simple_tls   # XXX not sufficient!
    end

    def login(username, password)
      user_filter = Net::LDAP::Filter.eq('cn', username)

      # first check if user exists
      ldap_entries = @ldap.search(:filter => user_filter)
      if ldap_entries.length == 0 then
        @flog.info('user does not exist in external ldap',
                   'user does not exist in external ldap')
        return nil
      end
      raise ExternalLoginUnavailable, 'ldap search returned too many entries' \
        unless ldap_entries.length == 1

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
      ldap_entry = ldap_entries.first

      lookup_groups_filter \
        = Net::LDAP::Filter.eq('objectClass', 'posixGroup') \
            .&(Net::LDAP::Filter.eq('memberUid', username))
      groups_result = @ldap.search(:filter => lookup_groups_filter)
      groups = Hash[
        groups_result.map do |g|
          [ Array(g['cn']).first, Array(g['displayname']).first ]
        end
      ]

      # XXX check that these are not nonsense?
      userinfo = {
        'external_id' => Array(ldap_entry['dn']).first.to_s,
        'first_name'  => Array(ldap_entry['givenname']).first.to_s,
        # 'groups'     => groups,
        'last_name'   => Array(ldap_entry['sn']).first.to_s,
        'password'    => password,
        'username'    => Array(ldap_entry['uid']).first.to_s,
      }

      # XXX We presume that ldap result strings are UTF-8.  This might be a
      # XXX wrong presumption, and this should be configurable.
      userinfo.each do |key, value|
        value.force_encoding('UTF-8')
      end

      userinfo
    end
  end

  class ExternalWilmaService < ExternalLoginService
    def initialize(wilma_config, service_name, flog)
      super(service_name, flog)

      @linkname = wilma_config['linkname'].to_s
      @url      = wilma_config['url'].to_s
      if @linkname.empty? || @url.empty? then
        raise ExternalLoginError, 'wilma resource is not configured'
      end
    end

    def login(username, password)
      # XXX not done yet
      raise NotImplemented, 'wilma logins do not work yet'

      agent = Mechanize.new

      login_basepage = agent.get(@url)
      raise ExternalLoginUnavailable,
            'could not get base page to wilma login page' \
        unless login_basepage

      login_link = login_basepage.links.find { |l| l.text == @linkname }
      raise ExternalLoginUnavailable, 'could not find link to login page' \
        unless login_link

      login_page = login_link.click
      raise ExternalLoginUnavailable, 'could not find wilma login page' \
        unless login_page

      login_form = login_page.form
      raise ExternalLoginUnavailable,
        'could not find login form in login page' \
          unless login_form
      raise ExternalLoginUnavailable,
        'could not find submit button in login page' \
          unless login_form.buttons && login_form.buttons.first

      login_form.Login    = username
      login_form.Password = password
      login_result_page   = agent.submit(login_form, login_form.buttons.first)

      login_result_form = login_result_page.form
      raise ExternalLoginUnavailable, 'could not find login result form' \
        unless login_result_form
      raise ExternalLoginUnavailable,
        'could not find submit button in login result form' \
          unless login_result_form.buttons && login_result_form.buttons.first

      final_result = agent.submit(login_result_form,
                                  login_result_form.buttons.first)

      raise ExternalLoginUnavailable,
        'could not find title in final login result page' \
          unless final_result && final_result.title

      return nil if final_result.title != 'Session Summary'

      # XXX how to get userinfo?
      userinfo = {}
      return userinfo
    end
  end
end
