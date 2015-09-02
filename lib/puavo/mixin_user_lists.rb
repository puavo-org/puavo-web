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
      user_list.users = data["users"]
      user_list.school_id = data["school_id"]
      user_list.users_by_groups = data["users_by_groups"]
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
    def initialize(user_ids = nil)
      return if user_ids.nil?

      @uuid = UUID.generate
      @school_id = nil
      @users = []
      @users_by_groups = {}

      user_ids.each do |user_id|
        user = PuavoRest::User.by_id(user_id)
        @users.push(user.id)

        @school_id = user.school.id if @school_id.nil?

        group = user.groups.first

        # FIXME: many groups for user?
        unless @users_by_groups.has_key?(group.id)
          @users_by_groups[group.id] = []
        end

        @users_by_groups[group.id].push(user.id)
      end

    end

    def as_json
      {
        "id" => @uuid,
        "users" => @users,
        "school_id" => @school_id,
        "users_by_groups" => @users_by_groups,
        "created_at" => "",
        "creator" => ""
      }
    end

    def to_json
      self.as_json.to_json
    end

    def save
      user_list = self.class.get_redis_user_list
      user_list.set(@uuid, self.to_json)
    end
  end

end
end
