# frozen_string_literal: true

class IdPool < ActiveLdap::Base
  ldap_mapping dn_attribute: 'cn',
               prefix: '',
               classes: %w[top puavoIdPool]

  def self.find(*args)
    self.setup_connection(ensure_configuration.merge('base' => 'o=puavo')) unless connected?
    super
  end

  def self.next_uid_number
    new_uid_number = next_id('puavoNextUidNumber')

    return next_uid_number if User.find(:first, attribute: 'uidNumber', value: new_uid_number)

    new_uid_number
  end

  def self.next_gid_number
    new_gid_number = next_id('puavoNextGidNumber')

    return next_gid_number if Group.find(:first, attribute: 'gidNumber', value: new_gid_number)

    new_gid_number
  end

  def self.next_puavo_id
    next_id('puavoNextId')
  end

  def self.next_puavo_id_range(range)
    id_range('puavoNextId', range)
  end

  def self.id_range(id_field, count)
    redis_id_pool = get_redis_id_pool
    legacy_id_pool = get_legacy_id_pool

    # Migrate existing id sequences to redis
    if redis_id_pool.get(id_field).nil?
      _current_id = legacy_id_pool.send(id_field)
      redis_id_pool.set(id_field, _current_id)
    end

    _id_range = (1..count).map do
      redis_id_pool.incr(id_field).to_s
    end

    # Save redis id sequences back to the old ldap id pool too. Not required
    # and has the same race condition issues but allows to fallback to it if
    # required.
    legacy_id_pool.send("#{id_field}=", _id_range.last)
    legacy_id_pool.save!

    _id_range
  end

  def self.last_id(id_field)
    get_redis_id_pool.get(id_field)
  end

  def self.next_id(id_field)
    id_range(id_field, 1).first
  end

  def self.set_id!(id_field, value)
    redis_id_pool = get_redis_id_pool
    legacy_id_pool = get_legacy_id_pool

    redis_id_pool.set(id_field, value)
    legacy_id_pool.send("#{id_field}=", value)
    legacy_id_pool.save!
  end

  private_class_method def self.get_redis_id_pool
    Redis::Namespace.new('idpool', redis: REDIS_CONNECTION)
  end

  private_class_method def self.get_legacy_id_pool
    IdPool.find('IdPool')
  end
end
