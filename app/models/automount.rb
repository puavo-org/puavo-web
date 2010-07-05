class Automount < ActiveLdap::Base
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=auto.master,ou=Automount",
                :classes => ['top', 'automount', 'puavoShare'] )

  before_validation :set_special_ldap_value

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  private

  def set_special_ldap_value
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
    self.automountInformation = "-fstype=nfs4,rw,sec=krb5 #{"ltsp1"}:/home/#{self.cn}"
  end

end
