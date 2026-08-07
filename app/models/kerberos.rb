# frozen_string_literal: true

class Kerberos < LdapBase
  ldap_mapping dn_attribute: 'krbPrincipalName',
               prefix: 'ou=Kerberos Realms',
               classes: %w[krbPrincipal]

  def self.all_auth_times_by_uid
    auth_times_by_uid = {}

    self.all.each do |k|
      unless k.krbPrincipalName
        warn("could not find kerberos principal in #{k.dn}")
        next
      end

      match = k.krbPrincipalName.match(/^(.*)@/)

      unless match
        logger.warn("kerberos principal is in bad format in dn=#{k.dn}")
        next
      end

      uid = match[1]
      auth_times_by_uid[uid] = k.krbLastSuccessfulAuth
    end

    auth_times_by_uid
  end
end
