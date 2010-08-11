class Server < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Servers,ou=Hosts",
                :classes => ['top', 'device', 'puppetClient', 'puavoServer'] )

  has_many( :automounts, :class_name => 'Automount',
            :primary_key => 'dn',
            :foreign_key => 'puavoServer' )

  before_validation :set_puavo_id

  def full_hostname
    "#{self.puavoHostname}.#{LdapOrganisation.first.puavoDomain}"
  end

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  private

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
    self.cn = self.puavoHostname
  end
end
