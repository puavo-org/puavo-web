require_relative "../lib/samba_attrs"

module PuavoRest

class Group < LdapModel
  include SambaAttrs

  ldap_map :dn, :dn
  ldap_map :puavoEduGroupType, :type, LdapConverters::SingleValue
  ldap_map :puavoId, :id, LdapConverters::SingleValue
  ldap_map :puavoExternalId, :external_id, LdapConverters::SingleValue
  ldap_map :objectClass, :object_classes, LdapConverters::ArrayValue
  ldap_map :cn, :abbreviation
  ldap_map :displayName, :name
  ldap_map :puavoSchool, :school_dn
  ldap_map :gidNumber, :gid_number, LdapConverters::Number
  ldap_map(:puavoPrinterQueue, :printer_queue_dns){ |v| Array(v) }
  ldap_map :memberUid, :member_usernames, LdapConverters::ArrayValue
  ldap_map :member, :member_dns, LdapConverters::ArrayValue
  ldap_map :puavoEduGroupType, :type, LdapConverters::SingleValue

  before :create do
    if Array(object_classes).empty?
      self.object_classes = ['top', 'posixGroup', 'puavoEduGroup','sambaGroupMapping']
    end

    unless self.abbreviation =~ /^[a-z0-9-]+$/
      raise BadInput, :user => "group abbreviation \"#{self.abbreviation}\" contains invalid characters"
    end

    unless Group.by_attr(:abbreviation, self.abbreviation, :multiple => true).empty?
      raise BadInput, :user => "duplicate group abbreviation \"#{self.abbreviation}\""
    end

    if id.nil?
      self.id = IdPool.next_id("puavoNextId").to_s
    end

    if gid_number.nil?
      self.gid_number = IdPool.next_id("puavoNextGidNumber")
    end

    if dn.nil?
      self.dn = "puavoId=#{ id },#{ self.class.ldap_base }"
    end

    write_samba_attrs
  end

  before :update do
    unless self.abbreviation =~ /^[a-z0-9-]+$/
      raise BadInput, :user => "group abbreviation \"#{self.abbreviation}\" contains invalid characters"
    end

    # validate abbreviation uniqueness, but don't check the group against itself
    other_groups = Group.by_attr(:abbreviation, self.abbreviation, :multiple => true)
    other_groups.reject!{|g| g.id == self.id }
    unless other_groups.empty?
      raise BadInput, :user => "duplicate group abbreviation \"#{self.abbreviation}\""
    end
  end

  computed_attr :school_id
  def school_id
    school_dn.to_s.match(/puavoid=([0-9]+)/i)[1]
  end

  def self.base_filter
    "(objectClass=puavoEduGroup)"
  end

  def self.ldap_base
    "ou=Groups,#{ organisation["base"] }"
  end

  def self.by_user_dn(dn)
    by_ldap_attr(:member, dn, :multiple => true)
  end

  def self.by_type_and_school(type, school, options = {})
    self.by_attrs({ :school_dn => school.dn,
                     :type => type },
                   options )
  end

  def self.teaching_groups_by_school(school)
    self.by_type_and_school("teaching group", school, :multiple => true)
  end

  def self.administrative_groups
    self.by_attr(:type, "administrative group", :multiple => true)
  end

  def printer_queues
    PrinterQueue.by_dn_array(printer_queue_dns)
  end

  # Add member to group. Append username to `memberUid` and dn to `member` ldap
  # attributes
  #
  # @param user [User] user to add as member
  def add_member(user)
    add(:member_usernames, user.username)
    add(:member_dns, user.dn)
  end

  # Like above, but without any User objects. Takes the username and DN directly.
  def add_member_raw(username, dn)
    add(:member_usernames, username)
    add(:member_dns, dn)
  end

  # Remove member for the group
  #
  # @param user [User] user to add as member
  def remove_member(user)
    remove(:member_usernames, user.username)
    remove(:member_dns, user.dn)
  end

  # Like above, but without any User objects. Takes the username and DN directly.
  def remove_member_raw(username, dn)
    remove(:member_usernames, username)
    remove(:member_dns, dn)
  end

  # Does user belong to this group
  #
  # @param user [User] user to add as member
  # @return [Boolean]
  def has?(user)
    return member_usernames.include?(user.username)
  end

  # Write internal samba attributes. Implementation is based on the puavo-web
  # code is not actually tested on production systems
  def write_samba_attrs
    set_samba_sid

    write_raw(:sambaGroupType, ["2"])
  end

  # Cached organisation query
  def organisation
    @organisation ||= Organisation.by_dn(self.class.organisation["base"])
  end


end

class Groups < PuavoSinatra

  get "/v3/administrative_groups" do
    auth :basic_auth, :kerberos
    json Group.administrative_groups
  end


  # -------------------------------------------------------------------------------------------------
  # -------------------------------------------------------------------------------------------------
  # EXPERIMENTAL V4 API

  # Use at your own risk. Currently read-only.


  # Maps "user" field names to LDAP attributes. Used when searching for data, as only
  # the requested fields are actually returned in the queries.
  USER_TO_LDAP = {
    'abbreviation'  => 'cn',
    'created'       => 'createTimestamp',   # LDAP operational attribute
    'dn'            => 'dn',
    'external_id'   => 'puavoExternalId',
    'gid_number'    => 'gidNumber',
    'id'            => 'puavoId',
    'member_dn'     => 'member',
    'member_uid'    => 'memberUid',
    'modified'      => 'modifyTimestamp',   # LDAP operational attribute
    'name'          => 'displayName',
    'school_id'     => 'puavoSchool',
    'type'          => 'puavoEduGroupType',
  }

  # Maps LDAP attributes back to "user" fields and optionally specifies a conversion type
  LDAP_TO_USER = {
    'cn'                => { name: 'abbreviation' },
    'createTimestamp'   => { name: 'created', type: :ldap_timestamp },
    'displayName'       => { name: 'name' },
    'dn'                => { name: 'dn' },
    'gidNumber'         => { name: 'gid_number', type: :integer },
    'member'            => { name: 'member_dn' },
    'memberUid'         => { name: 'member_uid' },
    'modifyTimestamp'   => { name: 'modified', type: :ldap_timestamp },
    'puavoExternalId'   => { name: 'external_id' },
    'puavoEduGroupType' => { name: 'type' },
    'puavoId'           => { name: 'id', type: :integer },
    'puavoSchool'       => { name: 'school_id', type: :id_from_dn },
  }

  def v4_do_group_search(filters, requested_ldap_attrs)
    base = "ou=Groups,#{Organisation.current['base']}"
    filter_string = v4_combine_filter_parts(filters)

    return Group.raw_filter(base, filter_string, requested_ldap_attrs)
  end

  # Get all (or some) groups in the organisation.
  # GET /v4/groups?fields=...
  get "/v4/groups" do
    auth :basic_auth, :kerberos

    raise Unauthorized, :user => nil unless User.current.admin?

    v4_do_operation do
      # which fields to get?
      user_fields = v4_get_fields(params).to_set
      ldap_attrs = v4_user_to_ldap(user_fields, USER_TO_LDAP)

      # optional filters
      filters = v4_get_filters_from_params(params, USER_TO_LDAP, 'puavoEduGroup')

      # do the query
      raw = v4_do_group_search(filters, ldap_attrs)

      # convert and return
      out = v4_ldap_to_user(raw, ldap_attrs, LDAP_TO_USER)
      out = v4_ensure_is_array(out, 'member_uid', 'member_dn')

      return 200, json({
        status: 'ok',
        error: nil,
        data: out,
      })
    end
  end

end
end
