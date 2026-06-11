# frozen_string_literal: true

class MacAddress < LdapBase
  ldap_mapping dn_attribute: 'dhcpHWAddress',
               prefix: 'ou=Devices,ou=Hosts',
               classes: %w[top dhcpHost]
end
