module PuavoRest

class Group < LdapHash
  ldap_map :dn, :dn
  ldap_map :cn, :name
  ldap_map :puavoPrinterQueue, :printer_queues

  def self.ldap_base
    "ou=Groups,#{ organisation["base"] }"
  end

  def self.by_user_dn(dn)
    filter("(member=#{ escape dn })")
  end

  def printers
      Array(self["printer_queues"]).map do |dn|
      # TODO: optimize to single ldap query
      PrinterQueue.by_dn(dn)
    end
  end

end
end
