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

  def self.next_uid_number
    new_uid_number = next_id("puavoNextUidNumber")
    if User.find(:first, :attribute => "uidNumber", :value => new_uid_number)
      return next_uid_number
    end
    return new_uid_number
  end

  def self.next_gid_number
    new_gid_number = next_id("puavoNextGidNumber")
    if Group.find(:first, :attribute => "gidNumber", :value => new_gid_number)
      return next_gid_number
    end
    return new_gid_number
  end

  def self.next_puavo_id
    new_puavo_id = next_id("puavoNextId")
    return new_puavo_id
  end

  def self.next_puavo_id_range(range)
    generate_id_range("puavoNextId", range)
  end

  private

  def self.generate_id_range(id_field, count)
    redis_id_pool = Redis::Namespace.new(
      "idpool",
      :redis => REDIS_CONNECTION
    )

    ldap_id_pool = self.find('IdPool')

    # Migrate existing id sequences to redis
    if redis_id_pool.get(id_field).nil?
      current_id = ldap_id_pool.send(id_field)
      redis_id_pool.set(id_field, current_id)
    end

    id_range = (1..count).map do
      redis_id_pool.incr(id_field).to_s
    end

    # Save redis id sequences back to the old ldap id pool too. Not required
    # and has the same race condition issues but allows to fallback to it if
    # required.
    ldap_id_pool.send(id_field + "=", id_range.last)
    ldap_id_pool.save

    return id_range
  end

  def self.next_id(id_field)
    generate_id_range(id_field, 1).first
  end
end
