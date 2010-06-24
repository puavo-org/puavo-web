class School < ActiveLdap::Base
  ldap_mapping( :dn_attribute => Puavo.configurations['school']['dn_attribute'],
                :prefix => Puavo.configurations['school']['prefix'],
                :classes => Puavo.configurations['school']['classes'] )

  def method_missing(*args)
    begin
      super
    rescue
      if Puavo.configurations['school']['attributes'][args.first.to_s]
        self.send(Puavo.configurations['school']['attributes'][args.first.to_s])
      else
        super
      end
    end
  end
end
