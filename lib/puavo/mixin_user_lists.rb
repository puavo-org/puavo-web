require 'redis'

module Puavo
module MixinUserLists

  module ClassMethods
    def all
      get_redis_user_list.scan(0)[1].map do |key|
        by_id(key)
      end
    end

    def from_json(json)
      puts json
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
      return if user_ids.nil?

      self.uuid = UUID.generate
      self.created_at = Time.now.to_i
      self.creator = creator
      self.downloaded = false
      self.school_id = nil
      self.users = []

      user_ids.each do |user_id|
        user = PuavoRest::User.by_id(user_id)
        self.users.push(user.id)

        self.school_id = user.school.id if self.school_id.nil?
      end

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
    end

    def remove
      self.class.get_redis_user_list.del(self.uuid)
    end
  end

end
end
