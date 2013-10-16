module PuavoRest

class Group < LdapModel
  ldap_map :dn, :dn
  ldap_map :cn, :name
  ldap_map(:gidNumber, :gid_number){ |v| Array(v).first.to_i }
  ldap_map(:puavoPrinterQueue, :printer_queue_dns){ |v| Array(v) }

  def self.ldap_base
    "ou=Groups,#{ organisation["base"] }"
  end

  def self.by_user_dn(dn)
    filter("(member=#{ escape dn })")
  end

  def printer_queues
    PrinterQueue.by_dn_array(printer_queue_dns)
  end

end
end
