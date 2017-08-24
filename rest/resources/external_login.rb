require 'mechanize'
require 'net/ldap'

class ExternalLoginUnavailable < StandardError; end

module PuavoRest
  class ExternalLogin < PuavoSinatra
    post '/v3/external_login' do
      response = nil

      begin
        external_login_config = CONFIG['external_login']
        raise ExternalLoginUnavailable, 'external login not configured' \
          unless external_login_config

        # XXX organisation should not be hardcoded
        org_extlogin_config = external_login_config['kehitys']
        raise ExternalLoginUnavailable,
          'external_login not for organisation not configured' \
            unless org_extlogin_config

        login_service_name = org_extlogin_config['service']
        raise ExternalLoginUnavailable, 'external_login service not set' \
          unless login_service_name

        loginclass_map = {
          'ldap'  => LdapLogin,
          'wilma' => WilmaLogin,
        }
        external_login_class = loginclass_map[login_service_name]
        raise InternalError,
          "External login '#{ login_service_name }' is not supported" \
            unless external_login_class

        external_login_params = org_extlogin_config[login_service_name]
        raise ExternalLoginUnavailable,
          'External login parameters not configured' \
            unless external_login_params.kind_of?(Hash)

        username = params[:username].to_s
        password = params[:password].to_s
        if username.empty? || password.empty? then
          warn('No user credentials provided')
          return 401        # XXX Unauthorized
        end

        response = external_login_class.login(username, password,
          external_login_params)
      rescue ExternalLoginUnavailable => e
        # XXX Is this the proper way to log things?
        warn("External login is unavailable: #{ e.message }")
        raise Sinatra::NotFound, e.message
      rescue StandardError => e
        raise InternalError, e.message
      end

      # XXX
      return 200 if response

      # XXX Unauthorized
      return 401
    end
  end

  class LdapLogin
    def self.login(username, password, ldap_config)
      base = ldap_config['base']
      raise ExternalLoginUnavailable, 'ldap base not configured' \
        unless base

      bind_dn = ldap_config['bind_dn']
      raise ExternalLoginUnavailable, 'ldap bind dn not configured' \
        unless bind_dn

      bind_password = ldap_config['bind_password']
      raise ExternalLoginUnavailable, 'ldap bind password not configured' \
        unless bind_password

      server = ldap_config['server']
      raise ExternalLoginUnavailable, 'ldap server not configured' \
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

      return ldap.bind_as(:base     => base,
                          :filter   => "(cn=#{username})",
                          :password => password)
    end
  end

  class WilmaLogin
    def self.login(username, password, wilma_config)
      linkname = wilma_config['linkname'].to_s
      url      = wilma_config['url'].to_s
      if linkname.empty? || url.empty? then
        # XXX Is this the proper way to log things?
        warn('Wilma resource is not configured')
        raise ExternalLoginUnavailable, 'Wilma resource is not configured'
      end

      agent = Mechanize.new

      login_basepage = agent.get(url)
      raise ExternalLoginUnavailable,
            'Could not get base page to wilma login page' \
        unless login_basepage

      login_link = login_basepage.links.find { |l| l.text == linkname }
      raise ExternalLoginUnavailable, 'Could not find link to login page' \
        unless login_link

      login_page = login_link.click
      raise ExternalLoginUnavailable, 'Could not find wilma login page' \
        unless login_page

      login_form = login_page.form
      raise ExternalLoginUnavailable,
        'Could not find login form in login page' \
          unless login_form
      raise ExternalLoginUnavailable,
        'Could not find submit button in login page' \
          unless login_form.buttons && login_form.buttons.first

      login_form.Login    = username
      login_form.Password = password
      login_result_page   = agent.submit(login_form, login_form.buttons.first)

      login_result_form = login_result_page.form
      raise ExternalLoginUnavailable, 'Could not find login result form' \
        unless login_result_form
      raise ExternalLoginUnavailable,
        'Could not find submit button in login result form' \
          unless login_result_form.buttons && login_result_form.buttons.first

      final_result = agent.submit(login_result_form,
                                  login_result_form.buttons.first)

      raise ExternalLoginUnavailable,
        'Could not find title in final login result page' \
          unless final_result && final_result.title

      return false if final_result.title != 'Session Summary'

      # XXX should really return user data to be parsed
      return true
    end
  end
end
