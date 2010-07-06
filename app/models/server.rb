class Server < ActiveLdap::Base
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Hosts",
                :classes => ['top', 'device', 'ipHost', 'puppetClient', 'puavoServer'] )

  has_many( :automounts, :class_name => 'Automount',
            :primary_key => 'dn',
            :foreign_key => 'puavoServer' )
  
  before_validation :set_puavo_id

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  def full_hostname
    "#{self.cn}.#{LdapBase.first.puavoDomain}"
  end

  private

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end
end
