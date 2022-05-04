# -*- coding: utf-8 -*-
class User < LdapBase
  include Puavo::Integrations

  include Puavo::AuthenticationMixin
  include Puavo::Locale
  include Puavo::Helpers
  include Puavo::Integrations
  include Puavo::Password

  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=People",
                :classes => ['top', 'posixAccount', 'inetOrgPerson', 'puavoEduPerson','sambaSamAccount','eduPerson'] )
  belongs_to :groups, :class_name => 'Group', :many => 'member', :primary_key => "dn"
  belongs_to :uidGroups, :class_name => 'Group', :many => 'memberUid', :primary_key => "Uid"
  belongs_to( :primary_group, :class_name => 'School',
              :foreign_key => 'gidNumber',
              :primary_key => 'gidNumber' )
  belongs_to( :school, :class_name => 'School',
              :foreign_key => 'puavoSchool',
              :primary_key => 'dn' )
  belongs_to :member_school, :class_name => 'School', :many => 'member', :primary_key => "dn"
  belongs_to :member_uid_school, :class_name => 'School', :many => 'memberUid', :primary_key => "uid"

  before_validation :set_special_ldap_value

  before_save :is_uid_changed, :set_preferred_language

  before_update :change_password

  after_save :add_member_uid_to_models, :reset_sso_session

  before_destroy :delete_all_associations, :delete_kerberos_principal, :reset_sso_session

  after_create :change_password_no_upstream

  validate :validate

  alias_method :v1_as_json, :as_json

  # Attributes from relations and other helpers
  @@extra_attributes = [
     :password,
     :new_password,
     :uid_has_changed,
     :image,
     :earlier_user,
     :new_password_confirmation,
     :password_change_mode
  ]

  attr_accessor(*@@extra_attributes)

  def self.image_size
    { :width => 120, :height => 160 }
  end

  def as_json(*args)
    self.class.build_hash_for_to_json(self)
  end

  # Building hash for as_json method with better name of attributes
  #  * data argument may be User or Hash
  def self.build_hash_for_to_json(data)
    new_user_hash = {}
    # Note: value of attribute may be raw ldap value eg. { givenName => ["Joe"] }
    user_attributes =
      [ { :original_attribute_name => "givenName",
          :new_attribute_name => "given_name",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "puavoAdminOfSchool",
          :new_attribute_name => "admin_of_schools",
          :value_block => lambda{ |value| value ? Array(value).map{ |s| s.to_s.match(/puavoId=([^, ]+)/)[1].to_i } : [] } },
        { :original_attribute_name => "puavoSchool",
          :new_attribute_name => "school_id",
          :value_block => lambda{ |value| value.to_s.match(/puavoId=([^, ]+)/)[1].to_i } },
        { :original_attribute_name => "telephoneNumber",
          :new_attribute_name => "telephone_number",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "displayName",
          :new_attribute_name => "name",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "gidNumber",
          :new_attribute_name => "gid",
          :value_block => lambda{ |value| Array(value).first.to_i } },
        { :original_attribute_name => "homeDirectory",
          :new_attribute_name => "home_directory",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "puavoEduPersonAffiliation",
          :new_attribute_name => "user_type",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "mail",
          :new_attribute_name => "email",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "puavoEduPersonReverseDisplayName",
          :new_attribute_name => "reverse_name",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "sn",
          :new_attribute_name => "surname",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "uid",
          :new_attribute_name => "uid",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "puavoId",
          :new_attribute_name => "puavo_id",
          :value_block => lambda{ |value| Array(value).first.to_i } },
        { :original_attribute_name => "sambaSID",
          :new_attribute_name => "samba_sid",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "uidNumber",
          :new_attribute_name => "uid_number",
          :value_block => lambda{ |value| Array(value).first.to_i } },
        { :original_attribute_name => "loginShell",
          :new_attribute_name => "login_shell",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "sambaPrimaryGroupSID",
          :new_attribute_name => "samba_primary_group_SID",
          :value_block => lambda{ |value| Array(value).first } } ]

    user_attributes.each do |attr|
      attribute_value = data.class == Hash ? data[attr[:original_attribute_name]] : data.send(attr[:original_attribute_name])
      new_user_hash[attr[:new_attribute_name]] = attr[:value_block].call(attribute_value)
    end
    return new_user_hash
  end

  def all_attributes
    attrs = attributes
    @@extra_attributes.each do |attr|
      attrs[attr.to_s] = send(attr)
    end
    attrs
  end

  def validate
    # givenName validation
    if self.givenName.empty?
      errors.add( :givenName, I18n.t("activeldap.errors.messages.blank",
                                    :attribute => I18n.t("activeldap.attributes.user.givenName") ) )
    end

    if !self.new_password_confirmation.nil? && self.new_password != self.new_password_confirmation
      errors.add( :new_password_confirmation, I18n.t("activeldap.errors.messages.confirmation",
                                        :attribute => I18n.t("activeldap.attributes.user.new_password")) )
    end

    # Validate the password against the validation rules specified for this organisation/school
    if !self.new_password_confirmation.nil? && !self.new_password_confirmation.empty?
      unless self.primary_school.cn == 'administration'
        if self.new_password
          password_errors = []

          ruleset_name =
            get_school_password_requirements(LdapOrganisation.current.cn, self.primary_school.puavoId)

          if ruleset_name
            # Rule-based password validation
            rules = Puavo::PASSWORD_RULESETS[ruleset_name]

            password_errors +=
              Puavo::Password::validate_password(self.new_password, rules[:rules])

            if rules[:deny_names_in_passwords]
              if self.new_password.downcase.include?(self.givenName.downcase) ||
                 self.new_password.downcase.include?(self.sn.downcase) ||
                 self.new_password.downcase.include?(self.uid.downcase)
                password_errors << 'contains_name'
              end
            end
          end

          # Reject common passwords. Match full words in a tab-separated string.
          if Puavo::COMMON_PASSWORDS.include?("\t#{self.new_password}\t")
            password_errors << 'common'
          end

          unless password_errors.empty?
            # Combine the errors like the live validator does
            password_errors = password_errors
                              .collect { |e| I18n.t("activeldap.errors.messages.password_validation.#{e}") }
                              .join('<br>')
                              .html_safe

            errors.add(:new_password, password_errors)
          end
        end
      end
    end

    # Validates length of uid
    if self.uid.to_s.size < 3
      errors.add( :uid,  I18n.t("activeldap.errors.messages.too_short",
                                :attribute => I18n.t("activeldap.attributes.user.uid"),
                                :count => 3) )
    end
    if self.uid.to_s.size > 255
      errors.add( :uid, I18n.t("activeldap.errors.messages.too_long",
                               :attribute => I18n.t("activeldap.attributes.user.uid"),
                               :count => 255) )
    end
    # Format of uid, default configuration:
    #   * allowed characters is a-z0-9.-
    #   * uid must begin with the small letter
    allow_uppercase_characters_uid = Puavo::Organisation.
      find(LdapOrganisation.current.cn).
      value_by_key("allow_uppercase_characters_uid").
      to_s.chomp == "true" ? true : false rescue false

    usernameFailed = false

    unless self.uid.to_s =~ ( allow_uppercase_characters_uid ? /^[a-zA-Z]/ : /^[a-z]/ )
      errors.add( :uid, I18n.t("activeldap.errors.messages.user.must_begin_with") )
      usernameFailed = true
    end

    unless self.uid.to_s =~ ( allow_uppercase_characters_uid ? /^[a-zA-Z0-9.-]+$/ : /^[a-z0-9.-]+$/ )
      errors.add( :uid, I18n.t("activeldap.errors.messages.user.invalid_characters") )
      usernameFailed = true
    end

    locale_puavoEduPersonAffiliation_name = I18n.t("activeldap.attributes.user.puavoEduPersonAffiliation")

    if self.puavoEduPersonAffiliation.nil?
      errors.add( :puavoEduPersonAffiliation, I18n.t("activeldap.errors.messages.blank",
                                                     :attribute => locale_puavoEduPersonAffiliation_name ) )
    end

    # puavoEduPersonAffiliation validation
    Array(self.puavoEduPersonAffiliation).each do |value|
      unless self.class.puavoEduPersonAffiliation_list.include?(value)
        errors.add( :puavoEduPersonAffiliation,
                    I18n.t("activeldap.errors.messages.invalid",
                           :attribute => locale_puavoEduPersonAffiliation_name ) )
      end
    end

    # Validate the image, if set. Must be done here, because if the file is not a valid image file,
    # it will cause an exception in ImageMagick.
    if self.image && !self.image.path.to_s.empty?
      begin
        resize_image
      rescue
        errors.add(:image, I18n.t('activeldap.errors.messages.image_failed'))
      end
    end

    # If the username failed validation, stop here. Older versions if the LDAP library allowed invalid characters
    # in the username and the user was returned to the form, but in newer versions the LDAP query fails. So force
    # stop here if the username isn't valid.
    return false if usernameFailed

    # Validate uid uniqueness only if there are no other errors in the uid
    if !self.uid.nil? && !self.uid.empty? && errors.select{ |k,v| k == "uid" }.empty?
      if user = User.find(:first, :attribute => "uid", :value => self.uid)
        if user.puavoId != self.puavoId
          self.earlier_user = user
          errors.add :uid, I18n.t("activeldap.errors.messages.taken",
                                  :attribute => I18n.t("activeldap.attributes.user.uid") )
        end
      end
    end

    # Unique validation for puavoExternalId
    if !self.puavoExternalId.nil? && !self.puavoExternalId.empty?
      if user = User.find(:first, :attribute => "puavoExternalId", :value => self.puavoExternalId)
        if user.puavoId != self.puavoId
          errors.add :puavoExternalId, I18n.t("activeldap.errors.messages.taken",
                                              :attribute => I18n.t("activeldap.attributes.user.puavoExternalId") )
        end
      end
    end

    emailFailed = false

    if !self.mail.nil? && !self.mail.empty?
      Array(self.mail).each do |m|
        m.strip!

        # There are (supposedly) checks that validate email addresses... but they don't
        # seem to work. So... just brute-force it.
        # Regex taken from https://www.regular-expressions.info/email.html
        if !m.empty? && !/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.match(m)
          emailFailed = true
        end
      end

      if emailFailed
        errors.add(:mail, I18n.t('activeldap.errors.messages.email_not_valid'))
        return false
      end

      email_dup = User.find(:first, :attribute => "mail", :value => self.mail)
      if email_dup && email_dup.puavoId != self.puavoId
        errors.add(
          :mail,
          I18n.t(
            "activeldap.errors.messages.taken",
            :attribute => I18n.t("activeldap.attributes.user.mail")
          )
        )
      end
    end

    if !self.telephoneNumber.nil? && !self.telephoneNumber.empty?
      Array(self.telephoneNumber).each do |p|
        p.strip!
        if p == '-'
          errors.add(:telephoneNumber,
                     I18n.t("activeldap.errors.messages.invalid",
                            :attribute => I18n.t("activeldap.attributes.user.telephoneNumber")))
          return false
        end
      end
    end

    # Fix the primary school DN if it isn't set and it can be fixed
    unless self.puavoEduPersonPrimarySchool
      all_schools = Array(self.school)

      if all_schools.count == 1
        self.puavoEduPersonPrimarySchool = self.school.dn
      else
        raise RuntimeError, "user has multiple schools, but puavoEduPersonPrimarySchool is not set"
      end
    end

    # Explode loudly if the primary school DN is invalid
    self.primary_school
  end

  def change_password_no_upstream
    change_password(:no_upstream)
  end

  def change_password(mode=nil)
    return if new_password.nil? || new_password.empty?

    ldap_conf = User.configuration

    # ldap_conf[:bind_dn] may not be associated with a username in the
    # current organisation in which case it should be nil
    actor_dn = ldap_conf[:bind_dn]
    actor_username = User.find(actor_dn).uid rescue nil

    # use a particular passowrd change mode
    # (:all, :upstream_only, :no_upstream) if requested, otherwise
    # the current operation default or default
    pw_change_mode = password_change_mode || mode || :all

    # This request ID is logged everywhere and shown to the user
    # in case something goes wrong. It can be then grepped from
    # the logs to determine why the password change failed.
    request_id = generate_synchronous_call_id()

    rest_params = {
      :actor_dn             => actor_dn.to_s,
      :actor_username       => actor_username,
      :actor_password       => ldap_conf[:password],
      :host                 => ldap_conf[:host],
      :mode                 => pw_change_mode,
      :target_user_username => self.uid,
      :target_user_password => new_password,
      :request_id           => request_id,
    }

    logger.info("[#{request_id}] Sending a password change request to puavo-rest, target user is \"#{self.uid}\"")

    res = rest_proxy.put('/v3/users/password', :json => rest_params).parse

    unless res.kind_of?(Hash)
      logger.warn("[#{request_id}] the puavo-rest call did not return a Hash:")
      logger.warn("[#{request_id}]   #{res.inspect}")
      res = {}
    end

    full_reply = res.merge(
      :from => 'user model',
      :user => {
        :dn  => self.dn.to_s,
        :uid => self.uid,
      }
    )

    logger.info("[#{request_id}] full reply from puavo-rest: #{full_reply}")

    if res['exit_status'] != 0
      logger.error("[#{request_id}] puavo-rest call failed with exit status #{res['exit_status']}:")

      if res.include?('stderr')
        logger.error("[#{request_id}]  stderr: \"#{res['stderr']}\"")
      end

      if res.include?('stdout')
        logger.error("[#{request_id}]  stdout: \"#{res['stdout']}\"")
      end

      # Interpret the results. If there were external systems where the
      # password change could not be synchronised, they might (should)
      # have returned an actual error code indicating why the call
      # failed. If that code exists, use it to format a clean error
      # message that can be shown to the user. Otherwise, show a generic
      # error message (which isn't good).

      if res.include?('sync_status') && res.include?('request_id')
        raise UserError, I18n.t('flash.password.failed_details',
          :details => I18n.t('flash.integrations.' + res['sync_status']),
          :code => request_id)
      else
        raise UserError, I18n.t('flash.password.failed')
      end
    end

    return true
  end

  # FIXME, where is better location on this method? Using same code also on other model?
  def self.human_attribute_name(*args)
    if I18n.t("activeldap.attributes").has_key?(:user) &&
       # Attribute key name
       I18n.t("activeldap.attributes.user").has_key?(args[0].to_sym)

      if args[0] == "puavoEduPersonAffiliation"
        return I18n.t("activeldap.attributes.user.puavoEduPersonAffiliationDeprecated")
      end

      return I18n.t("activeldap.attributes.user.#{args[0]}")
    end
    super(*args)
  end

  def generate_password(size=8)
    characters = (("a".."z").to_a + ("0".."9").to_a).delete_if do |char| not char[/[015iIosql]/].nil? end
    Array.new(size) { characters[rand(characters.size)] }.join
  end

  def set_generated_password
    self.new_password = generate_password
  end

  def set_password(password)
    self.new_password = password
  end

  def self.puavoEduPersonAffiliation_list
    ["teacher", "staff", "student", "visitor", "parent", "admin", "testuser"]
  end

  def destroy(*args)
    delete_dn_cache
    super
  end

  def update_attributes(*args)
    delete_dn_cache
    super
  end

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  def organisation_owner?
    Array(LdapOrganisation.current.owner).include? self.dn
  end

  def human_readable_format(attribute)
    case attribute
    when "puavoEduPersonAffiliation"
      if self.class.puavoEduPersonAffiliation_list.include?(self.send(attribute).to_s)
        I18n.t( 'puavoEduPersonAffiliation_' + self.send(attribute) )
      else
        Array(self.send(attribute)).first.to_s
      end
    else
      Array(self.send(attribute)).first.to_s
    end
  end

  def primary_school
    all_schools = Array(self.school)

    if self.puavoEduPersonPrimarySchool
      # Most users have only one school, so this loop should be over quickly
      all_schools.each do |s|
        if s.dn.to_s == self.puavoEduPersonPrimarySchool
          return s
        end
      end

      raise RuntimeError, "user::primary_school(): primary school DN \"#{self.puavoEduPersonPrimarySchool}\" points to an invalid school"
    end

    if all_schools.count != 1
      raise RuntimeError, "user::primary_school(): user has multiple schools, but puavoEduPersonPrimarySchool is not set"
    end

    all_schools[0]
  end

  def change_school(new_school_dn)
    school_dn = self.puavoSchool
    LdapBase.ldap_modify_operation( self.puavoSchool,
                                    :delete, [{ "member" => [self.dn.to_s] }]) rescue Exception
    LdapBase.ldap_modify_operation( self.puavoSchool,
                                    :delete, [{ "memberUid" => [self.uid.to_s] }]) rescue Exception
    self.puavoSchool = new_school_dn
  end

  def managed_schools
    device = Device.find( :all,
                          :attributes => ["*", "+"],
                          :attribute => 'creatorsName',
                          :value => self.dn.to_s).max do |a,b|
      a.puavoId.to_i <=> b.puavoId.to_i
    end
    default_school_dn = device.puavoSchool if device

    if Array(LdapOrganisation.current.owner).include?(self.dn)
      schools = School.all
    else
      schools = School.find( :all,
                             :attribute => 'puavoSchoolAdmin',
                             :value => self.dn )
    end

    if default_school = schools.select{ |s| s.dn.to_s == default_school_dn.to_s }.first
      default_school_id = default_school.puavoId
    else
      default_school_id = schools.first.puavoId
    end

    return ( { 'label' => 'School',
               'default' => default_school_id,
               'title' => 'School selection',
               'question' => 'Select school: ',
               'list' =>  schools.map{ |s| s.v1_as_json }  } ) unless schools.empty?
  end

  def administrative_groups
    return @administrative_groups if @administrative_groups
    @administrative_groups = rest_proxy.get("/v3/users/#{ self.uid }/administrative_groups").parse or []
  end

  def administrative_groups=(group_ids)
    rest_proxy.put("/v3/users/#{ self.uid }/administrative_groups", :json => { "ids" => group_ids }).parse
  end

  def teaching_group
    return @teaching_group if @teaching_group
    @teaching_group = rest_proxy.get("/v3/users/#{ self.uid }/teaching_group").parse or {}
  end

  def teaching_group=(group_id)
    rest_proxy.put("/v3/users/#{ self.uid }/teaching_group", :params => { "id" => group_id }).parse
  end

  def year_class
    return @year_class if @year_class
    @year_class = rest_proxy.get("/v3/users/#{ self.uid }/year_class").parse or {}
  end

  private

  def set_special_ldap_value
    pri_school = self.primary_school

    self.displayName = self.givenName + " " + self.sn
    self.cn = self.uid
    self.homeDirectory = "/home/" + self.uid unless self.uid.nil?
    self.gidNumber = pri_school.gidNumber
    set_uid_number if self.uidNumber.nil?
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
    set_samba_settings if self.sambaSID.nil?
    unless self.gidNumber.nil? || self.puavoSchool.nil?
      self.sambaPrimaryGroupSID = "#{SambaDomain.first.sambaSID}-#{pri_school.puavoId}"
    end
    self.loginShell = '/bin/bash'
    self.eduPersonPrincipalName = "#{self.uid}@#{LdapOrganisation.current.puavoKerberosRealm}"
    if self.puavoAllowRemoteAccess.class == String
      self.puavoAllowRemoteAccess = case self.puavoAllowRemoteAccess
                                    when "true"
                                      true
                                    when "false"
                                      false
                                    end
    end
    self.puavoEduPersonReverseDisplayName = self.sn + " " + self.givenName
  end

  def set_uid_number
    self.uidNumber = IdPool.next_uid_number
  end

  def is_uid_changed
    unless self.puavoId.nil?
      begin
        old_user = User.find(self.puavoId)
        if self.uid != old_user.uid
          self.uid_has_changed = true

          logger.debug "User uid has changed. Remove memberUid from groups"

          Group.search_as_utf8( :filter => "(memberUid=#{old_user.uid})",
                        :scope => :one,
                        :attributes => ['dn'] ).each do |group_dn, values|
            begin
              LdapBase.ldap_modify_operation(group_dn, :delete, [{"memberUid" => [old_user.uid.to_s]}])
            rescue ActiveLdap::LdapError::NoSuchAttribute
            end
          end
          School.search_as_utf8( :filter => "(memberUid=#{old_user.uid})",
                         :scope => :one,
                         :attributes => ['dn'] ).each do |school_dn, values|
            begin
              LdapBase.ldap_modify_operation(school_dn, :delete, [{"memberUid" => [old_user.uid.to_s]}])
            rescue ActiveLdap::LdapError::NoSuchAttribute
            end
          end
          # Remove uid from Domain Users group
          SambaGroup.delete_uid_from_memberUid('Domain Users', old_user.uid)
        end
      rescue ActiveLdap::EntryNotFound
      end
    end
  end

  def add_member_uid_to_models
    if self.uid_has_changed
      logger.debug "User uid has changed. Add the new uid to groups if it's not already in them."
      self.uid_has_changed = false

      self.groups.each do |group|
        begin
          group.ldap_modify_operation( :add, [{"memberUid" => [self.uid.to_s]}] )
        rescue ActiveLdap::LdapError::TypeOrValueExists
        end
      end
    end

    Array(self.school).each do |school|
      unless Array(school.memberUid).include?(self.uid)
        begin
          school.ldap_modify_operation( :add, [{"memberUid" => [self.uid.to_s]}] )
        rescue ActiveLdap::LdapError::TypeOrValueExists
        end
      end

      unless Array(school.member).include?(self.dn)
        # There was a "FIXME" in the original code here, but I don't know what it was for.
        # As far as I can tell, it was added in commit ec5094a99 back in 2011, but there was
        # no explanation for what was broken.
        begin
          school.ldap_modify_operation( :add, [{"member" => [self.dn.to_s]}] )
        rescue ActiveLdap::LdapError::TypeOrValueExists
        end

      end
    end

    # Set uid to Domain Users group
    SambaGroup.add_uid_to_memberUid('Domain Users', self.uid)
  end

  # Invalidate active SSO session cookies for this user, if present
  def reset_sso_session
    organisation = Puavo::Organisation.find(LdapOrganisation.current.cn)
    return unless organisation
    return if organisation.value_by_key('enable_sso_sessions_in').nil?

    # This organisation has SSO login cookies enabled. If this user has an active session,
    # remove it immediately.
    db = Redis::Namespace.new('sso_session', :redis => REDIS_CONNECTION)

    key = db.get("user:#{self.id}")
    return unless key

    if db.get("data:#{key}")
      db.del("data:#{key}")
    end

    db.del("user:#{self.id}")
  end

  private

  def delete_all_associations
    # Remove uid from Domain Users group
    SambaGroup.delete_uid_from_memberUid('Domain Users', self.uid)
    if Array(self.puavoAdminOfSchool).count > 0
      SambaGroup.delete_uid_from_memberUid('Domain Admins', self.uid)
    end

    self.groups.each do |g|
      g.remove_user(self)
    end

    Array(self.school).each do |s|
      s.remove_user(self)
    end
  end

  def delete_kerberos_principal
    # XXX We should really destroy the kerberos principal for this user,
    # XXX but for now we just set a password to some unknown value
    # XXX so that the kerberos principal can not be used.
    self.new_password = generate_password(40)
    change_password(:no_upstream)
  end

  def set_samba_settings
    self.sambaSID = SambaDomain.next_samba_sid
    self.sambaAcctFlags = "[U]"
  end

end

# FIXME: this code have to move to better place.
module ActiveLdap
  module Association
    class BelongsTo < Proxy
      # Overwrite to_s method.
      # Example usage: user.primary_group.to_s, return example: "Class 4"
      def to_s
        # exists?-method load target (example group object) and returns true if found it
        if self.exists?
          return self.target.to_s
        end
        return ""
      end
    end
  end
end
