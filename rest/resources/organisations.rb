require 'puavo/ldap'

module PuavoRest
class Organisation < LdapModel
  ldap_map :dn, :dn
  ldap_map :dn, :base
  ldap_map :o, :name
  ldap_map :puavoDomain, :domain
  ldap_map(:owner, :owner) { |v| Array(v) }
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :preferredLanguage, :preferred_language
  ldap_map :puavoLocale, :locale
  ldap_map :puavoWlanSSID, :wlan_networks, &LdapConverters.parse_wlan
  ldap_map :puavoAllowGuest, :allow_guest, :default => false, &LdapConverters.string_boolean
  ldap_map :puavoAutomaticImageUpdates, :automatic_image_updates, :default => false, &LdapConverters.string_boolean
  ldap_map :puavoPersonalDevice, :personal_device, :default => false, &LdapConverters.string_boolean
  ldap_map(:puavoActiveService, :external_services) do |es|
      Array(es).map { |s| s.downcase.strip }
  end
  ldap_map :puavoTimezone, :timezone
  ldap_map :puavoKeyboardLayout, :keyboard_layout
  ldap_map :puavoKeyboardVariant, :keyboard_variant
  ldap_map :puavoImageSeriesSourceURL, :image_series_source_urls, LdapConverters::ArrayValue
  ldap_map :puavoConf, :puavoconf, LdapConverters::PuavoConfObj

  ldap_map :eduOrgHomePageURI, :homepage

  ldap_map :puavoDeviceAutoPowerOffMode, :autopoweroff_mode
  ldap_map :puavoDeviceOnHour,           :daytime_start_hour
  ldap_map :puavoDeviceOffHour,          :daytime_end_hour
  ldap_map :puavoKerberosRealm,          :puavo_kerberos_realm

  ldap_map :puavoNotes, :notes, LdapConverters::SingleValue
  ldap_map :puavoDefaultTeacherPermissions, :default_teacher_permissions, LdapConverters::ArrayValue

  ldap_map :puavoMenuData, :puavomenu_data
  skip_serialize :puavomenu_data

  ldap_map :puavoOrganisationOID, :oid

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
        all.each do |org|
          cache[org.domain] = org
        end
      end

      @@organisation_cache = cache
    end
  end

  def self.by_dn(dn)
    res = nil
    connection.search(dn, LDAP::LDAP_SCOPE_BASE, "(objectClass=*)", []) do |entry|
      res = entry.to_hash
    end

    from_ldap_hash(res) if res
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
    image = get_own(:preferred_image)
    image ? image.strip : nil
  end

  def homepage
    get_own(:homepage)
  end

  computed_attr :owners
  def owners
    # A compact hash, contains only relevant information about the user
    # Some of the fields, like UID and SSH public key, are needed by
    # puavoadmins-update and puavo-update-admins scripts.
    def owner_hash(u)
      # don't crash if the owners array contains a deleted user
      return nil unless u

      return {
        id: u.id,
        dn: u.dn,
        first_name: u.first_name,
        last_name: u.last_name,
        username: u.username,
        uid_number: u.uid_number,
        gid_number: u.gid_number,
        ssh_public_key: u.ssh_public_key,
      }
    end

    Array( get_own(:owner) ).select{ |o| o.to_s.match(/#{self.base}$/) }.map do |owner_dn|
      owner_hash(User.by_dn(owner_dn))
    end.compact
  end

  # Customized to_hash method for stripping down the returned data to only bare essentials
  def to_hash
    out = {
      dn: self.dn,
      base: self.base,
      name: self.name,
      domain: self.domain,
      oid: self.oid,
      notes: self.notes,
      preferred_image: self.preferred_image,
      preferred_language: self.preferred_language,
      locale: self.locale,
      allow_guest: self.allow_guest,
      automatic_image_updates: self.automatic_image_updates,
      personal_device: self.personal_device,
      timezone: self.timezone,
      keyboard_layout: self.keyboard_layout,
      keyboard_variant: self.keyboard_variant,
      image_series_source_urls: self.image_series_source_urls,
      puavoconf: self.puavoconf,
      autopoweroff_mode: self.autopoweroff_mode,
      daytime_start_hour: self.daytime_start_hour,
      daytime_end_hour: self.daytime_end_hour,
      puavo_kerberos_realm: self.puavo_kerberos_realm,
      owners: []
    }

    # Fill in the owners array without constructing user objects
    # (the self.owners User objects appear to be constructed on-demand)
    attrs = ['puavoId', 'dn', 'uid', 'givenName', 'sn', 'uidNumber', 'gidNumber', 'puavoSshPublicKey']

    self.owner.each do |dn|
      next if dn == 'uid=admin,o=puavo'

      User.raw_filter(LdapModel.ldap_escape(dn), '(objectclass=*)', attrs) do |o|
        out[:owners] << {
          id: o['puavoId'][0].to_i,
          dn: dn,
          username: o['uid'][0].force_encoding('UTF-8'),
          first_name: o['givenName'][0].force_encoding('UTF-8'),
          last_name: o['sn'][0].force_encoding('UTF-8'),
          uid_number: o['uidNumber'][0].to_i,
          gid_number: o['gidNumber'][0].to_i,
          ssh_public_key: o.to_hash.fetch('puavoSshPublicKey', [])[0]
        }
      end
    end

    return out
  end

end


class Organisations < PuavoSinatra

  post "/v3/refresh_organisations" do
    Organisation.refresh
    json({"ok" => "true"})
  end

  def require_admin!
    unless v4_is_request_allowed?(User.current)
      raise Unauthorized, :user => "Sorry, only administrators can access this resource."
    end
  end

  def require_admin_or_not_people!
    return if not LdapModel.settings[:credentials][:dn].to_s.downcase.match(/people/)

    require_admin!
  end

  get "/v3/current_organisation" do
    auth :basic_auth, :kerberos, :server_auth
    require_admin_or_not_people!

    Organisation.refresh
    json Organisation.current
  end

  get "/v3/organisations/:domain" do
    auth :basic_auth, :kerberos, :server_auth
    require_admin_or_not_people!

    Organisation.refresh
    json Organisation.by_domain(params[:domain])
  end

  # -------------------------------------------------------------------------------------------------
  # -------------------------------------------------------------------------------------------------
  # EXPERIMENTAL V4 API

  # Use at your own risk. Currently read-only.

  USER_TO_LDAP = {
    'abbreviation'    => 'cn',
    'active_services' => 'puavoActiveService',
    'created'         => 'createTimestamp',   # LDAP operational attribute
    'description'     => 'description',
    'dn'              => 'dn',
    'modified'        => 'modifyTimestamp',   # LDAP operational attribute
    'name'            => 'o',
    'notes'           => 'puavoNotes',
    'oid'             => 'puavoOrganisationOID',
    'owners'          => 'owner',
    'puavoconf'       => 'puavoConf',
    'timezone'        => 'puavoTimezone',
  }

  LDAP_TO_USER = {
    'cn'                  => { name: 'abbreviation' },
    'createTimestamp'     => { name: 'created', type: :ldap_timestamp },
    'description'         => { name: 'description' },
    'dn'                  => { name: 'dn' },
    'modifyTimestamp'     => { name: 'modified', type: :ldap_timestamp },
    'o'                   => { name: 'name' },
    'owner'               => { name: 'owners' },
    'puavoActiveService'  => { name: 'active_services' },
    'puavoConf'           => { name: 'puavoconf', type: :json },
    'puavoNotes'          => { name: 'notes' },
    'puavoOrganisationOID' => { name: 'oid' },
    'puavoTimezone'       => { name: 'timezone' },
  }

  # GET /v4/organisation?fields=...
  get '/v4/organisation' do
    auth :basic_auth, :kerberos, :server_auth

    v4_do_operation do
      user_fields = v4_get_fields(params).to_set
      ldap_attrs = v4_user_to_ldap(user_fields, USER_TO_LDAP)

      # Organisation.raw_filter() exists, but I can't get it to work
      raw = nil

      Organisation.connection.search(Organisation.current.dn, LDAP::LDAP_SCOPE_BASE,
                                     '(objectClass=*)', ldap_attrs) do |entry|
        raw = [entry.to_hash]
      end

      out = v4_ldap_to_user(raw, ldap_attrs, LDAP_TO_USER)
      out = v4_ensure_is_array(out, 'active_services', 'owners')

      return 200, json({
        status: 'ok',
        error: nil,
        data: out,
      })
    end
  end

  # Retrieves a list of all organisations in the database
  get '/v4/organisations_list' do
    auth :basic_auth, :kerberos, :server_auth

    topdomain = File.read('/etc/puavo/topdomain').strip

    # "dc=edu,dc=XXXXX,dc=YY"
    matcher = /^dc=edu,dc=(.*),dc=(.*$)/.freeze
    organisations = []

    Organisation.connection.search('', LDAP::LDAP_SCOPE_BASE, '(objectClass=*)', ['namingContexts']) do |entry|
      organisations = (entry['namingContexts'] || []).collect do |dn|
        match = matcher.match(dn)

        match ? {
          name: match[1],
          domain: "#{match[1]}.#{topdomain}",
          dn: dn,
        } : nil
      end.compact
    end;

    return 200, json({
      status: 'ok',
      error: nil,
      data: organisations
    })
  end

end
end
