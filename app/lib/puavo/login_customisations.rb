# Applies per-customer customisations

module Puavo
  module LoginCustomisations
    def customise_login_screen()
      begin
        org_key = organisation_key_from_host

        logger.info("customise_login_screen(): organisation key: \"#{org_key}\"")

        customisations = Puavo::Organisation
          .find(org_key)
          .value_by_key('login_screen')

        customisations = {} unless customisations.class == Hash
      rescue StandardError => e
        customisations = {}
      end

      unless customisations.empty?
        logger.info('customise_login_screen(): this organisation has login screen customisations enabled')
      end

      extra_content = {}

      if customisations.include?('css')
        extra_content['css'] = customisations['css']
      end

      if customisations.include?('upper_logos')
        extra_content['upper_logos'] = customisations['upper_logos']
      end

      if customisations.include?('header_text')
        extra_content['header_text'] = customisations['header_text']
      end

      if customisations.include?('service_title_override')
        extra_content['service_title_override'] = customisations['service_title_override']
      end

      if customisations.include?('lower_logos')
        extra_content['lower_logos'] = customisations['lower_logos']
      end

      extra_content
    end
  end
end
