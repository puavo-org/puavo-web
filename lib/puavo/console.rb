module Puavo
  class Console

    def initialize(organisation_key, admin_password, admin_uid = "admin")
      unless organisation = Puavo::Organisation.find(organisation_key)
        raise "Can't find organisation configuration (#{ organisation_key })."
      end

      I18n.locale = organisation.value_by_key('locale')

      default_ldap_configuration = ActiveLdap::Base.ensure_configuration
      puavo_dn = default_ldap_configuration["bind_dn"]
      puavo_password = default_ldap_configuration["password"]

      LdapBase.ldap_setup_connection( organisation.ldap_host,
                                      organisation.ldap_base,
                                      puavo_dn,
                                      puavo_password )

      admin_user = User.find(:first, :attribute => "uid", :value => admin_uid)

      raise "Can't find admin user" if not admin_user

      LdapBase.ldap_setup_connection( organisation.ldap_host,
                                      organisation.ldap_base,
                                      admin_user.dn.to_s,
                                      admin_password )
    end
  end
end
