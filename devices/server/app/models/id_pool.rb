class IdPool < ActiveLdap::Base
  ldap_mapping( :dn_attribute => "cn",
                :prefix => "",
                :classes => ['top', 'puavoIdPool'] )

  def self.find(*args)
    unless connected?
      self.setup_connection( ensure_configuration.merge("base" => "o=puavo") )
    end
    super
  end

  def self.next_puavo_id
    new_puavo_id = next_id("puavoNextId")
    return new_puavo_id
  end

  private

  def self.next_id(id_field)
    id_pool = self.find('IdPool')
    new_id = id_pool.send(id_field)
    id_pool.send(id_field + "=", new_id + 1)
    id_pool.save
    return new_id.to_s
  end
end
