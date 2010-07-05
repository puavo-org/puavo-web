class Automount < ActiveLdap::Base
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=auto.master,ou=Automount",
                :classes => ['top', 'automount', 'puavoShare'] )

  belongs_to( :server, :class_name => 'Server',
              :foreign_key => 'puavoServer',
              :primary_key => 'dn' )


  before_validation :set_special_ldap_value

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  private

  def set_special_ldap_value
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
    self.automountInformation = "-fstype=nfs4,rw,sec=krb5 #{self.server.ipHostNumber}:/home/#{self.cn}"
  end

end
