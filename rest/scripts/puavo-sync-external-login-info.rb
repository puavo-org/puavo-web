#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'bundler/setup'
require_relative '../puavo-rest'

require 'yaml'

class SyncLog
  def error(msg); Kernel::warn(msg); end
  def info(msg) ; Kernel::puts(msg); end
  def warn(msg) ; Kernel::warn(msg); end
end

# necessary for routing ExternalLogin logging to stdout/stderr
$rest_log = SyncLog.new

topdomain = IO.read('/etc/puavo/topdomain').chomp

puavo_rest_base_conf = YAML::load_file('/etc/puavo-rest.yml')
raise '/etc/puavo-rest.yml is not a hash' \
  unless puavo_rest_base_conf.kind_of?(Hash)

puavo_rest_extlogin_conf \
  = YAML::load_file('/etc/puavo-rest.d/external_logins.yml')
raise '/etc/puavo-rest.d/external_logins.yml is not a hash' \
  unless puavo_rest_extlogin_conf.kind_of?(Hash)

puavo_rest_conf = puavo_rest_base_conf.merge(puavo_rest_extlogin_conf)

extlogin_conf = puavo_rest_conf['external_login']

raise 'no external login configuration' unless extlogin_conf.kind_of?(Hash)

all_organisations_ok = true

extlogin_conf.each do |organisation, org_conf|
  begin
    raise 'organisation is not a string' unless organisation.kind_of?(String)

    puts ">>> checking organisation #{ organisation }"

    org_domain = "#{ organisation }.#{ topdomain }"

    admin_dn = org_conf['admin_dn']
    raise 'no admin dn' unless admin_dn

    admin_password = org_conf['admin_password']
    raise 'no admin password' unless admin_password

    LdapModel.setup(
      :credentials  => { :dn => admin_dn, :password => admin_password },
      :organisation => PuavoRest::Organisation.by_domain!(org_domain),
      :rest_root    => 'DUMMY')

    external_login = PuavoRest::ExternalLogin.new
    login_service = external_login.new_external_service_handler()

    external_users = nil
    begin
      external_users = login_service.lookup_all_users()
    rescue StandardError => e
      raise 'error looking up all users from external login service: ' \
              + e.message
    end

    all_users_ok = true

    puts ">> checking users to remove on [#{ organisation }]"

    PuavoRest::User.all.each do |puavo_user|
      begin
        external_id = puavo_user.external_id
        unless external_id then
          puts "> user #{ puavo_user.username } [#{ organisation }] " \
                 + 'has no external id, skipping check'
          next
        end

        if external_users.has_key?(external_id) then
          puts "> user #{ puavo_user.username } (#{ external_id })" \
                 + " [#{ organisation }] exists in external service"
          next
        end

        puts "> user #{ puavo_user.username } (#{ external_id })" \
               + " [#{ organisation }] does not exist in external service"

        # User not found in external service, so it must be in Puavo
        # and we mark it for removal.
        if puavo_user.mark_for_removal! then
          puts("> puavo user '#{ puavo_user.username }' (#{ external_id })" \
                 + " [#{ organisation }] is marked for removal")
        end

      rescue StandardError => e
        warn("! error in marking user '#{ puavo_user.username }'" \
               + " [#{ organisation }] for removal: #{ e.backtrace }")
               # + " [#{ organisation }] for removal: #{ e.message }")
        all_users_ok = false
      end
    end

    puts '>> checking updates to users in Puavo'

    external_users.each do |external_id, userinfo|
      begin
        username   = userinfo['username']
        ldap_entry = userinfo['ldap_entry']

        puts "> updating Puavo information on #{ username }" \
               + " (#{ external_id }) [#{ organisation }]"

        login_service.set_ldapuserinfo(username, ldap_entry)
        userinfo = login_service.get_userinfo(username)
        user_status = external_login.update_user_info(userinfo, nil, {})

        if user_status != PuavoRest::ExternalLoginStatus::NOCHANGE \
          && user_status != PuavoRest::ExternalLoginStatus::UPDATED then
            raise '! user information update to Puavo failed for' \
                    + " '#{ username }' (#{ external_id })" \
                    + " (#{ organisation })"
        end

      rescue StandardError => e
        warn("! error checking user '#{ username }' (#{ external_id })" \
               + " [#{ organisation }] in external login service: "     \
               + e.message + " " \
               + e.backtrace.join(' / '))
               # + " [#{ organisation }] in external login service: "   \
        all_users_ok = false
      end
    end

    unless all_users_ok then
      raise 'could not check and update one or more users' \
              + ' from external login service'
    end

  rescue StandardError => e
    warn('!! error in updating users from external login service on' \
           + " organisation '#{ organisation }': #{ e.message }")
    all_organisations_ok = false
  end
end

unless all_organisations_ok then
  warn '!!! some organisation syncs failed'
  exit(1)
end

exit(0)
