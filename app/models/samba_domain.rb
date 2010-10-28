class SambaDomain < LdapBase
  ldap_mapping( :dn_attribute => "sambaDomainName",
                :prefix => "",
                :classes => ['top', 'sambaDomain'] )

  def self.next_samba_sid
    samba_domain = first
    next_rid = samba_domain.sambaNextRid
    samba_domain.sambaNextRid = next_rid.nil? ? 2 : next_rid + 1
    samba_domain.save
    return "#{samba_domain.sambaSID}-#{samba_domain.sambaNextRid.to_i - 1}"
  end
end
