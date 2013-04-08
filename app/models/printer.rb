class Printer < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Printers",
                :classes => ['top', 'cupsPrinter', 'puavoPrinterQueue'] )

  before_validation :set_puavo_id, :set_empty_location

  def validate
    Printer.find( :all,
                  :attribute => 'printerDescription',
                  :value => self.printerDescription ).each do |printer|
      if self.puavoId != printer.puavoId && self.puavoServer == printer.puavoServer
        errors.add( :printerDescription,
                    I18n.t("activeldap.errors.messages.uniqueness",
                           :attribute => I18n.t("activeldap.attributes.printer.printerDescription") ) )
      end
    end
  end
  
  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  def set_empty_location
    if self.printerLocation.empty? || self.printerLocation.nil?
      self.printerLocation = "-"
    end
  end
end
