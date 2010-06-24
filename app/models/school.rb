class School < ActiveLdap::Base
  ldap_mapping( :dn_attribute => Iivari.configurations['school']['dn_attribute'],
                :prefix => Iivari.configurations['school']['prefix'],
                :classes => Iivari.configurations['school']['classes'] )

  def method_missing(*args)
    begin
      super
    rescue
      if Iivari.configurations['school']['attributes'][args.first.to_s]
        self.send(Iivari.configurations['school']['attributes'][args.first.to_s])
      else
        super
      end
    end
  end
end
