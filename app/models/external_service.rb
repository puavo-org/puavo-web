require 'sha1'
require 'base64'
class ExternalService < LdapBase
  include Puavo::Authentication
  include Puavo::Security

  ldap_mapping( :dn_attribute => "uid",
                :prefix => "ou=System Accounts",
                :classes => ["simpleSecurityObject", "account"] )

  belongs_to :groups, :class_name => 'SystemGroup', :many => 'member', :primary_key => "dn"

  before_save :encrypt_userPassword
  after_save :update_groups
  before_destroy :remove_groups
  validates_length_of( :userPassword,
                       :minimum => 12,
                       :allow_blank => true,
                       :message =>
                       I18n.t("activeldap.errors.messages.too_short",
                              :attribute => I18n.t("userPassword",
                                                   :scope => "activeldap.attributes.external_service"),
                              :count => 12
                              ))

  def update_groups
    new_groups = self.groups.map{ |g| g.class == String ? g : g.id }
    self.reload
    old_groups = self.groups.map &:id
    # Add groups
    (new_groups - old_groups).each do |group_cn|
      update_group_member(group_cn, :add)
    end

    # Remove groups
    (old_groups - new_groups).each do |group_cn|
      update_group_member(group_cn, :delete)
    end
  end

  def remove_groups
    self.groups.each do |group|
      update_group_member(group.cn, :delete)
    end
  end

  private

  def update_group_member(group_cn, type)
    group = SystemGroup.find(group_cn)
    ldif = ActiveLdap::LDIF.new
    record = ActiveLdap::LDIF::ModifyRecord.new(group.dn)
    ldif << record
    record.add_operation(type, 'member', [], {'member' => [self.dn.to_s]})
    ExternalService.load(ldif.to_s)
  end
end
