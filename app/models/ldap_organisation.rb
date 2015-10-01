class LdapOrganisation < LdapBase
  include Wlan
  include BooleanAttributes
  include Puavo::Locale

  ldap_mapping( :dn_attribute => "dc",
                :prefix => "",
                :classes => ["dcObject", "organization", "puavoEduOrg", "eduOrg"] )

  validate :validate_wlan_attributes

  before_save :set_preferred_language

  def self.current
    LdapOrganisation.first
  end

  def rest_proxy
    conf = self.class.configuration
    PuavoRestProxy.new(
      puavoDomain,
      conf[:bind_dn],
      conf[:password]
    )
  end

  def as_json(*args)
    # owner: return only users's puavoId, skip uid=admin,o=puavo user
    { "domain" => self.puavoDomain,
      "puppet_host" => self.puavoPuppetHost,
      "owners" => Array(self.owner).select{|o| o.to_s.match(/puavoId/)}.map{ |org|
        org.to_s.match(/puavoId=([^, ]+)/)[1].to_i },
      "preferred_language" => self.preferredLanguage,
      "name" => self.o }
  end

  def add_owner(user)
    # FIXME: add owner also to Domain Admins
    #domain_admin = SambaGroup.find("Domain Admins")
    #domain_admin.memberUid = user.uid
    #domain_admin.save!

    self.ldap_modify_operation( :add, [{"owner" => [user.dn.to_s]}] )
  end

  def remove_owner(user)
    self.ldap_modify_operation( :delete, [{"owner" => [user.dn.to_s]}] )
  end

end
