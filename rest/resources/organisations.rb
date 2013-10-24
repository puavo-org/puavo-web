require 'puavo/ldap'

module PuavoRest
class Organisation < LdapModel
  ldap_map :dn, :dn
  ldap_map :dn, :base
  ldap_map :o, :name
  ldap_map :puavoDomain, :domain
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :preferredLanguage, :preferred_language
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
    if @@by_domain.nil?
      raise "Call Organisation.refresh first!"
    end
    return @@by_domain
  end

  def self.refresh
    by_domain = {}

    LdapModel.setup(:credentials => CONFIG["server"]) do
      all.each do |org|
        by_domain[org["domain"]] = org
        if CONFIG["default_organisation_domain"] == org["domain"]
          by_domain["*"] = org
        end
      end
    end

    # Bootservers must have default organisation because they might use unknown
    # hostnames.
    if CONFIG["bootserver"] && by_domain["*"].nil?
      raise "Failed to configure #{ CONFIG["default_organisation_domain"].inspect } as default organisation"
    end

    @@by_domain = by_domain
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
      by_dn(base)
    end
  end

  def self.current
    # TODO: Refresh organisation from ldap
    LdapModel.organisation
  end

  refresh
end


class Organisations < LdapSinatra

  post "/v3/refresh_organisations" do
    Organisation.refresh
  end

  def require_admin
    if not User.current.admin?
      raise Unauthorized, :user => "Sorry, only administrators can access this resource."
    end
  end

  get "/v3/organisations" do
    auth :basic_auth, :kerberos
    require_admin

    LdapModel.setup(:credentials => CONFIG["server"]) do
      json Organisation.all
    end
  end

  get "/v3/current_organisation" do
    auth :basic_auth, :kerberos
    require_admin

    json Organisation.current
  end

  get "/v3/organisations/:domain" do
    auth :basic_auth, :kerberos
    require_admin

    json Organisation.by_domain[params[:domain]]
  end

end
end
