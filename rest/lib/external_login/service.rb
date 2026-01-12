module PuavoRest
  class ExternalLoginService
    attr_reader :service_name

    def initialize(external_login, service_name, rlog)
      @external_login = external_login
      @rlog           = rlog
      @service_name   = service_name
    end
  end
end
