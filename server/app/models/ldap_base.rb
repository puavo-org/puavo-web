class LdapBase < ActiveLdap::Base
  include Puavo::Connection if defined?(Puavo::Connection)
end
