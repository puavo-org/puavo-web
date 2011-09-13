class LdapOrganisation < LdapBase
  ldap_mapping( :dn_attribute => "dc",
                :prefix => "",
                :classes => ["dcObject", "organization", "puavoEduOrg", "eduOrg"] )

  def self.current
    LdapOrganisation.first
  end

  def to_json(*args)
    # owner: return only users's puavoId, skip uid=admin,o=puavo user
    { "domain" => self.puavoDomain,
      "puppet_host" => self.puavoPuppetHost,
      "owners" => Array(self.owner).select{|o| o.to_s.match(/puavoId/)}.map{ |org|
        org.to_s.match(/puavoId=([^, ]+)/)[1].to_i },
      "preferred_language" => self.preferredLanguage,
      "name" => self.o }.to_json
  end
end
