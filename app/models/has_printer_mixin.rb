module HasPrinterMixin

  def has_printer?(printer)
    printer = self.class.ensure_dn(printer)
    Array(self.puavoPrinterQueue).include?(printer)
  end

  def add_printer(printer)
    printer = self.class.ensure_dn(printer)
    ldap_modify_operation(:add, [
      { "puavoPrinterQueue" => printer }
    ]) rescue ActiveLdap::LdapError::TypeOrValueExists
    reload
  end

  def remove_printer(printer)
    printer = self.class.ensure_dn(printer)
    ldap_modify_operation(:delete, [
      { "puavoPrinterQueue" => [printer.to_s] }
    ]) rescue ActiveLdap::LdapError::NoSuchAttribute
    reload
  end

end
