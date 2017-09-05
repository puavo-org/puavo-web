require 'mechanize'
require 'net/ldap'

class ExternalLoginError         < StandardError; end
class ExternalLoginNotConfigured < ExternalLoginError; end
class ExternalLoginUnavailable   < ExternalLoginError; end

module PuavoRest
  class ExternalLogin < PuavoSinatra
    USER_STATUS_NOCHANGE = 'NOCHANGE'
    USER_STATUS_UPDATED  = 'UPDATED'

    post '/v3/external_login' do
      userinfo = nil
      user_status = nil

      begin
        all_external_login_configs = CONFIG['external_login']
        raise ExternalLoginNotConfigured, 'external login not configured' \
          unless all_external_login_configs

        organisation = Organisation.by_domain(request.host)
        raise ExternalLoginError,
          'Could not determine organisation from request host' \
            unless organisation && organisation.domain.kind_of?(String)

        organisation_name = organisation.domain.split('.')[0]
        raise ExternalLoginError,
          'Could not parse organisation from organisation domain' \
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
          "External login '#{ login_service_name }' is not supported" \
            unless external_login_class

        external_login_params = external_login_config[login_service_name]
        raise ExternalLoginError,
          'External login parameters not configured' \
            unless external_login_params.kind_of?(Hash)

        username = params[:username].to_s
        password = params[:password].to_s
        if username.empty? || password.empty? then
          warn('No user credentials provided')
          return 401        # XXX Unauthorized
        end

        begin
          userinfo = external_login_class.login(username, password,
            external_login_params)
        rescue ExternalLoginError => e
          raise e
        rescue StandardError => e
          raise ExternalLoginUnavailable, e
        end

        return 401 unless userinfo      # XXX Unauthorized

        school_dn = params[:school_dn].to_s
        user_status = update_user_info(organisation, external_login_config,
           userinfo, school_dn)

      rescue ExternalLoginNotConfigured => e
        # XXX Is this the proper way to log things?
        warn("External login is not configured: #{ e.message }")
        return json({ 'status' => 'NOTCONFIGURED', 'msg' => e.message })
      rescue ExternalLoginUnavailable => e
        # XXX Is this the proper way to log things?
        warn("External login is unavailable: #{ e.message }")
        return json({ 'status' => 'UNAVAILABLE', 'msg' => e.message })
      rescue ExternalLoginError => e
        # XXX Is this the proper way to log things?  how to suppress stacktrace?
        warn("External login error: #{ e.message }")
        raise InternalError, e
      rescue StandardError => e
        raise InternalError, e
      end

      return json({ 'status' => user_status })
    end

    def update_user_info(organisation, el_config, userinfo, school_dn)
      admin_dn = el_config['admin_dn'].to_s
      raise ExternalLoginError, 'admin dn is not set' \
        if admin_dn.empty?

      admin_password = el_config['admin_password'].to_s
      raise ExternalLoginError, 'admin password is not set' \
        if admin_password.empty?

      LdapModel.setup(:credentials => {
                        :dn       => admin_dn,
                        :password => admin_password,
                      },
                      :organisation => organisation)

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
          return USER_STATUS_UPDATED
        elsif user.check_if_changed_attributes(userinfo) then
          user.update!(userinfo)
          user.save!
          return USER_STATUS_UPDATED
        else
          return USER_STATUS_NOCHANGE
        end
      rescue ValidationError => e
        raise ExternalLoginError,
              "Error saving user because of validation errors: #{ e.message }"
      end
    end
  end

  class LdapLogin
    def self.login(username, password, ldap_config)
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

      bind_filter = Net::LDAP::Filter.eq('cn', username)
      ldap_entries = ldap.bind_as(:filter   => bind_filter,
                                  :password => password)
      return nil unless ldap_entries

      raise ExternalLoginUnavailable, 'ldap bind returned too many entries' \
        unless ldap_entries.length == 1

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
    def self.login(username, password, wilma_config)
      linkname = wilma_config['linkname'].to_s
      url      = wilma_config['url'].to_s
      if linkname.empty? || url.empty? then
        raise ExternalLoginError, 'Wilma resource is not configured'
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

      return false if final_result.title != 'Session Summary'

      # XXX should really return user data to be parsed
      return true
    end
  end
end
