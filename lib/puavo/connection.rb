module Puavo
  module Connection
    def self.included(base)
      base.send :extend, ClassMethods
    end

    module ClassMethods
      def ldap_setup_connection(host, base, dn, password)
        setup_connection( ensure_configuration.merge( { "host" => host,
                                                        "base" => base,
                                                        "bind_dn" => dn,
                                                        "password" => password } ) )
      end
    end
  end
end
