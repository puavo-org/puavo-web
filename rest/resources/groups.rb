module PuavoRest

class Group < LdapModel
  ldap_map :dn, :dn
  ldap_map :cn, :name
  ldap_map(:gidNumber, :gid_number){ |v| Array(v).first.to_i }
  ldap_map :puavoPrinterQueue, :printer_queue_dns

  def self.ldap_base
    "ou=Groups,#{ organisation["base"] }"
  end

  def self.by_user_dn(dn)
    filter("(member=#{ escape dn })")
  end

  def printer_queues
    Array(self["printer_queue_dns"]).map do |dn|
      PrinterQueue.by_dn(dn)
    end
  end

end
end
