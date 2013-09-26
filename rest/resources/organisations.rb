require 'puavo/ldap'

module PuavoRest
class Organisation < LdapHash
  ldap_map :dn, :dn
  ldap_map :o, :name
  ldap_map :puavoDomain, :domain
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoWlanSSID, :wlan_networks, &LdapConverters.parse_wlan
  ldap_map :puavoAllowGuest, :allow_guest, false, &LdapConverters.string_boolean
  ldap_map :puavoPersonalDevice, :personal_device, false, &LdapConverters.string_boolean
  ldap_map(:puavoActiveService, :external_services) do |es|
      Array(es).map { |s| s.downcase.strip }
  end

  def self.ldap_base
    ""
  end

  @@by_domain = nil

  def self.by_domain
    return @@by_domain if @@by_domain
    @@by_domain = {}

    LdapHash.setup(:credentials => CONFIG["server"]) do
      all.each do |org|
        @@by_domain[org["domain"]] = org
        if CONFIG["default_organisation_domain"] == org["domain"]
          @@by_domain["*"] = org
        end
      end
    end

    # Bootservers must have default organisation because they might use unknown
    # hostnames.
    if CONFIG["bootserver"] && @@by_domain["*"].nil?
      raise "Failed to configure #{ CONFIG["default_organisation_domain"].inspect } as default organisation"
    end

    @@by_domain
  end

  def self.clear_domain_cache
    @@by_domain = nil
  end

  def self.bases
    connection.search("", LDAP::LDAP_SCOPE_BASE, "(objectClass=*)", ["namingContexts"]) do |e|
      return e.get_values("namingContexts").select do |base|
        base != "o=puavo"
      end
    end
  end

  def self.all
    bases.map do |base|
      by_dn(base).merge("base" => base)
    end
  end

end


class Organisations < LdapSinatra

  get "/v3/current_organisation" do
    json LdapHash.organisation
  end

  get "/v3/organisations/:domain" do
    json Organisation.by_domain[params[:domain]]
  end

  get "/v3/organisations" do
    json(Organisation.by_domain.map do |k, v|
      v.merge("domain" => k)
    end)
  end

end
end
