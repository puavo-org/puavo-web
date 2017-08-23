require 'mechanize'

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

        external_login_class  = nil
        external_login_params = nil
        case login_service_name
          when 'wilma'
            external_login_class  = WilmaLogin
            external_login_params = org_extlogin_config['wilma']
          else
            raise InternalError,
                  "External login '#{ login_service_name }' is not supported"
        end

        raise ExternalLoginUnavailable,
          'External login parameters not configured' \
            unless external_login_params.kind_of?(Hash)

        username = params[:username]
        password = params[:password]
        if username.to_s.empty? || password.to_s.empty? then
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
