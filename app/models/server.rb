class Server < ActiveLdap::Base
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Hosts",
                :classes => ['top', 'device', 'ipHost', 'puppetClient', 'puavoServer'] )

  before_validation :set_puavo_id

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  private

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end
end
