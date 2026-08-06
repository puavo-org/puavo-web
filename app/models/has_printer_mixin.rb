# frozen_string_literal: true

module HasPrinterMixin
  def has_printer?(printer)
    printer = self.class.ensure_dn(printer)
    Array(self.puavoPrinterQueue).include?(printer)
  end

  def add_printer(printer)
    printer = self.class.ensure_dn(printer)

    begin
      ldap_modify_operation(:add, [{ 'puavoPrinterQueue' => printer }])
    rescue ActiveLdap::LdapError::TypeOrValueExists
    end
  end

  def remove_printer(printer)
    printer = self.class.ensure_dn(printer)

    begin
      ldap_modify_operation(:delete, [{ 'puavoPrinterQueue' => [printer.to_s] }])
    rescue ActiveLdap::LdapError::NoSuchAttribute
    end
  end
end
