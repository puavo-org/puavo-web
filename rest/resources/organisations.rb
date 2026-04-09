module PuavoRest
class Organisation < LdapModel
  ldap_map :dn, :dn
  ldap_map :dn, :base
  ldap_map :o, :name
  ldap_map :puavodomain, :domain
  ldap_map(:owner, :owner) { |v| Array(v) }
  ldap_map :puavodeviceimage, :preferred_image
  ldap_map :preferredlanguage, :preferred_language
  ldap_map :puavolocale, :locale
  ldap_map :puavowlanssid, :wlan_networks, &LdapConverters.parse_wlan
  ldap_map :puavoallowguest, :allow_guest, :default => false, &LdapConverters.string_boolean
  ldap_map :puavoautomaticimageupdates, :automatic_image_updates, :default => false, &LdapConverters.string_boolean
  ldap_map :puavopersonaldevice, :personal_device, :default => false, &LdapConverters.string_boolean
  ldap_map(:puavoactiveservice, :external_services) do |es|
      Array(es).map { |s| s.downcase.strip }
  end
  ldap_map :puavotimezone, :timezone
  ldap_map :puavokeyboardlayout, :keyboard_layout
  ldap_map :puavokeyboardvariant, :keyboard_variant
  ldap_map :puavoimageseriessourceurl, :image_series_source_urls, LdapConverters::ArrayValue
  ldap_map :puavoconf, :puavoconf, LdapConverters::PuavoConfObj

  ldap_map :eduorghomepageuri, :homepage

  ldap_map :puavodeviceautopoweroffmode, :autopoweroff_mode
  ldap_map :puavodeviceonhour,           :daytime_start_hour
  ldap_map :puavodeviceoffhour,          :daytime_end_hour
  ldap_map :puavokerberosrealm,          :puavo_kerberos_realm

  ldap_map :puavonotes, :notes, LdapConverters::SingleValue
  ldap_map :puavodefaultteacherpermissions, :default_teacher_permissions, LdapConverters::ArrayValue

  ldap_map :puavomenudata, :puavomenu_data
  skip_serialize :puavomenu_data

  ldap_map :puavoorganisationoid, :oid
  ldap_map :puavodevicerecoverypublickey, :device_recovery_public_key, LdapConverters::JSONObj

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
    ldap_op(:search, base: dn,
                     scope: Net::LDAP::SearchScope_BaseObject,
                     filter: '(objectClass=*)') do |entry|
      res = entry.to_h
    end

    from_ldap_hash(res) if res
  end

  def self.bases
    ldap_op(:search, base: '',
                     scope: Net::LDAP::SearchScope_BaseObject,
                     filter: '(objectClass=*)',
                     attributes: ['namingContexts']) do |entry|
      return Array(entry[:namingcontexts]).select do |base|
               base != 'o=puavo'
             end
    end
  end

  def self.all
    _bases = bases
    raise NotFound, :user => 'no ldap bases found' unless _bases
    _bases.map { |base| by_dn(base) }
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
      device_recovery_public_key: self.device_recovery_public_key,
      owners: [],
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

  get '/v3/current_organisation' do
    oauth2 scopes: ['puavo.read.organisation']
    auth :oauth2_token, :basic_auth, :kerberos, :server_auth
    require_admin_or_not_people!

    Organisation.refresh
    json Organisation.current
  end

  get '/v3/organisations/:domain' do
    oauth2 scopes: ['puavo.read.organisation']
    auth :oauth2_token, :basic_auth, :kerberos, :server_auth
    require_admin_or_not_people!

    Organisation.refresh
    json Organisation.by_domain(params[:domain])
  end

  # -------------------------------------------------------------------------------------------------
  # -------------------------------------------------------------------------------------------------
  # EXPERIMENTAL V4 API

  # Use at your own risk. Currently read-only.

  LDAP_TO_USER = {
    'cn'                   => { name: 'abbreviation' },
    'createTimestamp'      => { name: 'created', type: :ldap_timestamp },        # LDAP operational attribute
    'description'          => { name: 'description' },
    'dn'                   => { name: 'dn' },
    'modifyTimestamp'      => { name: 'modified', type: :ldap_timestamp },       # LDAP operational attribute
    'o'                    => { name: 'name' },
    'owner'                => { name: 'owners' },
    'puavoActiveService'   => { name: 'active_services' },
    'puavoConf'            => { name: 'puavoconf', type: :json },
    'puavoNotes'           => { name: 'notes' },
    'puavoOrganisationOID' => { name: 'oid' },
    'puavoTimezone'        => { name: 'timezone' },
  }

  # Maps "user" field names to LDAP attributes. Used when searching for data, as only
  # the requested fields are actually returned in the queries.
  USER_TO_LDAP = Hash[ LDAP_TO_USER.map { |k,v| [ v[:name], k ] } ]

  # GET /v4/organisation?fields=...
  get '/v4/organisation' do
    oauth2 scopes: ['puavo.read.organisation']
    auth :oauth2_token, :basic_auth, :kerberos, :server_auth

    raise Unauthorized, user: nil unless v4_is_request_allowed?(User.current)

    v4_do_operation do
      user_fields = v4_get_fields(params).to_set
      ldap_attrs = v4_user_to_ldap(user_fields, USER_TO_LDAP)

      # Organisation.raw_filter() exists, but I can't get it to work
      raw = nil

      Organisation.ldap_op(:search, base: Organisation.current.dn,
                                    scope: Net::LDAP::SearchScope_BaseObject,
                                    filter: '(objectClass=*)',
                                    attributes: ldap_attrs) do |entry|
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

  # Retrieves a list of all organisations in the database. Most users don't have enough rights to call
  # this endpoint. Even organisation owners aren't privileged enough. You need to use one of the LDAP
  # "super accounts", like uid=puavo,o=puavo or uid=admin,o=puavo.
  get '/v4/organisations_list' do
    auth :basic_auth, :kerberos, :server_auth

    topdomain = File.read('/etc/puavo/topdomain').strip

    # "dc=edu,dc=XXXXX,dc=YY"
    matcher = /^dc=edu,dc=(.*),dc=(.*$)/.freeze
    organisations = []

    Organisation.ldap_op(:search, base: '',
                                  scope: Net::LDAP::SearchScope_BaseObject,
                                  filter: '(objectClass=*)',
                                  attributes: ['namingContexts']) do |entry|
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
