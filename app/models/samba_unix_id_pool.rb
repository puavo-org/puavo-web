class SambaUnixIdPool < ActiveLdap::Base
  ldap_mapping( :dn_attribute => "sambaDomainName",
                :prefix => "",
                :classes => ['top', 'sambaDomain', 'sambaUnixIdPool'] )

  self.base = "dc=edu,dc=example,dc=org"

  def self.next_uid_number
    new_uid_number = next_id("uidNumber")
    if User.find(:first, :attribute => "uidNumber", :value => new_uid_number)
      return next_uid_number
    end
    return new_uid_number
  end

  def self.next_gid_number
    new_gid_number = next_id("gidNumber")
    if Group.find(:first, :attribute => "gidNumber", :value => new_gid_number)
      return next_gid_number
    end
    return new_gid_number
  end

  private

  def self.next_id(id_field)
    samba_unix_id_pool = SambaUnixIdPool.find('Opinsys')
    new_id = samba_unix_id_pool.send(id_field)
    samba_unix_id_pool.send(id_field + "=", new_id + 1)
    samba_unix_id_pool.save
    return new_id.to_s
  end
end
