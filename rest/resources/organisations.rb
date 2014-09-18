require 'puavo/ldap'

module PuavoRest
class Organisation < LdapModel
  ldap_map :dn, :dn
  ldap_map :dn, :base
  ldap_map :o, :name
  ldap_map :puavoDomain, :domain
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :preferredLanguage, :preferred_language
  ldap_map :puavoLocale, :locale
  ldap_map :puavoWlanSSID, :wlan_networks, &LdapConverters.parse_wlan
  ldap_map :puavoAllowGuest, :allow_guest, false, &LdapConverters.string_boolean
  ldap_map :puavoAutomaticImageUpdates, :automatic_image_updates, false, &LdapConverters.string_boolean
  ldap_map :puavoPersonalDevice, :personal_device, false, &LdapConverters.string_boolean
  ldap_map(:puavoActiveService, :external_services) do |es|
      Array(es).map { |s| s.downcase.strip }
  end
  ldap_map :puavoTimezone, :timezone
  ldap_map :puavoKeyboardLayout, :keyboard_layout
  ldap_map :puavoKeyboardVariant, :keyboard_variant

  ldap_map :puavoDeviceAutoPowerOffMode, :autopoweroff_mode
  ldap_map :puavoDeviceOnHour,           :daytime_start_hour
  ldap_map :puavoDeviceOffHour,          :daytime_end_hour

  def organisation_key
    domain.split(".").first if domain
  end

  def self.ldap_base
    ""
  end

  @@organisation_cache = nil

  def self.by_domain(domain)
    refresh if @@organisation_cache.nil?
    @@organisation_cache && @@organisation_cache[domain]
  end

  def self.by_domain!(domain)

    if domain.to_s.strip == ""
      raise InternalError, :user => "Invalid organisation: [EMPTY]"
    end

    org = by_domain(domain)
    if org.nil?
      raise NotFound, {
        :user => "Cannot find organisation for #{ domain }",
        :msg => "Try Organisation.refresh"
      }
    end
    return org
  end

  def self.default_organisation_domain!
    by_domain!(CONFIG["default_organisation_domain"])
  end

  REFRESH_LOCK = Mutex.new
  def self.refresh
    REFRESH_LOCK.synchronize do
      cache = {}

      LdapModel.setup(:credentials => CONFIG["server"]) do
        all.each{ |org| cache[org.domain] = org }
      end

      @@organisation_cache = cache
    end
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

  def self.current(option=nil)
    if option == :no_cache
      return Organisation.by_dn(LdapModel.organisation.dn)
    end
    LdapModel.organisation
  end

  def self.current?
    # TODO: Refresh organisation from ldap
    LdapModel.organisation?
  end

  def preferred_image
      if get_own(:preferred_image)
        get_own(:preferred_image).strip
      end
  end

end


class Organisations < LdapSinatra

  post "/v3/refresh_organisations" do
    Organisation.refresh
  end

  def require_admin!
    if not User.current.admin?
      raise Unauthorized, :user => "Sorry, only administrators can access this resource."
    end
  end

  get "/v3/organisations" do
    auth :basic_auth, :kerberos
    require_admin!

    LdapModel.setup(:credentials => CONFIG["server"]) do
      json Organisation.all
    end
  end

  get "/v3/current_organisation" do
    auth :basic_auth, :kerberos
    require_admin!

    json Organisation.current
  end

  get "/v3/organisations/:domain" do
    auth :basic_auth, :kerberos
    require_admin!

    json Organisation.by_domain(params[:domain])
  end

end
end
