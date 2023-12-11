require_relative "../lib/password"
require_relative "../lib/samba_attrs"

require_relative '../lib/eltern.rb'

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
  ldap_map :mail, :email, LdapConverters::ArrayValue
  ldap_map :puavoSchool, :school_dns, LdapConverters::ArrayValue
  ldap_map :puavoEduPersonPrimarySchool, :primary_school_dn, LdapConverters::SingleValue
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
  ldap_map :telephoneNumber, :telephone_number, LdapConverters::ArrayValue
  ldap_map :puavoRemovalRequestTime, :removal_request_time,
           LdapConverters::TimeStamp
  ldap_map :eduPersonPrincipalName, :edu_person_principal_name
  ldap_map :puavoDoNotDelete, :do_not_delete
  ldap_map :sambaPwdLastSet, :password_last_set, LdapConverters::Number
  ldap_map :puavoAdminPermissions, :admin_permissions, LdapConverters::ArrayValue

  ldap_map :puavoLearnerId, :learner_id

  ldap_map :puavoVerifiedEmail, :verified_email, LdapConverters::ArrayValue
  ldap_map :puavoPrimaryEmail, :primary_email

  # The classic Roles in puavo-web are now deprecated.
  # puavoEduPersonAffiliation will used as the roles from now on
  ldap_map :puavoEduPersonAffiliation, :roles, LdapConverters::ArrayValue

  ldap_map :puavoUuid, :uuid, LdapConverters::SingleValue
  ldap_map :puavoMFAEnabled, :mfa_enabled, LdapConverters::StringBoolean

  ldap_map :puavoLicenses, :licenses

  skip_serialize :external_data

  # List of school DNs where the user is school admin
  ldap_map(:puavoAdminOfSchool, :admin_of_school_dns) do |dns|
    Array(dns).map do |dn|
      dn
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

    auto_email, domain = get_automatic_email(User.current.organisation_name)

    if auto_email
      mail = "#{self.username}@#{domain}"

      if self.email != mail
        # FIXME: This will fail if the email address has been verified and it changes.
        write_raw(:mail, [mail])
      end
    end
  end

  before :destroy do
    # Currently "delete_kerberos_principal" updates the user entry on ldap,
    # which might affect associations, so do this first and only then
    # delete all associations.
    delete_kerberos_principal
    delete_all_associations
    reset_sso_session
  end

  before :update do
    new_username = username
    old_username = @previous_values[:username]
    if old_username && old_username != new_username then
      # Store the previous groups in a special variable, so we can restore them
      # after the renaming
      @previous_groups = self.groups.collect { |g| g.dn }

      # We need to update associations if username has changed, but must use
      # the old username when deleting.
      self.username = old_username
      delete_all_associations
      self.username = new_username
      self.edu_person_principal_name \
        = "#{ username }@#{ organisation.puavo_kerberos_realm }"
    end

    # For some reason, we store school admin states in two separate places: in the
    # user object and in the school object(s). If you remove an user from a school,
    # then remove the removed school DNs from the user admin array.
    new_admin = []

    self.admin_of_school_dns.each do |dn|
      new_admin << dn if self.school_dns.include?(dn)
    end

    self.admin_of_school_dns = new_admin

    # Then we hope that remove_from_school below will remove the other associations...

    self.uuid = SecureRandom.uuid if self.uuid.nil?

    reset_sso_session
  end

  def validate
    if username.to_s.strip.empty?
      add_validation_error(:username, :username_empty, "Username is empty")
    else
      validate_unique(:username)

      if BANNED_USERNAMES.include?(username)
        add_validation_error(:username, :username_not_allowed, "Username not allowed")
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

    unless telephone_number.nil?
      if Array(telephone_number || []).collect{ |n| !n.match(/^[A-Za-z[:digit:][:space:]'()+,-.\/:?"]+$/) }.any?
        add_validation_error(:telephone_number, :telephone_number_invalid,
                             "Invalid telephone number. Allowed characters: A-Z, a-z, 0-9, ', (, ), +, ,, -, ., /, :, ?, space and \"")
      end

      # I'm not touching that regexp above
      Array(telephone_number || []).each do |n|
        if n.strip == '-'
          add_validation_error(:telephone_number, :telephone_number_invalid,
                               "A telephone number cannnot be just a '-'")
        end
      end
    end

    # FIXME: Validate external id?
    if !external_id.nil?
      validate_unique(:external_id)
    end

    validate_unique(:email)

    # Ensure there are no validated email addresses that don't appear in the emails array
    unless (Array(self.verified_email) - Array(self.email)).empty?
      add_validation_error(:verified_email, :invalid_verified_address,
                           "the verified emails array contains an address that isn't in the normal email addresses array")
    end

    # Validate the primary email address
    if self.primary_email && !Array(self.verified_email).include?(self.primary_email)
      add_validation_error(:primary_email, :invalid_primary_email,
                           'the primary email address must be in the verified emails array')
    end

    # Set/validate the primary school DN. If it's unset (for example, when creating a new user)
    # then we can fix it automagically if there's only one school.
    all_schools = Array(school_dns)

    if self.primary_school_dn.nil?
      if all_schools.count == 1
        self.primary_school_dn = all_schools[0]
      else
        add_validation_error(:primary_school_dn, :primary_school_dn_unset,
                             "primary_school_dn is unset and the user has multiple (#{all_schools.count}) schools")
      end
    else
      unless all_schools.include?(self.primary_school_dn)
        add_validation_error(:primary_school_dn, :primary_school_dn_not_valid,
                             "primary_school_dn points to a school that isn't in the school_dns array")
      end
    end
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

    if locked.nil? then
      self.locked = false
    end

    self.uuid = SecureRandom.uuid

    validate_unique(:uid_number)
    validate_unique(:id)
    assert_validation

    write_samba_attrs
  end

  def delete_kerberos_principal
    # XXX We should really destroy the kerberos principal for this user,
    # XXX but for now we just set a password to some unknown value
    # XXX so that the kerberos principal can not be used.
    # XXX This also invalidates downstream passwords.
    change_user_password(:no_upstream, SecureRandom.hex(128))
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

    # Remove from school admin DNs (the user is not a member in these schools, but they admin
    # them). This is a clumsy and slow loop, but I don't know what else to do.
    self.admin_of_school_dns.each do |dn|
      begin
        school = School.by_dn(dn)

        # Because some values are cached, it is possible this array has already been cleaned
        # by remove_from_school! above, so we must do an extra check. Otherwise there will
        # be exceptions.
        if school.school_admin_dns.include?(self.dn)
          school.remove(:school_admin_dns, self.dn)
          school.save!
        end
      rescue StandardError => e
        $rest_log.error e
      end
    end

    # There are so many moving parts here that I don't know if this is
    # how the cleanup should be done :-(
  end

  # Just store password locally and handle it in after hook
  def password=(pw)
    @password = pw
  end

  def change_user_password(mode, password=nil)
    @password = password if password

    return if @password.nil?

    begin
      Puavo.change_passwd(mode,
                          CONFIG['ldap'],
                          LdapModel.settings[:credentials][:dn],
                          User.current.username,
                          LdapModel.settings[:credentials][:password],
                          username,
                          @password,
                          '???')        # no request ID
    ensure
      @password = nil
    end
  end

  after :create, :update do
    change_user_password(:all)
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

    # Restore previous groups. self.groups cannot be relied here. @previous_groups was
    # set in "before :update" handler above. It's currently not set anywhere else.
    if @previous_groups
      @previous_groups.each do |dn|
        begin
          group = PuavoRest::Group.by_dn(dn)
          group.add_member(self)
          group.save!
        rescue => e
          $rest_log.error("Can't put the renamed user back to group \"#{dn}\": #{e}")
        end
      end
    end
  end

  after :create do
    schools.each { |s| add_to_school!(s) }
  end

  def reset_sso_session
    # TODO: Implement this. It's harder than it looks.
  end

  def home_directory=(value)
    add_validation_error(:home_directory, :read_only, "home_directory is read only")
  end

  def telephone_number=(value)
    # Treat empty strings as nil and allow the number to be cleared.
    # This is extremely important, for example, in Primus import. Old
    # phone numbers must be cleared if they're missing.
    if !value.nil? && (value.empty? || value.to_s.strip == "")
      value = nil
    end

    write_raw(:telephoneNumber, transform(:telephone_number, :write, value))
  end

  # Fix the gid number when moving user to another school
  def school_dns=(_dn)
    write_raw(:puavoSchool, Array(_dn))

    if primary_school_dn
      # Unfortunately it is not possible to validate the DN here. It can be momentarily
      # invalid before it gets fixed, or it could have been left to an invalid value
      # accidentally. There just is no way for us to know here.
      write_raw(:gidNumber, [School.by_dn(primary_school_dn).gid_number.to_s])
    else
      # Let's hope for the best...
      write_raw(:gidNumber, Array(School.by_dn(Array(_dn)[0]).gid_number.to_s))
    end
  end

  def username=(_username)
    write_raw(:uid, Array(_username))
    write_raw(:cn, Array(_username))

    # The posixAccount class *requires* this, so we have to set it. It's not used for anything.
    write_raw(:homeDirectory, Array("/home/#{username}"))
  end

  def clean_up_email_array(a)
    (a.nil? || a.empty?) ? [] : \
      Array(a)
      .compact                  # remove nil values
      .map { |e| e.strip }      # remove trailing and leading whitespace
      .reject { |e| e.empty? }  # remove completely empty strings
      .uniq                     # remove duplicates
  end

  def email=(_email)
    write_raw(:mail, clean_up_email_array(_email))
  end

  def verified_email=(_verified)
    write_raw(:puavoVerifiedEmail, clean_up_email_array(_verified))
  end

  def learner_id=(lid)
    if lid.nil? || lid.to_s.strip.empty?
      # Ensure empty strings stay as nils (or empty arrays, LDAP is weird)
      value = []
    else
      value = [lid.strip]
    end

    write_raw(:puavoLearnerId, value)
  end

  def is_school_admin_in?(school)
    admin_of_school_dns.include?(school.dn)
  end

  def roles_within_school(school)
    _roles = roles.dup    # dup because we modify the array
    if is_school_admin_in?(school)
      _roles.push("schooladmin")
    end
    _roles
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
    dn
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

  # The "raw" version of by_username. No objects here, just raw data,
  # with the attributes you wanted.
  def self.by_username_raw_attrs(username, attributes)
    raw_filter(ldap_base(), "(uid=#{ LdapModel.ldap_escape(username) })", attributes)
  end

  def self.by_id_raw_attrs(id, attributes)
    raw_filter(ldap_base(), "(puavoId=#{ LdapModel.ldap_escape(id) })", attributes)
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
    data = raw_filter(ldap_base, "(uid=#{ LdapModel.ldap_escape(uid) })", ["jpegPhoto"])
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
    primary_school_dn
  end

  # Primary school
  def school
    return @school if @school

    # This method is sometimes called before the object has been fully constructed, so
    # the school DN array hasn't been populated yet. Crazy, but it does happen. For
    # example, almost all of the REST user tests will fail without this check.
    return if school_dns.nil? || school_dns.empty?

    all_schools = Array(self.school_dns)
    dn = primary_school_dn

    if dn.nil?
      if all_schools.count == 1
        dn = all_schools[0]
      else
        raise InternalError, "user #{self.username} has multiple schools but no primary school DN"
      end
    end

    # TODO: reuse the schools array, it already exists
    @school = School.by_dn(dn)
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
    Array(roles).include?('admin')
  end

  def groups
    @groups ||= Group.by_user_dn(dn)
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
    # Inject the materials charge value into the schools array, at the correct school
    mpass_charging_state = nil
    mpass_charging_school = nil

    if roles.include?('student') && external_data
      begin
        ed = JSON.parse(external_data)
      rescue
        ed = {}
      end

      if ed.include?('materials_charge')
        parts = ed['materials_charge'].split(';')
        mpass_charging_state = parts[0]
        mpass_charging_school = parts[1]
      end
    end

    out = []

    schools.each do |school|
      s = {
        "id" => school.id,
        "dn" => school.dn,
        "name" => school.name,
        "abbreviation" => school.abbreviation,
        "school_code" => school.school_code,
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

      if mpass_charging_school && school.school_code == mpass_charging_school
        s['learning_materials_charge'] = mpass_charging_state
      end

      out << s
    end

    return out
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

  # Called when User.to_hash is called
  computed_attr :year_class_hash, :year_class
  def year_class_hash
    grp = self.group_by_type('year class')
    grp.nil? ? nil : grp.name
  end

  def year_class
    return nil unless self.roles.include?('student')

    yc = Array(self.group_by_type('year class'))
    return nil if yc.nil? || yc.first.nil?
    return yc.first
  end

  def year_class=(group)
    return unless self.roles.include?('student')

    self.group_by_type('year class', { :multiple => true }).each do |g|
      if g.abbreviation != group.abbreviation
        g.remove_member(self)
        g.save!
      end
    end

    unless group.member_usernames.include?(username)
      group.add_member(self)
      group.save!
    end
  end

  def year_class_changed?(group)
    return false unless self.roles.include?('student')

    self.group_by_type('year class', { :multiple => true }).each do |g|
      if g.abbreviation != group.abbreviation
        # It doesn't matter how many wrong year classes this user
        # is a member of, we need just one to trigger an update
        return true
      end
    end

    unless group.member_usernames.include?(username)
      return true
    end

    return false
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

      old_value = old_userinfo[attribute]
      if old_value != new_value then
        return true
      end
    end

    return false
  end

  def mark_for_removal!
    self.locked = true

    mark_set = false

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

    if school.school_admin_dns.include?(dn)
      school.remove(:school_admin_dns, dn)
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
  include PuavoRest::ElternHelpers

  DIR = File.expand_path(File.dirname(__FILE__))
  ANONYMOUS_IMAGE_PATH = DIR + "/anonymous.png"


  post "/v3/users" do
    auth :basic_auth, :kerberos

    # You can't add/edit verified email addresses directly
    parameters = json_params
    parameters.delete('verified_email')
    parameters.delete('primary_email')

    user = User.new(parameters)
    user.save!
    json user
  end

  post "/v3/users_validate" do
    auth :basic_auth, :kerberos
    user = User.new(json_params)
    user.validate!
    json user
  end

  delete '/v3/users/:username' do
    auth :basic_auth, :kerberos

    user = User.by_username!(params['username'])

    uname = LdapModel.settings.dig(:credentials, :username)

    if uname && user.username == uname
      return 403, 'you cannot self-terminate'
    end

    # This check is here because I don't know how to remove organisation owners
    # with puavo-rest. And owners usually should be left alone.
    if user.organisation.owners.collect { |o| o[:dn] }.include?(user.dn)
      return 403, 'refusing to delete an organisation owner'
    end

    if user.do_not_delete && user.do_not_delete == 'TRUE'
      return 403, 'user deletion has been prevented'
    end

    user.destroy!

    return 200
  end

  put '/v3/users/password' do
    # Permit localhost by default (for testing purposes), but all other IPs
    # must be explicitly allowed
    unless request.ip == "127.0.0.1" || CONFIG.fetch("allow_password_changes_from", []).include?(request.ip)
      request_id = json_params.fetch('request_id', nil)

      $rest_log.error("[#{request_id}] got a PUT /v3/users/password from unauthorized IP address \"#{request.ip}\"")

      return json({
        :exit_status => 1,
        :stderr      => 'your password change request came from an unauthorized IP address',
        :stdout      => '',
        :sync_status => 'unauthorized',
        :request_id  => request_id,
      })
    end

    auth :basic_auth

    request_id = nil

    # validate the request parameters
    begin
      param_names_list = %w(actor_dn
                            actor_username
                            actor_password
                            host
                            mode
                            target_user_username
                            target_user_password
                            request_id)

      unless json_params.include?('request_id')
        $rest_log.error("got a PUT /v3/users/password without \"request_id\" in the parameters, ignoring")

        return json({
          :exit_status => 1,
          :stderr      => "missing 'request_id' from the request parameters",
          :stdout      => '',
          :sync_status => 'bad_request',
          :request_id  => '?',
        })
      end

      request_id = json_params['request_id']

      param_names_list.each do |param_name|
        case param_name
          when 'actor_dn', 'actor_username'
            param_ok = json_params[param_name].kind_of?(String) \
                         || json_params[param_name].nil?
          when 'mode'
            param_ok = json_params[param_name] == 'all'                \
                         || json_params[param_name] == 'no_upstream'   \
                         || json_params[param_name] == 'upstream_only'
          else
            param_ok = json_params[param_name].kind_of?(String) \
                         && !json_params[param_name].empty?
        end

        raise "'#{ param_name }' parameter is not set or is of wrong type" \
          unless param_ok
      end

      if json_params['actor_dn'].to_s.empty? \
           && json_params['actor_username'].to_s.empty? then
        raise 'either actor_dn or actor_username parameter must be set'
      end
    rescue StandardError => e
      $rest_log.error("[#{request_id}] #{e}")

      return json({
        :exit_status => 1,
        :stderr      => e.message,
        :stdout      => '',
        :sync_status => 'bad_request',
        :request_id  => request_id,
      })
    end

    $rest_log.info(
      "[#{request_id}] \"PUT /v3/users/password\" starting " \
      "for user \"#{json_params['target_user_username']}\""
    )

    res = Puavo.change_passwd(json_params['mode'].to_sym,
                              json_params['host'],
                              json_params['actor_dn'],
                              json_params['actor_username'],
                              json_params['actor_password'],
                              json_params['target_user_username'],
                              json_params['target_user_password'],
                              request_id)

    res[:request_id] = request_id

    target_user_username = json_params['target_user_username']

    msg = "[#{request_id}] \"PUT /v3/users/password\" finished for user " \
          "\"#{json_params['target_user_username']}\", exit status is " \
          "#{res[:exit_status]}"

    if res[:exit_status] == 0
      $rest_log.info(msg)
    else
      $rest_log.error(msg)
    end

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

    parameters = json_params

    # This cannot be edited. It should be immutable.
    parameters.delete('uuid')

    # You can't add/edit verified email addresses directly
    parameters.delete('verified_email')
    parameters.delete('primary_email')

    # You're unlikely to have write access to this attribute anyway
    parameters.delete('mfa_enabled')

    user.update!(parameters)
    user.save!
    json user

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

  get "/v3/users/:username/year_class" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])
    json user.year_class
  end

  put "/v3/users/:username/external_data" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])

    data = request.body.read.to_s

    if data.nil? || data.strip.empty?
      # empty string clears the data
      user.external_data = nil
    else
      # ensure it's valid JSON
      begin
        JSON.parse(data)
      rescue StandardError => e
        $rest_log.error("can't set external data for user \"#{params["username"]}\" because the JSON is not valid: #{e}")
        return 400, 'user external data must be either an empty string (to clear it), or valid JSON'
      end

      user.external_data = data
    end

    user.save!
    return 200
  end

  get "/v3/users/:username/mark_for_deletion" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])
    json user.removal_request_time
  end

  put "/v3/users/:username/mark_for_deletion" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])

    uname = LdapModel.settings.dig(:credentials, :username)

    if uname && user.username == uname
      return 403, 'you cannot mark yourself for deletion'
    end

    if user.do_not_delete.nil?
      if user.removal_request_time.nil?
        # This call cannot change an already set time
        user.removal_request_time = Time.now.utc
        user.save!
      end
    end
  end

  delete "/v3/users/:username/mark_for_deletion" do
    auth :basic_auth, :kerberos
    user = User.by_username!(params["username"])

    if user.do_not_delete.nil?
      unless user.removal_request_time.nil?
        user.removal_request_time = nil
        user.save!
      end
    end
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

    user = User.current
    organisation = LdapModel.organisation

    json({
      id: user.id,
      dn: user.dn.to_s,
      first_name: user.first_name,
      last_name: user.last_name,
      username: user.username,
      organisation_name: organisation.name,
      organisation_domain: organisation.domain,
    })
  end


  # -------------------------------------------------------------------------------------------------
  # -------------------------------------------------------------------------------------------------
  # EXPERIMENTAL V4 API

  # Use at your own risk. Currently read-only.


  # Maps "user" field names to LDAP attributes. Used when searching for data, as only
  # the requested fields are actually returned in the queries.
  USER_TO_LDAP = {
    'admin_school_id'    => 'puavoAdminOfSchool',
    'created'            => 'createTimestamp',  # LDAP operational attribute
    'dn'                 => 'dn',
    'do_not_delete'      => 'puavoDoNotDelete',
    'email'              => 'mail',
    'external_id'        => 'puavoExternalId',
    'external_data'      => 'puavoExternalData',
    'first_names'        => 'givenName',
    'gid_number'         => 'gidNumber',
    'id'                 => 'puavoId',
    'last_name'          => 'sn',
    'learner_id'         => 'puavoLearnerId',
    'licenses'           => 'puavoLicenses',
    'locale'             => 'puavoLocale',
    'locked'             => 'puavoLocked',
    'mfa_enabled'        => 'puavoMFAEnabled',
    'modified'           => 'modifyTimestamp',  # LDAP operational attribute
    'personnel_number'   => 'puavoEduPersonPersonnelNumber',
    'phone'              => 'telephoneNumber',
    'preferred_language' => 'preferredLanguage',
    'primary_school_id'  => 'puavoEduPersonPrimarySchool',
    'removal_mark_time'  => 'puavoRemovalRequestTime',
    'role'               => 'puavoEduPersonAffiliation',
    'school_ids'         => 'puavoSchool',
    'ssh_public_key'     => 'puavoSshPublicKey',
    'uid_number'         => 'uidNumber',
    'username'           => 'uid',
    'uuid'               => 'puavoUuid',
  }

  # Maps LDAP attributes back to "user" fields and optionally specifies a conversion type
  LDAP_TO_USER = {
    'createTimestamp'               => { name: 'created', type: :ldap_timestamp },
    'dn'                            => { name: 'dn' },
    'gidNumber'                     => { name: 'gid_number', type: :integer },
    'givenName'                     => { name: 'first_names' },
    'mail'                          => { name: 'email' },
    'modifyTimestamp'               => { name: 'modified', type: :ldap_timestamp },
    'preferredLanguage'             => { name: 'preferred_language' },
    'puavoAdminOfSchool'            => { name: 'admin_school_id', type: :id_from_dn },
    'puavoDoNotDelete'              => { name: 'do_not_delete', type: :boolean },
    'puavoEduPersonAffiliation'     => { name: 'role' },
    'puavoEduPersonPersonnelNumber' => { name: 'personnel_number' },
    'puavoEduPersonPrimarySchool'   => { name: 'primary_school_id', type: :id_from_dn },
    'puavoExternalId'               => { name: 'external_id' },
    'puavoExternalData'             => { name: 'external_data', type: :json },
    'puavoId'                       => { name: 'id', type: :integer },
    'puavoLearnerId'                => { name: 'learner_id' },
    'puavoLicenses'                 => { name: 'licenses', type: :json },
    'puavoLocale'                   => { name: 'locale' },
    'puavoLocked'                   => { name: 'locked', type: :boolean },
    'puavoMFAEnabled'               => { name: 'mfa_enabled', type: :boolean },
    'puavoRemovalRequestTime'       => { name: 'removal_mark_time', type: :ldap_timestamp },
    'puavoSchool'                   => { name: 'school_ids', type: :id_from_dn },
    'puavoSshPublicKey'             => { name: 'ssh_public_key' },
    'puavoUuid'                     => { name: 'uuid' },
    'sn'                            => { name: 'last_name' },
    'telephoneNumber'               => { name: 'phone' },
    'uid'                           => { name: 'username' },
    'uidNumber'                     => { name: 'uid_number', type: :integer },
  }

  def v4_do_user_search(filters, requested_ldap_attrs)
    base = "ou=People,#{Organisation.current['base']}"
    filter_string = v4_combine_filter_parts(filters)

    return User.raw_filter(base, filter_string, requested_ldap_attrs)
  end

  # Retrieve all (or some) users in the organisation
  # GET /v4/users?fields=...
  get '/v4/users' do
    auth :basic_auth, :kerberos

    raise Unauthorized, :user => nil unless v4_is_request_allowed?(User.current)

    if params.include?('no_eltern')
      # Explicitly disable Eltern processing for this request
      do_eltern = false
    else
      # Handle supplementary Eltern data if the domain matches
      do_eltern = CONFIG['eltern_users'] &&
                  Array(CONFIG['eltern_users']['domains']).include?(Organisation.current.domain)
    end

    v4_do_operation do
      # which fields to get?
      user_fields = v4_get_fields(params).to_set
      user_fields << 'id' if do_eltern

      ldap_attrs = v4_user_to_ldap(user_fields, USER_TO_LDAP)

      # optional filters
      filters, puavoid = v4_get_filters_from_params(params, USER_TO_LDAP)

      # do the query
      raw = v4_do_user_search(filters, ldap_attrs)

      # convert and return
      out = v4_ldap_to_user(raw, ldap_attrs, LDAP_TO_USER)

      get_parents(out, puavoid) if do_eltern

      out = v4_ensure_is_array(out, 'role', 'email', 'phone', 'admin_school_id', 'school_ids')

      return 200, json({
        status: 'ok',
        error: nil,
        data: out,
      })
    end
  end

end
end
