require 'net/ldap'

require_relative './errors'
require_relative './ldap'
require_relative './univention'

module PuavoRest
  class ExternalLoginStatus
    BADUSERCREDS     = 'BADUSERCREDS'
    CONFIGERROR      = 'CONFIGERROR'
    NOCHANGE         = 'NOCHANGE'
    NOTCONFIGURED    = 'NOTCONFIGURED'
    PUAVOUSERMISSING = 'PUAVOUSERMISSING'
    UNAVAILABLE      = 'UNAVAILABLE'
    UPDATED          = 'UPDATED'
    UPDATED_BUT_FAIL = 'UPDATED_BUT_FAIL'
    UPDATEERROR      = 'UPDATEERROR'
    USERMISSING      = 'USERMISSING'
  end

  class ExternalLogin
    attr_reader :config, :manage_puavousers, :puavo_extlogin_id_field

    def initialize(organisation=nil)
      # Parse config with relevant information for doing external logins.

      @rlog = $rest_log

      all_external_login_configs = CONFIG['external_login']
      unless all_external_login_configs then
        raise ExternalLoginNotConfigured, 'external login not configured'
      end

      @organisation = organisation || LdapModel.organisation
      raise ExternalLoginError, 'could not determine organisation' \
        unless @organisation && @organisation.domain.kind_of?(String)

      organisation_name = @organisation.domain.split('.')[0]
      raise ExternalLoginError,
        'could not parse organisation from organisation domain' \
          unless organisation_name

      @config = all_external_login_configs[organisation_name]
      unless @config then
        raise ExternalLoginNotConfigured,
          'external_login not configured for this organisation'
      end

      @login_service_name = @config['service']
      raise ExternalLoginConfigError, 'external_login service not set' \
        unless @login_service_name

      @manage_puavousers = @config['manage_puavousers']
      raise ExternalLoginConfigError,
            'external_login manage_puavousers not set' \
        if @manage_puavousers.nil?

      @managed_roles = @config['managed_roles']
      raise ExternalLoginConfigError,
            'external_login managed roles not set' \
        unless @managed_roles.kind_of?(Array)

      @puavo_extlogin_id_field = @config['puavo_extlogin_id_field']
      raise ExternalLoginConfigError,
            'puavo_extlogin_id_field is missing or has an unsupported value' \
        unless %w(external_id id learner_id).include?(@puavo_extlogin_id_field)

      # More login classes could be added here in the future,
      # for other types of external logins.
      loginclass_map = {
        'external_ldap' => ExternalLdapService,
        'univention'    => ExternalUniventionService,
      }
      @external_login_class = loginclass_map[@login_service_name]
      raise ExternalLoginError,
        "external login '#{ @login_service_name }' is not supported" \
          unless @external_login_class

      @puavo_extschool_id_field = @config['puavo_extschool_id_field']
      raise ExternalLoginConfigError,
            'puavo_extlogin_id_field is missing or has an unsupported value' \
        if @external_login_class == ExternalUniventionService \
             && @puavo_extlogin_id_field != 'external_id'

      @external_login_params = @config[@login_service_name]
      raise ExternalLoginError,
        'external login parameters not configured' \
          unless @external_login_params.kind_of?(Hash)

      @admin_dn = @config['admin_dn'].to_s
      raise ExternalLoginError, 'admin dn is not set' \
        if @admin_dn.empty?

      @admin_password = @config['admin_password'].to_s
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

    def extlogin_id(user)
      user.send(@puavo_extlogin_id_field)
    end

    def extschool_id(school)
      school.send(@puavo_extschool_id_field)
    end

    def check_user_is_manageable(username)
      user = User.by_username(username)

      # If we do not have a user with this username, that username slot is
      # available for external logins.
      if !user then
        if !@manage_puavousers then
          raise ExternalLoginPuavoUserMissing,
                "no username '#{ username }' in puavo and user management" \
                  + ' is disabled'
        end
        @rlog.info("username '#{ username }' is available for external logins")
        return true
      end

      if extlogin_id(user) then
        # User is managed by external logins, if extlogin_id is set to a
        # non-empty value.
        @rlog.info("username '#{ username }' has non-empty extlogin id" \
                     + " (#{ @puavo_extlogin_id_field }), ok")
        return true
      end

      message = "user '#{ username }' exists but does not have" \
                  + " an extlogin id (#{ @puavo_extlogin_id_field }) set," \
                  + " refusing to manage"
      raise ExternalLoginNotConfigured, message
    end

    def new_external_service_handler()
      @external_login_class.new(self,
                                @external_login_params,
                                @login_service_name,
                                @rlog)
    end

    def set_puavo_password(username, extlogin_id, new_password)
      begin
        user = puavo_user_by_extlogin_id(extlogin_id)
        if !user then
          msg = "user with extlogin id '#{ extlogin_id }' (#{ username }?)" \
                  + ' not found in Puavo, can not set password'
          @rlog.info(msg)
          return ExternalLoginStatus::NOCHANGE
        end

        begin
          # First test if user password is already valid.  No need to change
          # it in case new one is the same as old.  The point of this is
          # to not modify the user ldap entry in case it is not necessary.
          LdapModel.dn_bind(user.dn, new_password)
          return ExternalLoginStatus::NOCHANGE
        rescue StandardError => e
          @rlog.info("changing puavo password for '#{ username }'")
        end

        res = Puavo.change_passwd(:no_upstream,
                                  CONFIG['ldap'],
                                  @admin_dn,
                                  nil,
                                  @admin_password,
                                  user.username,
                                  new_password,
                                  '???')    # we have no request ID here
        if res[:exit_status] == Net::LDAP::ResultCodeSuccess then
          return ExternalLoginStatus::UPDATED
        end

        raise "unexpected exit code (#{ res[:exit_status] }):" \
                " with admin dn/password: #{ res[:stderr] }"

      rescue StandardError => e
        raise ExternalLoginError,
              "error in set_puavo_password(): #{ e.message }"
      end
    end

    def maybe_invalidate_puavo_password(username, extlogin_id, old_password)
      begin
        user = puavo_user_by_extlogin_id(extlogin_id)
        if !user then
          msg = "user with extlogin id '#{ extlogin_id }' (#{ username }?)" \
                  + ' not found in Puavo, can not try to invalidate password'
          @rlog.info(msg)
          return ExternalLoginStatus::NOCHANGE
        end

        new_password = SecureRandom.hex(128)

        # if old_password is not valid, nothing is done and that is good
        res = Puavo.change_passwd(:no_upstream,
                                  CONFIG['ldap'],
                                  user.dn,
                                  nil,
                                  old_password,
                                  user.username,
                                  new_password,
                                  '???')  # we have no request ID here
        case res[:exit_status]
        when Net::LDAP::ResultCodeInvalidCredentials
          return ExternalLoginStatus::NOCHANGE
        when Net::LDAP::ResultCodeSuccess
          return ExternalLoginStatus::UPDATED
        else
          raise "unexpected exit code (#{ res[:exit_status] }): " \
                  + res[:stderr]
        end
      rescue StandardError => e
        raise ExternalLoginError,
              "error in maybe_invalidate_puavo_password(): #{ e.message }"
      end

      return ExternalLoginStatus::NOCHANGE
    end

    def puavo_user_by_extlogin_id(extlogin_id)
      users = User.by_attr(@puavo_extlogin_id_field, extlogin_id,
                           :multiple => true)
      if users.count > 1 then
        raise('multiple users with the same' \
                + " #{ @puavo_extlogin_id_field }: #{ extlogin_id }")
      end
      users.first
    end

    def manage_groups_for_user(user, external_groups_by_type)
      external_login_status = ExternalLoginStatus::NOCHANGE

      return external_login_status unless @manage_puavousers

      user.schools.each do |school|
        external_groups_by_type.each do |ext_group_type, external_groups|

          if [ 'teaching group', 'year class' ].include?(ext_group_type) then
            if external_groups.count > 1 then
              @rlog.warn("trying to add '#{ user.username }' to"             \
                           + " #{ external_groups.count } groups of type"    \
                           + " '#{ ext_group_type }', which is not allowed," \
                           + ' not proceeding, check your external_login'    \
                           + ' configuration.')
              next
            end
          end

          puavo_group_list \
            = Group.by_attr(:type, ext_group_type, :multiple => true) \
                   .select { |pg| pg.external_id }

          external_groups.each do |ext_group_name, ext_group_displayname|
            @rlog.info("making sure user '#{ user.username }' belongs to" \
                         + " a puavo group '#{ ext_group_name }'" \
                         + " / #{ ext_group_displayname }")

            puavo_group = nil
            puavo_group_list.each do |candidate_puavo_group|
              next unless candidate_puavo_group.abbreviation == ext_group_name
              puavo_group = candidate_puavo_group
              if puavo_group.name != ext_group_displayname then
                @rlog.info('updating group name'                \
                             + " for '#{ puavo_group.abbreviation }'" \
                             + " from '#{ puavo_group.name }'"        \
                             + " to '#{ ext_group_displayname }'")

                puavo_group.name = ext_group_displayname
                puavo_group.save!
                external_login_status = ExternalLoginStatus::UPDATED
              end
            end

            unless puavo_group then
              @rlog.info('creating a new puavo group of type'           \
                           + " '#{ ext_group_type }' to school"         \
                           + " '#{ school.abbreviation }'"              \
                           + " with abbreviation '#{ ext_group_name }'" \
                           + " and name '#{ ext_group_displayname }'")

              puavo_group \
                = PuavoRest::Group.new(:abbreviation => ext_group_name,
                                       :external_id  => ext_group_name,
                                       :name         => ext_group_displayname,
                                       :school_dn    => school.dn,
                                       :type         => ext_group_type)
              puavo_group.save!
              external_login_status = ExternalLoginStatus::UPDATED
            end

            unless puavo_group.has?(user) then
              @rlog.info("adding user '#{ user.username }'" \
                           + " to group '#{ ext_group_displayname }'")
              puavo_group.add_member(user)
              puavo_group.save!
              external_login_status = ExternalLoginStatus::UPDATED
            end
          end

          puavo_group_list.each do |puavo_group|
            unless external_groups.has_key?(puavo_group.abbreviation) then
              if puavo_group.has?(user) then
                @rlog.info("removing user '#{ user.username }' from group" \
                             + " '#{ puavo_group.abbreviation }'")
                puavo_group.remove_member(user)
                puavo_group.save!
                external_login_status = ExternalLoginStatus::UPDATED
              end
            end
            # if puavo_group.member_dns.empty? then
            #   # We could maybe remove a puavo group here, BUT a group
            #   # is associated with a gid, which might be associated with
            #   # files, so do not do it.  Perhaps mark it for removal and
            #   # remove later?
            # end
          end
        end
      end

      return external_login_status
    end

    def update_user_info(userinfo, password, params)
      external_groups_by_type = userinfo.delete('external_groups')

      user = puavo_user_by_extlogin_id(userinfo[@puavo_extlogin_id_field])
      user, user_update_status = update_user_attributes(user, userinfo, params)

      if password then
        pw_update_status \
          = set_puavo_password(userinfo['username'],
                               userinfo[@puavo_extlogin_id_field],
                               password)
        if pw_update_status == ExternalLoginStatus::UPDATED \
          && userinfo['password_last_set'] then
            # must update the password_last_set to match what external ldap has
            # because password change operation changes the value in Puavo
            begin
              user.password_last_set = userinfo['password_last_set']
              user.save!
            rescue StandardError => e
              @rlog.info(
                'error in updating password_last_set in Puavo' \
                  + " for user #{ userinfo['username'] }: #{ e.message }")
            end
        end
      else
        pw_update_status = ExternalLoginStatus::NOCHANGE
      end

      mg_update_status = manage_groups_for_user(user, external_groups_by_type)

      return ExternalLoginStatus::UPDATED \
        if (user_update_status    == ExternalLoginStatus::UPDATED \
              || pw_update_status == ExternalLoginStatus::UPDATED \
              || mg_update_status == ExternalLoginStatus::UPDATED)

      return ExternalLoginStatus::NOCHANGE
    end

    def update_user_attributes(user, userinfo, params)
      user_update_status = ExternalLoginStatus::NOCHANGE

      return user_update_status unless @manage_puavousers

      if userinfo['school_dns'].empty? then
        school_dn_param = params[:school_dn].to_s
        if !school_dn_param.empty? then
          userinfo['school_dns'] = [ school_dn_param ]
        end
      end
      if userinfo['school_dns'].empty? then
        raise ExternalLoginError,
              "could not determine user school for #{ userinfo['username'] }"
      end

      if userinfo['roles'].empty? then
        role_param = params[:role].to_s
        if !role_param.empty? then
          userinfo['roles'] = [ role_param ]
        end
      end
      if userinfo['roles'].empty? then
        raise ExternalLoginError,
              "could not determine user role for #{ userinfo['username'] }"
      end

      begin
        userinfo = adjust_userinfo(user, userinfo)

        if !user then
          if userinfo['id'] then
            # We should not be creating users with a specific puavoId,
            # this should never happen and something is configured in an
            # unsupported way.
            raise ExternalLoginError,
                  'puavoId set for new user in external_login'
          end

          # All is good, we are missing a user and should create one.
          user = User.new(userinfo)
          user.save!
          @rlog.info("created a new user '#{ userinfo['username'] }'")
          user_update_status = ExternalLoginStatus::UPDATED

        elsif user.check_if_changed_attributes(userinfo) then
          userinfo.delete('id')
          user.update!(userinfo)
          user.locked = false
          user.removal_request_time = nil
          user.save!
          @rlog.info("updated user info for '#{ userinfo['username'] }'")
          user_update_status = ExternalLoginStatus::UPDATED

        else
          if user.locked || user.removal_request_time then
            user.locked = false
            user.removal_request_time = nil
            user.save!
          end

          @rlog.info('no change in user information for' \
                       + " '#{ userinfo['username'] }'")
          user_update_status = ExternalLoginStatus::NOCHANGE
        end
      rescue ValidationError => e
        raise ExternalLoginError,
              "error saving user because of validation errors: #{ e.message }"
      end

      return user, user_update_status
    end

    def adjust_userinfo(user, userinfo)
      return userinfo unless user

      # We want to get roles listed in @managed_roles from the external
      # login information, but other roles we want to maintain ourselves
      # (often, for example, the "admin"-role).
      new_user_roles = (user.roles - @managed_roles) + userinfo['roles']
      userinfo['roles'] = new_user_roles.sort.uniq

      userinfo
   end

    def self.auth(username, password, organisation, params)
      rlog = $rest_log

      userinfo = nil
      user_status = nil

      begin
        external_login = ExternalLogin.new(organisation)
        external_login.setup_puavo_connection()
        external_login.check_user_is_manageable(username)

        login_service = external_login.new_external_service_handler()

        remove_user_if_found = false
        wrong_credentials    = false

        begin
          message = 'attempting external login to service' \
                      + " '#{ login_service.service_name }' by user" \
                      + " '#{ username }'"
          rlog.info(message)
          userinfo = login_service.login(username, password)
        rescue ExternalLoginUserMissing => e
          rlog.info("user does not exist in external LDAP: #{e.message}")
          remove_user_if_found = true
          userinfo = nil
        rescue ExternalLoginWrongCredentials => e
          rlog.info("user provided wrong username/password: #{e.message}")
          wrong_credentials = true
          userinfo = nil
        rescue ExternalLoginError => e
          raise e
        rescue StandardError => e
          # Unexpected errors when authenticating to external service means
          # it was not available.
          raise ExternalLoginUnavailable, e
        end

        if external_login.manage_puavousers && remove_user_if_found then
          # No user information in external login service, so remove user
          # from Puavo if there is one.  But instead of removing
          # we simply generate a new, random password, and mark the account
          # for removal, in case it was not marked before.  Not removing
          # right away should allow use to catch some possible accidents
          # in case the external ldap somehow "loses" some users, and we want
          # keep user uids stable on our side.
          user_to_remove = User.by_username(username)
          if user_to_remove && user_to_remove.mark_for_removal! then
            rlog.info("puavo user '#{ user_to_remove.username }' is marked" \
                        + ' for removal')
          end
        end

        if wrong_credentials then
          # Try looking up user from Puavo, but in case a user does not exist
          # yet (there is a mismatch between username in Puavo and username
          # in external service), look up the user extlogin_id from external
          # service so we can try to invalidate the password matching
          # the right Puavo username.
          user = User.by_username(username)
          extlogin_id = (user && external_login.extlogin_id(user)) \
                          || login_service.lookup_extlogin_id(username)

          pw_update_status \
            = external_login.maybe_invalidate_puavo_password(username,
                                                             extlogin_id,
                                                             password)
          if pw_update_status == ExternalLoginStatus::UPDATED then
            msg = 'user password invalidated'
            rlog.info("user password invalidated for #{ username }")
            LdapModel.disconnect()
            return ExternalLogin.status_updated_but_fail(msg)
          end
        end

        if !userinfo then
          msg = 'could not login to external service' \
                  + " '#{ login_service.service_name }' by user" \
                  + " '#{ username }', username or password was wrong"
          rlog.info(msg)
          raise ExternalLoginWrongCredentials, msg
        end

        # update user information after successful login

        message = 'successful login to external service' \
                    + " by user '#{ userinfo['username'] }'"
        rlog.info(message)

        begin
          extlogin_status = external_login.update_user_info(userinfo,
                                                            password,
                                                            params)
          user_status \
            = case extlogin_status
                when ExternalLoginStatus::NOCHANGE
                  ExternalLogin.status_nochange()
                when ExternalLoginStatus::UPDATED
                  ExternalLogin.status_updated()
                else
                  raise 'unexpected update status from update_user_info()'
              end
        rescue StandardError => e
          rlog.warn("error updating user information: #{ e.message }")
          LdapModel.disconnect()
          return ExternalLogin.status_updateerror(e.message)
        end

      rescue BadCredentials => e
        # this means there was a problem with Puavo credentials (admin dn)
        user_status = ExternalLogin.status_configerror(e.message)
      rescue ExternalLoginConfigError => e
        rlog.info("external login configuration error: #{ e.message }")
        user_status = ExternalLogin.status_configerror(e.message)
      rescue ExternalLoginNotConfigured => e
        rlog.info("external login is not configured: #{ e.message }")
        user_status = ExternalLogin.status_notconfigured(e.message)
      rescue ExternalLoginPuavoUserMissing => e
        rlog.warn("external login puavo user is missing: #{ e.message }")
        user_status = ExternalLogin.status_puavousermissing(e.message)
      rescue ExternalLoginUnavailable => e
        rlog.warn("external login is unavailable: #{ e.message }")
        user_status = ExternalLogin.status_unavailable(e.message)
      rescue ExternalLoginWrongCredentials => e
        user_status = ExternalLogin.status_badusercreds(e.message)
      rescue StandardError => e
        raise InternalError, e
      end

      LdapModel.disconnect()

      return user_status
    end

    def self.status(status_string, msg)
      { 'msg' => msg, 'status' => status_string }
    end

    def self.status_badusercreds(msg=nil)
      status(ExternalLoginStatus::BADUSERCREDS,
             (msg || 'auth FAILED, username or password was wrong'))
    end

    def self.status_configerror(msg=nil)
      status(ExternalLoginStatus::CONFIGERROR,
             (msg || 'external logins configuration error'))
    end

    def self.status_nochange(msg=nil)
      status(ExternalLoginStatus::NOCHANGE,
             (msg || 'auth OK, no change to user information'))
    end

    def self.status_notconfigured(msg=nil)
      status(ExternalLoginStatus::NOTCONFIGURED,
             (msg || 'external logins not configured'))
    end

    def self.status_puavousermissing(msg=nil)
      status(ExternalLoginStatus::PUAVOUSERMISSING,
             (msg || 'external logins puavo user missing'))
    end

    def self.status_unavailable(msg=nil)
      status(ExternalLoginStatus::UNAVAILABLE,
             (msg || 'external login service not available'))
    end

    def self.status_updated(msg=nil)
      status(ExternalLoginStatus::UPDATED,
             (msg || 'auth OK, user information updated'))
    end

    def self.status_updated_but_fail(msg=nil)
      status(ExternalLoginStatus::UPDATED_BUT_FAIL,
             (msg || 'auth FAILED, user information updated'))
    end

    def self.status_updateerror(msg=nil)
      status(ExternalLoginStatus::UPDATEERROR,
             (msg || 'error when updating user information in Puavo'))
    end
  end
end
