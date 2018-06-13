require_relative "../lib/password"
require_relative "../lib/samba_attrs"

require 'date'
require 'securerandom'

module PuavoRest

class User < LdapModel
  include SambaAttrs

  ldap_map :dn, :dn
  ldap_map :puavoId, :id, LdapConverters::Number # FIXME: this attribute should be a String
  ldap_map :puavoExternalId, :external_id, LdapConverters::SingleValue
  ldap_map :puavoExternalData, :external_data, LdapConverters::SingleValue
  ldap_map :objectClass, :object_classes, LdapConverters::ArrayValue
  ldap_map :uid, :username
  ldap_map :uidNumber, :uid_number, LdapConverters::Number
  ldap_map :gidNumber, :gid_number, LdapConverters::Number
  ldap_map :sn, :last_name
  ldap_map :givenName, :first_name
  ldap_map(:mail, :secondary_emails){ |v| _, *other_emails = Array(v); other_emails }
  ldap_map :mail, :email
  ldap_map :puavoSchool, :school_dns, LdapConverters::ArrayValue
  ldap_map :preferredLanguage, :preferred_language
  ldap_map(:jpegPhoto, :profile_image_link) do |image_data|
    if image_data
      @model.link "/v3/users/#{ @model.username }/profile.jpg"
    end
  end
  ldap_map :puavoLocale, :locale
  ldap_map :puavoTimezone, :timezone
  ldap_map :puavoLocked, :locked, LdapConverters::StringBoolean
  ldap_map :puavoSshPublicKey, :ssh_public_key
  ldap_map :homeDirectory, :home_directory
  ldap_map :loginShell, :login_shell, :default => "/bin/bash"
  ldap_map :telephoneNumber, :telephone_number
  ldap_map :puavoRemovalRequestTime, :removal_request_time,
           LdapConverters::TimeStamp
  ldap_map :eduPersonPrincipalName, :edu_person_principal_name
  ldap_map :puavoEduPersonReverseDisplayName, :reverse_name

  # The classic Roles in puavo-web are now deprecated.
  # puavoEduPersonAffiliation will used as the roles from now on
  ldap_map :puavoEduPersonAffiliation, :roles, LdapConverters::ArrayValue

  # Roles does not make much sense without a school
  skip_serialize :roles

  # List of school DNs where the user is school admin
  ldap_map(:puavoAdminOfSchool, :admin_of_school_dns) do |dns|
    Array(dns).map do |dn|
      dn.downcase
    end
  end

  BANNED_USERNAMES = Set.new([
    "root",
    "administrator",
    "postmaster",
    "adm",
    "admin"
  ])

  VALID_ROLES = Set.new([
    "teacher",
    "staff",
    "student",
    "visitor",
    "parent",
    "admin",
    "testuser"
  ])

  before :update, :create do
    write_raw(:displayName, [first_name.to_s + " " + last_name.to_s])
  end

  before :destroy do
    # Currently "delete_kerberos_principal" updates the user entry on ldap,
    # which might affect associations, so do this first and only then
    # delete all associations.
    delete_kerberos_principal
    delete_all_associations
  end

  before :update do
    new_username = username
    old_username = @previous_values[:username]
    if old_username && old_username != new_username then
      # We need to update associations if username has changed, but must use
      # the old username when deleting.
      self.username = old_username
      delete_all_associations
      self.username = new_username
      self.edu_person_principal_name \
        = "#{ username }@#{ organisation.puavo_kerberos_realm }"
    end
  end

  def validate

    if username.to_s.strip.empty?
      add_validation_error(:username, :username_empty, "Username is empty")
    else
      validate_unique(:username)

      if BANNED_USERNAMES.include?(username)
        add_validation_error(:username, :username_not_allowed, "Username not allowed")
      end

      if username.start_with?("adm-")
        add_validation_error(:username, :username_not_allowed, "'adm-' prefix is not allowed")
      end

      # XXX: In puavo-web it's possible to configure from organisation upper
      # case letters as allowed but it's not implemented here yet
      if !/^[a-z]+[a-z0-9.-]+$/.match(username)
        add_validation_error(:username, :username_invalid, "Invalid username. Allowed characters a-z, 0-9, dot and dash. Also it must begin with a letter")
      end

      if username.size < 3
        add_validation_error(:username, :username_too_short, "Username too short")
      end

      if username.size > 255
        add_validation_error(:username, :username_too_long, "Username too long")
      end

    end

    if roles.empty?
      add_validation_error(:roles, :no_roles, "at least one role must be set")
    else
      roles.each do |role|
        if !VALID_ROLES.include?(role)
          add_validation_error(:roles, :unknown_role, "Unknow role #{ role }. Valid roles are #{ VALID_ROLES.to_a.join(", ") }")
        end
      end
    end

    if first_name.to_s.strip.empty?
      add_validation_error(:first_name, :first_name_empty, "First name is empty")
    end

    if last_name.to_s.strip.empty?
      add_validation_error(:last_name, :last_name_empty, "Last name is empty")
    end

    if school.nil?
      add_validation_error(:school_dns, :must_have_school, "no schools are set")
    end

    if !telephone_number.nil? && !telephone_number.match(/^[A-Za-z[:digit:][:space:]'()+,-.\/:?"]+$/)
      add_validation_error(:telephone_number, :telephone_number_invalid,
                           "Invalid telephone number. Allowed characters: A-Z, a-z, 0-9, ', (, ), +, ,, -, ., /, :, ?, space and \"")
    end

    # FIXME: Validate external id?
    #if !external_id.nil?
    #  validate_unique(:external_id)
    #end

    validate_unique(:email)
    # XXX validate secondary emails too!!
  end


  before :create do
    if Array(object_classes).empty?
      self.object_classes = ["top", "posixAccount", "inetOrgPerson", "puavoEduPerson", "sambaSamAccount", "eduPerson"]
    end

    if id.nil?
      self.id = IdPool.next_id("puavoNextId")
    end

    if dn.nil?
      self.dn = "puavoId=#{ id },#{ self.class.ldap_base }"
    end

    if uid_number.nil?
      self.uid_number = IdPool.next_id("puavoNextUidNumber")
    end

    if gid_number.nil? && school
      self.gid_number = school.gid_number
    end

    if edu_person_principal_name.nil? then
      self.edu_person_principal_name \
        = "#{ username }@#{ organisation.puavo_kerberos_realm }"
    end

    self.login_shell = '/bin/bash'

    if reverse_name.nil? then
      self.reverse_name = "#{ last_name } #{ first_name }"
    end

    if locked.nil? then
      self.locked = false
    end

    validate_unique(:uid_number)
    validate_unique(:id)
    assert_validation

    write_samba_attrs
  end

  def delete_kerberos_principal
    # XXX We should really destroy the kerberos principal for this user,
    # XXX but for now we just set a password to some unknown value
    # XXX so that the kerberos principal can not be used.
    self.password = SecureRandom.hex(128)
    self.save!
  end

  def delete_all_associations
    # remove Samba associations
    [ 'Domain Admins', 'Domain Users' ].each do |samba_group_name|
      sambagroup = SambaGroup.by_attr!(:name, samba_group_name)
      if sambagroup.members.include?(username) then
        sambagroup.remove(:members, username)
        sambagroup.save!
      end
    end

    # remove group associations
    groups.each do |group|
      group.remove_member(self)
      group.save!
    end

    # remove school associations
    schools.each do |school|
      remove_from_school!(school)
    end
  end

  # Just store password locally and handle it in after hook
  def password=(pw)
    @password = pw
  end

  after :create, :update do
    next if @password.nil?

    begin
      Puavo.change_passwd(:all,
                          CONFIG['ldap'],
                          LdapModel.settings[:credentials][:dn],
                          User.current.username,
                          LdapModel.settings[:credentials][:password],
                          username,
                          @password)
    ensure
      @password = nil
    end
  end

  after :create, :update do
    [ 'Domain Admins', 'Domain Users' ].each do |samba_group_name|
      should_belong = (samba_group_name == 'Domain Users') \
                         || (samba_group_name == 'Domain Admins' \
                               && !self.admin_of_school_dns.empty?)

      sambagroup = SambaGroup.by_attr!(:name, samba_group_name)

      if should_belong then
        if ! sambagroup.members.include?(username) then
          sambagroup.add(:members, username)
          sambagroup.save!
        end
      else
        if sambagroup.members.include?(username) then
          sambagroup.remove(:members, username)
          sambagroup.save!
        end
      end
    end
  end

  after :update do
    current_schools = schools

    # XXX: Also search for any broken relations. In ideal world this would not
    # necessary but as there are no proper constraints in LDAP there can be
    # stale relations. This fixes those when user model is saved but it also
    # makes saving slower.
    current_schools += School.by_attr(:member_dns, dn, :multiple => true)
    current_schools += School.by_attr(:member_usernames, username, :multiple => true)
    current_schools = current_schools.uniq{|s| s.dn}

    current_schools.each do |s|
      if school_dns.include?(s.dn)
        add_to_school!(s)
      else
        remove_from_school!(s)
      end
    end
  end

  after :create do
    schools.each { |s| add_to_school!(s) }
  end

  def home_directory=(value)
    add_validation_error(:home_directory, :read_only, "home_directory is read only")
  end

  def telephone_number=(value)
    # LDAP raises an error if empty string is given as the number.
    # Just skip the attribute if its empty
    return if value.to_s.strip == ""
    write_raw(:telephoneNumber, transform(:telephone_number, :write, value))
  end

  # Fix the gid number when moving user to another school
  def school_dns=(_dn)
    write_raw(:puavoSchool, Array(_dn))
    write_raw(:gidNumber, Array(School.by_dn(Array(_dn)[0]).gid_number.to_s))
  end

  def username=(_username)
    write_raw(:uid, Array(_username))
    write_raw(:cn, Array(_username))

    # Initial home directory in the "new" format
    write_raw(:homeDirectory, Array("/home/#{username}"))
  end

  def email=(_email)
    secondary_emails = Array(get_raw(:mail))[1..-1] || []
    write_raw(:mail, [_email] + secondary_emails)
    @cache[:email] = nil
  end

  def secondary_emails=(emails)
    primary = Array(get_raw(:mail)).first
    val = ([primary] + emails).compact
    write_raw(:mail, val)
    @cache[:secondary_emails] = nil
  end

  def is_school_admin_in?(school)
    admin_of_school_dns.include?(school.dn.downcase)
  end

  def roles_within_school(school)
    _roles = roles
    if is_school_admin_in?(school)
      _roles.push("schooladmin")
    end
    _roles
  end

  def legacy_roles
    LegacyRole.by_attr(:member_dns, dn, :multiple => true)
  end

  # XXX: deprecated!
  computed_attr :user_type
  def user_type
    roles.first
  end

  computed_attr :puavo_id
  def puavo_id
    id
  end

  computed_attr :unique_id
  def unique_id
    dn.downcase
  end

  def self.ldap_base
    "ou=People,#{ organisation["base"] }"
  end

  # Find user model by username
  #
  # @param [String] username
  # @return [String, nil]
  def self.by_username(username, options={})
    by_attr(:username, username, options)
  end

  # Find user model by username
  #
  # @param [String] username
  # @return [String]
  def self.by_username!(username, options={})
    by_attr!(:username, username, options)
  end


  # Find dn string for username
  #
  # @param [String] username
  # @return [String, nil]
  def self.resolve_dn(username)
    user = by_attr(:username, username, :attrs => [:dn])
    user ? user.dn : nil
  end

  def self.profile_image(uid)
    data = raw_filter(ldap_base, "(uid=#{ escape uid })", ["jpegPhoto"])
    if !data || data.size == 0
      raise NotFound, :user => "Cannot find image data for user: #{ uid }"
    end

    data.first["jpegPhoto"]
  end

  def organisation
    User.organisation
  end

  computed_attr :organisation_domain
  def organisation_domain
    organisation.domain
  end

  computed_attr :organisation_name
  def organisation_name
    organisation.name
  end

  computed_attr :school_dn
  def school_dn
    Array(school_dns).first
  end

  # Primary school
  def school
    return @school if @school
    return if school_dn.nil?
    @school = School.by_dn(school_dn)
  end

  computed_attr :primary_school_id
  def primary_school_id
    school.id if school
  end

  def schools
    # TODO: handle errors
    @schools ||= school_dns.map do |dn|
      School.by_dn(dn)
    end.compact
  end

  def import_school_name
    school.name
  end

  def preferred_language
    if get_own(:preferred_language).nil? && school
      school.preferred_language
    else
      get_own(:preferred_language)
    end
  end

  def locale
    if get_own(:locale).nil? && school
      school.locale
    else
      get_own(:locale)
    end
  end

  def timezone
    if get_own(:timezone).nil? && school
      school.timezone
    else
      get_own(:timezone)
    end
  end

  def admin?
    user_type == "admin"
  end

  def groups
    @groups ||= Group.by_user_dn(dn)
  end

  def import_group_name
    return "" if groups.empty?
    return groups.first.name
  end

  def groups_within_school(school)
    groups.select do |group|
        group.school_id == school.id
    end
  end

  computed_attr :domain_username
  def domain_username
    "#{ username }@#{ organisation.domain }"
  end

  computed_attr :homepage
  def homepage
    if school
      school.homepage
    end
  end

  computed_attr :external_domain_username
  def external_domain_username
    return nil unless CONFIG.has_key?("external_domain")
    return nil if CONFIG["external_domain"].class != Hash
    return nil unless CONFIG["external_domain"].has_key?(organisation.organisation_key)

    "#{ username }@#{ CONFIG["external_domain"][organisation.organisation_key] }"
  end

  def server_user?
    dn == CONFIG["server"][:dn]
  end

  computed_attr :schools_hash, :schools
  def schools_hash
    schools.map do |school|
        {
          "id" => school.id,
          "dn" => school.dn,
          "name" => school.name,
          "abbreviation" => school.abbreviation,
          "roles" => roles_within_school(school),
          "groups" => groups_within_school(school).map do |group|
            {
              "id" => group.id,
              "dn" => group.dn,
              "name" => group.name,
              "abbreviation" => group.abbreviation,
              "type" => group.type
            }
          end
        }
    end
  end

  def self.current
    return settings[:credentials_cache][:current_user] if settings[:credentials_cache][:current_user]

    user_credentials = settings[:credentials]

    if user_credentials[:dn]
      user = User.by_dn(user_credentials[:dn])
    elsif user_credentials[:username]
      user = User.by_username(user_credentials[:username])
    end

    settings[:credentials_cache][:current_user] = user
  end

  def self.search_filters
    [
      create_filter_lambda(:username),
      create_filter_lambda(:first_name),
      create_filter_lambda(:last_name),
      create_filter_lambda(:email)
    ]
  end

  def group_by_type(type, options={})
    Group.by_attrs({ :member_dns => self.dn,
                     :type => type },
                   options )
  end

  def administrative_groups
    self.group_by_type('administrative group', { :multiple => true })
  end

  def administrative_groups=(group_ids)
    groups = Group.administrative_groups
    groups.each do |group|
      if group_ids.include?(group.id.to_s)
        unless group.member_dns.include?(self.dn)
          group.add_member(self)
          group.save!
        end
      else
        if group.member_dns.include?(self.dn)
          group.remove_member(self)
          group.save!
        end
      end
    end
  end

  def add_administrative_group(group)
    unless group.member_dns.include?(self.dn)
      group.add_member(self)
      group.save!
    end
  end

  def teaching_group
    self.group_by_type('teaching group')
  end

  def import_group_external_id
    group = self.group_by_type('teaching group')
    unless group.nil?
      group.external_id
    end
  end

  def teaching_group=(group)
    self.group_by_type('teaching group', { :multiple => true }).each do |g|
      next if group && g.id == group.id

      g.remove_member(self)
      g.save!
    end

    return if group.nil?

    unless group.member_dns.include?(self.dn)
      group.add_member(self)
      group.save!
    end
  end

  def year_class
    self.group_by_type('year class')
  end

  def year_class=(group)
    need_add_group = true
    self.group_by_type('year class', { :multiple => true }).each do |g|
      if g.external_id != group.external_id
        g.remove_member(self)
        g.save!
      else
        need_add_group = false
      end
    end

    if need_add_group
      group.add_member(self)
      group.save!
    end
  end

  def check_if_changed_attributes(new_userinfo)
    old_userinfo = self.to_hash

    new_userinfo.each do |attribute, new_value|
      if attribute == 'password' then
        begin
          conn = LdapModel.dn_bind(self.dn, new_userinfo['password'])
          conn.unbind
        rescue LDAP::ResultError => e
          # XXX how to check for Net::LDAP::ResultCodeInvalidCredentials
          # XXX instead of checking for the human readable message?
          if e.message == 'Invalid credentials' then
            # password has changed
            return true
          end
          raise e
        end

        next
      end

      # "roles"-attribute needs special handling because of role/group changes
      if attribute == 'roles' && !old_userinfo.has_key?('roles') then
        old_value = [ old_userinfo['user_type'] ]
      else
        old_value = old_userinfo[attribute]
      end

      if old_value != new_value then
        return true
      end
    end

    return false
  end

  def mark_for_removal!
    mark_set = false

    # ALWAYS setup up password to some random value for users that are
    # marked for removal.  This may seem odd, but we should guard against
    # the case where a user complains about login not working and subsequently
    # admin has changed the puavo password to something known to make the
    # account work, despite it being "marked for removal".
    self.password = SecureRandom.hex(128)

    if self.removal_request_time.nil? then
      self.removal_request_time = Time.now.utc.to_datetime
      mark_set = true
    end

    self.save!

    return mark_set
  end

  private

  # Add this user to the given school. Private method. This is used on {#save!}
  # when `school_dns` is manipulated. See {#remove_from_school!}
  #
  # @param school [School]
  def add_to_school!(school)
    if !school.member_usernames.include?(username)
      school.add(:member_usernames, username)
    end

    if !school.member_dns.include?(dn)
      school.add(:member_dns, dn)
    end

    school.save!
  end

  # @param school [School] Remove this user from the given school
  def remove_from_school!(school)
    if school.member_usernames.include?(username)
      school.remove(:member_usernames, username)
    end

    if school.member_dns.include?(dn)
      school.remove(:member_dns, dn)
    end
    school.save!
  end

  # Write internal samba attributes. Implementation is based on the puavo-web
  # code is not actually tested on production systems
  def write_samba_attrs
    set_samba_sid

    write_raw(:sambaAcctFlags, ["[U]"])
    if school
      set_samba_primary_group_sid(school.id)
    end

  end

end

class Users < PuavoSinatra
  DIR = File.expand_path(File.dirname(__FILE__))
  ANONYMOUS_IMAGE_PATH = DIR + "/anonymous.png"


  post "/v3/users" do
    auth :basic_auth, :kerberos
    user = User.new(json_params)
    user.save!
    json user
  end

  post "/v3/users_validate" do
    auth :basic_auth, :kerberos
    user = User.new(json_params)
    user.validate!
    json user
  end

  put '/v3/users/password' do
    auth :basic_auth

    begin
      param_names_list = %w(actor_dn
                            actor_username
                            actor_password
                            host
                            mode
                            target_user_username
                            target_user_password)

      param_names_list.each do |param_name|
        case param_name
          when 'actor_dn', 'actor_username'
            param_ok = params[param_name].kind_of?(String) \
                         || params[param_name].nil?
          when 'mode'
            param_ok = params[param_name] == 'all'                \
                         || params[param_name] == 'no_upstream'   \
                         || params[param_name] == 'upstream_only'
          else
            param_ok = params[param_name].kind_of?(String) \
                         && !params[param_name].empty?
        end

        raise "'#{ param_name }' parameter is not set or is of wrong type" \
          unless param_ok
      end

      if params['actor_dn'].to_s.empty? \
           && params['actor_username'].to_s.empty? then
        raise 'either actor_dn or actor_username parameter must be set'
      end
    rescue StandardError => e
      # XXX maybe log errors?
      return json({
        :exit_status => 1,
        :stderr      => e.message,
        :stdout      => '',
      })
    end

    res = Puavo.change_passwd(params['mode'].to_sym,
                              params['host'],
                              params['actor_dn'],
                              params['actor_username'],
                              params['actor_password'],
                              params['target_user_username'],
                              params['target_user_password'])

    target_user_username = params['target_user_username']
    msg = (res[:exit_status] == 0)                                       \
            ? "changed password for '#{ target_user_username }'"         \
            : "changing password failed for '#{ target_user_username }'"

    flog.info('PUT /v3/users/password called', msg, res)

    return json(res)
  end

  get "/v3/users/_search" do
    auth :basic_auth, :kerberos
    json User.search(params["q"])
  end

  # Return users in a organisation
  get "/v3/users" do
    auth :basic_auth, :kerberos

    attrs = nil
    if params["attributes"]
      attrs = params["attributes"].split(",").map{|s| s.strip }
    end

    # XXX cannot combine filters
    if params["email"]
      json User.by_attr(:email, params["email"], :multiple => true, :attrs => attrs)
    elsif params["id"]
      json User.by_attr(:id, params["id"], :multiple => true, :attrs => attrs)
    else
      users = User.all(:attrs => attrs)
      json users
    end

  end

  # Return users in a organisation
  get "/v3/users/_by_id/:id" do
    auth :basic_auth, :kerberos

    json User.by_id!(params["id"])
  end

  # Return users in a organisation
  get "/v3/users/:username" do
    auth :basic_auth, :kerberos

    json User.by_username!(params["username"], :attrs => params["attributes"])
  end

  post "/v3/users/:username" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])
    user.update!(json_params)
    user.save!
    json user

  end

  # Replace all legacy roles for user in one request
  # Example:
  #
  #   curl -u albus:albus -H "host: hogwarts.opinsys.net" -H "content-type: application/json" -X PUT -d '{"ids": [49937, 50164]}' http://localhost:9292/v3/users/bob/legacy_roles
  #
  #
  put "/v3/users/:username/legacy_roles" do
    auth :basic_auth, :kerberos

    user = User.by_username!(params["username"])
    new_legacy_roles = json_params["ids"].map do |id|
      LegacyRole.by_attr!(:id, id)
    end

    current_legacy_roles = LegacyRole.by_attr(:member_dns, user.dn, :multiple => true)

    current_legacy_roles.each do |r|
      r.remove_member(user)
      r.save!
    end


    new_legacy_roles.each do |r|
      r.add_member(user)
      r.save!
    end

    json new_legacy_roles

  end

  put "/v3/users/:username/groups" do
    auth :basic_auth, :kerberos

    user = User.by_username!(params["username"])
    new_groups = json_params["ids"].map do |id|
      Group.by_attr!(:id, id)
    end

    current_groups = Group.by_attr(:member_dns, user.dn, :multiple => true)

    current_groups.each do |r|
      r.remove_member(user)
      r.save!
    end


    new_groups.each do |r|
      r.add_member(user)
      r.save!
    end

    json new_groups
  end

  get "/v3/users/:username/teaching_group" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])
    json user.teaching_group
  end

  put "/v3/users/:username/teaching_group" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])
    group = Group.by_id(params["id"])
    user.teaching_group = group
    json group
  end

  get "/v3/users/:username/administrative_groups" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])
    json user.administrative_groups
  end

  put "/v3/users/:username/administrative_groups" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])
    json user.administrative_groups = json_params["ids"]
  end

  get "/v3/users/:username/legacy_roles" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])
    json user.legacy_roles
  end


  get "/v3/users/:username/profile.jpg" do
    auth :basic_auth, :kerberos
    content_type "image/jpeg"

    image = User.profile_image(params["username"])
    if image
      image
    else
      File.open(ANONYMOUS_IMAGE_PATH, "r") { |f| f.read }
    end
  end

  get "/v3/whoami" do
    auth :basic_auth, :kerberos
    user = User.current.to_hash
    json user.merge("organisation" => LdapModel.organisation.to_hash)
  end

end
end

