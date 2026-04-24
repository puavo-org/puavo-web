module PuavoRest
  class ExternalLoginService
    attr_reader :service_name

    def initialize(external_login, service_name, rlog)
      @external_login = external_login
      @rlog           = rlog
      @service_name   = service_name
    end

    def has_realtime?
      false
    end

    def update_from_external(username, external_user_entry)
      set_userinfo_from_external(username, external_user_entry)
      userinfo = get_userinfo_for_puavo(username)
      user_status = @external_login.update_user_info(userinfo, nil, {})

      if user_status != PuavoRest::ExternalLoginStatus::NOCHANGE \
        && user_status != PuavoRest::ExternalLoginStatus::UPDATED then
          raise 'user information update to Puavo failed with status' \
                  + " #{ user_status }"
      end
    end
  end
end
