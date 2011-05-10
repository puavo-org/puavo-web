class Printer < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Printers",
                :classes => ['top', 'cupsPrinter', 'puavoPrinterQueue'] )

  before_validation :set_puavo_id

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

end
