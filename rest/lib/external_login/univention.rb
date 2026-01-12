require_relative './errors'
require_relative './service'

module PuavoRest
  class ExternalUniventionService < ExternalLoginService
    def initialize(external_login, univention_config, service_name, rlog)
      super(external_login, service_name, rlog)

      # this is a reference to configuration, do not modify!
      @univention_config = univention_config

      raise ExternalLoginConfigError, 'univention server not configured' \
        unless @univention_config['server']
    end
  end
end
