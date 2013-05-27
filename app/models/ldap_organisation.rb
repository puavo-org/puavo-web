class LdapOrganisation < LdapBase
  include Wlan

  ldap_mapping( :dn_attribute => "dc",
                :prefix => "",
                :classes => ["dcObject", "organization", "puavoEduOrg", "eduOrg"] )

  validate :validate_wlan_attributes

  def self.current
    LdapOrganisation.first
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
end
