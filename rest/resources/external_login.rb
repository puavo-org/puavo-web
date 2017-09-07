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
  class ExternalLogin < PuavoSinatra
    USER_STATUS_NOCHANGE         = 'NOCHANGE'
    USER_STATUS_UPDATED          = 'UPDATED'
    USER_STATUS_UPDATED_BUT_FAIL = 'UPDATED_BUT_FAIL'

    post '/v3/external_login' do
      userinfo = nil
      user_status = nil

      begin
        # lookup related configuration information

        all_external_login_configs = CONFIG['external_login']
        raise ExternalLoginNotConfigured, 'external login not configured' \
          unless all_external_login_configs

        organisation = Organisation.by_domain(request.host)
        raise ExternalLoginError,
          'could not determine organisation from request host' \
            unless organisation && organisation.domain.kind_of?(String)

        organisation_name = organisation.domain.split('.')[0]
        raise ExternalLoginError,
          'could not parse organisation from organisation domain' \
            unless organisation_name

        external_login_config = all_external_login_configs[organisation_name]
        raise ExternalLoginNotConfigured,
          'external_login not configured for this organisation' \
            unless external_login_config

        login_service_name = external_login_config['service']
        raise ExternalLoginError, 'external_login service not set' \
          unless login_service_name

        loginclass_map = {
          'external_ldap'  => LdapLogin,
          'external_wilma' => WilmaLogin,
        }
        external_login_class = loginclass_map[login_service_name]
        raise ExternalLoginError,
          "external login '#{ login_service_name }' is not supported" \
            unless external_login_class

        external_login_params = external_login_config[login_service_name]
        raise ExternalLoginError,
          'external login parameters not configured' \
            unless external_login_params.kind_of?(Hash)

        username = params[:username].to_s
        password = params[:password].to_s
        if username.empty? || password.empty? then
          raise BadCredentials, :user => 'no user credentials provided'
        end

        # setup our own ldap connection

        admin_dn = external_login_config['admin_dn'].to_s
        raise ExternalLoginError, 'admin dn is not set' \
          if admin_dn.empty?
        admin_dn = admin_dn

        admin_password = external_login_config['admin_password'].to_s
        raise ExternalLoginError, 'admin password is not set' \
          if admin_password.empty?

        LdapModel.setup(:credentials => {
                          :dn       => admin_dn,
                          :password => admin_password,
                        },
                        :organisation => organisation)

        # try login to external service

        begin
          message = 'attempting external login to service' \
                      + " '#{ login_service_name }' by user '#{ username }'"
          flog.info('external login attempt', message)
          userinfo = external_login_class.login(username, password,
            external_login_params, flog)
        rescue ExternalLoginWrongPassword => e
          invalidated = maybe_invalidate_user_password(organisation,
	    external_login_config, username, password)
          if invalidated then
            return json({
              'status' => USER_STATUS_UPDATED_BUT_FAIL,
              'msg'    => 'user password invalidated',
            })
          end
          raise e
        rescue ExternalLoginError => e
          raise e
        rescue StandardError => e
          raise ExternalLoginUnavailable, e
        end

        if !userinfo then
          msg = 'could not login to external service' \
                  + " '#{ login_service_name }' by user '#{ username }'"
          raise Unauthorized, :user => msg
        end

        # update user information after successful login

        message = 'successful login to external service' \
                    + " by user '#{ userinfo['username'] }'"
        flog.info('external login successful', message)

        school_dn = params[:school_dn].to_s
        user_status = update_user_info(organisation, external_login_config,
           userinfo, school_dn)

      rescue ExternalLoginNotConfigured => e
        flog.info('external login not configured',
                  "external login is not configured: #{ e.message }")
        return json({ 'status' => 'NOTCONFIGURED', 'msg' => e.message })
      rescue ExternalLoginUnavailable => e
        flog.warn('external login unavailable',
                  "external login is unavailable: #{ e.message }")
        return json({ 'status' => 'UNAVAILABLE', 'msg' => e.message })
      rescue ExternalLoginError => e
        flog.error('external login error',
                   "external login error: #{ e.message }")
        raise InternalError, e
      rescue StandardError => e
        raise InternalError, e
      end

      return json({ 'status' => user_status })
    end

    def maybe_invalidate_user_password(organisation, el_config, username,
      password)
        user = User.by_username(username)
        if !user then
          flog.info(nil, "user '#{ username }' not found in Puavo, no password to invalidate")
          return
        end

        # change user password to something random and just throw it away
        new_password = SecureRandom.hex(128)

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
          flog.info(nil, msg)
          return true
        else
          flog.warn(nil, "error occurred when running ldappasswd: (#{ res[:exit_status] }) #{ res[:stderr] }")
        end

        return false
    end

    def update_user_info(organisation, el_config, userinfo, school_dn)
      if userinfo['school_dns'].nil? then
        if !school_dn.empty? then
          userinfo['school_dns'] = [ school_dn ]
        else
          default_school_dns = el_config['default_school_dns']
          if !default_school_dns.kind_of?(Array) then
            raise ExternalLoginError,
              "school dn is not known for '#{ userinfo['username'] }'" \
                + ' and default school is not set'
          end
          userinfo['school_dns'] = default_school_dns
        end
      end

      if userinfo['roles'].nil? then
        default_roles = el_config['default_roles']
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
          flog.info('new external login user',
                    "created a new user '#{ userinfo['username'] }'")
          return USER_STATUS_UPDATED
        elsif user.check_if_changed_attributes(userinfo) then
          user.update!(userinfo)
          user.save!
          flog.info('updated external login user',
                    "updated user information for '#{ userinfo['username'] }'")
          return USER_STATUS_UPDATED
        else
          flog.info('no change for external login user',
                    'no change in user information for' \
                      + " '#{ userinfo['username'] }'")
          return USER_STATUS_NOCHANGE
        end
      rescue ValidationError => e
        raise ExternalLoginError,
              "error saving user because of validation errors: #{ e.message }"
      end
    end
  end

  class LdapLogin
    def self.login(username, password, ldap_config, flog)
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

      ldap = Net::LDAP.new :base => base.to_s,
                           :host => server.to_s,
                           :port => (Integer(ldap_config['port']) rescue 636),
                           :auth => {
                             :method   => :simple,
                             :username => bind_dn.to_s,
                             :password => bind_password.to_s,
                           },
                           :encryption => :simple_tls   # XXX not sufficient!

      user_filter = Net::LDAP::Filter.eq('cn', username)

      # first check if user exists
      ldap_entries = ldap.search(:filter => user_filter)
      if ldap_entries.length == 0 then
        flog.info('user does not exist in external ldap',
                  'user does not exist in external ldap')
        return nil
      end
      raise ExternalLoginUnavailable, 'ldap search returned too many entries' \
        unless ldap_entries.length == 1

      # then authenticate as user
      ldap_entries = ldap.bind_as(:filter   => user_filter,
                                  :password => password)
      if !ldap_entries then
        message = "authentication to ldap failed: #{ ldap.get_operation_result.message }"
        if ldap.get_operation_result.code == Net::LDAP::ResultCodeInvalidCredentials then
          message += ' (user password was wrong)'
          raise ExternalLoginWrongPassword, message
        end
         
        raise ExternalLoginUnavailable, message
      end
      raise ExternalLoginUnavailable, 'ldap bind returned too many entries' \
        unless ldap_entries.length == 1

      flog.info('authentication to ldap succeeded',
                'authentication to ldap succeeded')
      ldap_entry = ldap_entries.first

      lookup_groups_filter \
        = Net::LDAP::Filter.eq('objectClass', 'posixGroup') \
            .&(Net::LDAP::Filter.eq('memberUid', username))
      groups_result = ldap.search(:filter => lookup_groups_filter)
      groups = Hash[
        groups_result.map do |g|
          [ Array(g['cn']).first, Array(g['displayname']).first ]
        end
      ]

      # XXX check that these are not nonsense?
      userinfo = {
        'external_id' => Array(ldap_entry['dn']).first,
        'first_name'  => Array(ldap_entry['givenname']).first,
        # 'groups'     => groups,
        'last_name'   => Array(ldap_entry['sn']).first,
        'password'    => password,
        'username'    => Array(ldap_entry['uid']).first,
      }

      # XXX We presume that ldap result strings are UTF-8.  This might be a
      # XXX wrong presumption, and this should be configurable.
      userinfo.each do |key, value|
        value.force_encoding('UTF-8') if value.respond_to?(:force_encoding)
      end

      userinfo
    end
  end

  class WilmaLogin
    def self.login(username, password, wilma_config, flog)
      linkname = wilma_config['linkname'].to_s
      url      = wilma_config['url'].to_s
      if linkname.empty? || url.empty? then
        raise ExternalLoginError, 'wilma resource is not configured'
      end

      agent = Mechanize.new

      login_basepage = agent.get(url)
      raise ExternalLoginUnavailable,
            'could not get base page to wilma login page' \
        unless login_basepage

      login_link = login_basepage.links.find { |l| l.text == linkname }
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

      raise NotImplemented, 'wilma logins do not work yet'
      userinfo = {}
      return userinfo
    end
  end
end
