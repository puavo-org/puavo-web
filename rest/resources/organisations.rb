require 'puavo/ldap'

module PuavoRest
class Organisation < LdapHash
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoWlanSSID, :wlan_networks, &LdapConverters.parse_wlan
  ldap_map :puavoAllowGuest, :allow_guest, false, &LdapConverters.string_boolean
  ldap_map :puavoPersonalDevice, :personal_device, false, &LdapConverters.string_boolean

  @@by_domain = nil
  def self.by_domain
    return @@by_domain if @@by_domain

    puavo_ldap = Puavo::Ldap.new(:base => "")
    organisation_bases = puavo_ldap.all_bases

    puavo_ldap.unbind

    by_domain = {}

    organisation_bases.each do |base|
      puavo_ldap = Puavo::Ldap.new(:base => base)

      if organisation_entry = puavo_ldap.organisation
        organisation = Puavo::Client::Base.new_by_ldap_entry( organisation_entry )

        # Default organisation is the organisation of the bootserver
        if PUAVO_ETC.domain == organisation.domain
          by_domain["*"] = organisation.data
        end

        by_domain[organisation.domain] = organisation.data
      end

      puavo_ldap.unbind
    end

    @@by_domain = by_domain
  end

end
end
