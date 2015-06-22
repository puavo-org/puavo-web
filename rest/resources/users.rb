require_relative "../lib/ldappasswd"

module PuavoRest

class User < LdapModel

  ldap_map :dn, :dn
  ldap_map :puavoId, :id, LdapConverters::Number
  ldap_map :objectClass, :object_classes, LdapConverters::ArrayValue
  ldap_map :uid, :username
  ldap_map :uidNumber, :uid_number, LdapConverters::Number
  ldap_map :gidNumber, :gid_number, LdapConverters::Number
  ldap_map :sn, :last_name
  ldap_map :givenName, :first_name
  ldap_map :mail, :email
  ldap_map(:mail, :secondary_emails){ |v| _, *other_emails = Array(v); other_emails }
  ldap_map :puavoSchool, :school_dns, LdapConverters::ArrayValue
  ldap_map :preferredLanguage, :preferred_language
  ldap_map(:jpegPhoto, :profile_image_link) do |image_data|
    if image_data
      @model.link "/v3/users/#{ @model.username }/profile.jpg"
    end
  end
  ldap_map :puavoLocale, :locale
  ldap_map :puavoTimezone, :timezone
  ldap_map :puavoLocked, :locked, &LdapConverters.string_boolean
  ldap_map :puavoSshPublicKey, :ssh_public_key
  ldap_map :homeDirectory, :home_directory
  ldap_map :loginShell, :login_shell, :default => "/bin/bash"
  ldap_map :telephoneNumber, :telephone_number

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

  before :update do
    if changed?(:username)
      # XXX This change must be reflected to Groups, SambaGroups etc.
      raise NotImplemented, :user => "username changing is not implemented"
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

    if !@password.nil? && @password.size < 8
      add_validation_error(:password, :password_too_short, "Password must have at least 8 characters")
    end

    if school.nil?
      add_validation_error(:school_dns, :must_have_school, "no schools are set")
    end

    if new? && school
      home = "/home/#{ school.abbreviation }/#{ username }"
      if User.by_attr(:home_directory, home)
        add_validation_error(:username, :bad_home_directoy, "Home directory (#{ home }) if already in use for this username")
      else
        write_raw(:homeDirectory, transform(:home_directory, :write, home))
      end
    end

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

    validate_unique(:uid_number)
    validate_unique(:id)
    assert_validation

    write_samba_attrs
  end

  after :create do
    # Add user to samba group after it is successfully saved
    samba_group = SambaGroup.by_attr!(:name, "Domain Users")
    if !samba_group.members.include?(username)
      samba_group.add(:members, username)
      samba_group.save!
    end
  end

  # Just store password locally and handle it in after hook
  def password=(pw)
    @password = pw
  end

  after :create, :update do
    next if @password.nil?

    begin
      Puavo.ldap_passwd(
        CONFIG["ldap"],
        LdapModel.settings[:credentials][:dn],
        LdapModel.settings[:credentials][:password],
        @password,
        dn
      )
    ensure
      @password = nil
    end

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

  def username=(_username)
    write_raw(:uid, Array(_username))
    write_raw(:cn, Array(_username))
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

  # aka by_uuid
  def self.by_username(username, attrs=nil)
    by_attr(:username, username, :single, attrs)
  end

  def self.by_username!(username, attrs=nil)
    by_attr!(:username, username, :single, attrs)
  end


  def self.resolve_dn(username)
    by_attr!(:username, username, ["dn"]).dn
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
              "abbreviation" => group.abbreviation
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

  private

  # Write internal samba attributes. Implementation is based on the puavo-web
  # code is not actually tested on production systems
  def write_samba_attrs
    all_samba_domains = SambaDomain.all

    if all_samba_domains.empty?
      raise InternalError, :user => "Cannot find samba domain"
    end

   # Each organisation should have only one
    if all_samba_domains.size > 1
      raise InternalError, :user => "Too many Samba domains"
    end

    samba_domain = all_samba_domains.first

    pool_key = "puavoNextSambaSID:#{ samba_domain.domain }"

    if IdPool.last_id(pool_key).nil?
      IdPool.set_id!(pool_key, samba_domain.legacy_rid)
    end

    rid = IdPool.next_id(pool_key)

    write_raw(:sambaAcctFlags, ["[U]"])
    write_raw(:sambaSID, ["#{ samba_domain.sid }-#{ rid - 1}"])
    if school
      write_raw(:sambaPrimaryGroupSID, ["#{samba_domain.sid}-#{school.id}"])
    end

    samba_sid = Array(get_raw(:sambaSID)).first
    if samba_sid && new?
      res = LdapModel.raw_filter(organisation["base"], "(sambaSID=#{ escape samba_sid })")
      if res && !res.empty?
        other_dn = res.first["dn"].first
        # Internal attribute, use underscore prefix to indicate that
        add_validation_error(:__sambaSID, :sambaSID_not_unique, "#{ samba_sid } is already used by #{ other_dn }")
      end
    end
    # Redo validation for samba attrs
    assert_validation

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
      json User.by_attr(:email, params["email"], :multi, attrs)
    elsif params["id"]
      json User.by_attr(:id, params["id"], :multi, attrs)
    else
      users = User.all(attrs)
      json users
    end

  end

  # Return users in a organisation
  get "/v3/users/:username" do
    auth :basic_auth, :kerberos

    json User.by_username!(params["username"], params["attributes"])
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

