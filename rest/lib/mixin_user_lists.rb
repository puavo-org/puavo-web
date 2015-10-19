require 'redis'

module PuavoRest
module MixinUserList

  module ClassMethods
    def all
      get_redis_user_list.scan_each.map do |key|
        by_id(key)
      end
    end

    def from_json(json)
      data = JSON.parse(json)
      user_list = new
      user_list.uuid = data["id"]
      user_list.created_at = data["created_at"]
      user_list.users = data["users"]
      user_list.school_id = data["school_id"]
      user_list.creator = data["creator"]
      user_list.downloaded = data["downloaded"]
      return user_list
    end

    def by_id(id)
      user_list = get_redis_user_list
      from_json(user_list.get(id))
    end

    def get_redis_user_list
      Redis::Namespace.new(
                           "user_lists",
                           :redis => REDIS_CONNECTION
                           )
    end

  end

  def self.included(base)
    base.send(:include, InstanceMethods)
    base.extend(ClassMethods)
  end


  module InstanceMethods
    def initialize(user_ids = nil, creator = nil)
      self.uuid = UUID.generate
      self.created_at = Time.now.to_i
      self.creator = creator
      self.downloaded = false
      self.users = user_ids
    end

    def as_json
      {
        "id" => self.uuid,
        "users" => self.users,
        "school_id" => self.school_id,
        "created_at" => self.created_at,
        "creator" => self.creator,
        "downloaded" => self.downloaded
      }
    end

    def to_json
      self.as_json.to_json
    end

    def save
      user_list = self.class.get_redis_user_list
      user_list.set(self.uuid, self.to_json)
      # Lifetime is about 6 moth
      user_list.expire(self.uuid, 60*60*24*30*6)
    end

    def remove
      self.class.get_redis_user_list.del(self.uuid)
    end
  end

end
end
