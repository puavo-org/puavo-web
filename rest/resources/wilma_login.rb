require 'mechanize'

class WilmaLoginUnavailable < StandardError; end

module PuavoRest
  class WilmaLogin < PuavoSinatra
    def authenticate(username, password, wilma_login_url, wilma_login_linkname)
      agent = Mechanize.new

      login_basepage = agent.get(wilma_login_url)
      raise WilmaLoginUnavailable,
            'Could not get base page to wilma login page' \
        unless login_basepage

      login_link = login_basepage.links.find do |l|
        l.text == wilma_login_linkname
      end
      raise WilmaLoginUnavailable, 'Could not find link to login page' \
        unless login_link

      login_page = login_link.click
      raise WilmaLoginUnavailable, 'Could not find wilma login page' \
        unless login_page

      login_form = login_page.form
      raise WilmaLoginUnavailable, 'Could not find login form in login page' \
        unless login_form
      raise WilmaLoginUnavailable,
        'Could not find submit button in login page' \
          unless login_form.buttons && login_form.buttons.first

      login_form.Login    = username
      login_form.Password = password
      login_result_page = agent.submit(login_form, login_form.buttons.first)

      login_result_form = login_result_page.form
      raise WilmaLoginUnavailable, 'Could not find login result form' \
        unless login_result_form
      raise WilmaLoginUnavailable,
        'Could not find submit button in login result form' \
          unless login_result_form.buttons && login_result_form.buttons.first

      final_result = agent.submit(login_result_form,
                                  login_result_form.buttons.first)

      raise WilmaLoginUnavailable,
        'Could not find title in final login result page' \
          unless final_result && final_result.title

      return false if final_result.title != 'Session Summary'

      # XXX should really return user data to be parsed
      return true
    end

    post '/v3/wilma/login' do
      wilma_config = CONFIG['wilma']

      wilma_login_linkname = wilma_config['linkname'].to_s
      wilma_login_url      = wilma_config['url'].to_s
      if wilma_config.nil? \
           || wilma_login_linkname.empty? \
           || wilma_login_url.empty? then
        # XXX Is this the proper way to log things?
        warn('Wilma resource is not configured')
        raise Sinatra::NotFound, 'Wilma resource is not configured'
      end

      username = params[:username]
      password = params[:password]
      if username.to_s.empty? || password.to_s.empty? then
        warn('No user credentials provided')
        return 401        # XXX Unauthorized
      end

      wilma_response = nil
      begin
        wilma_response = authenticate(username, password, wilma_login_url,
          wilma_login_linkname)
      rescue WilmaLoginUnavailable => e
        # XXX Is this the proper way to log things?
        warn("Wilma login is unavailable: #{ e.message }")
        raise Sinatra::NotFound, e.message
      rescue StandardError => e
        raise InternalError, e.message
      end

      # XXX
      return 200 if wilma_response

      # XXX Unauthorized
      return 401
    end
  end
end
