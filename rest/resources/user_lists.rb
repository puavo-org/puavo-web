require_relative "../lib/mixin_user_lists"

module PuavoRest
class UserList
  include PuavoRest::MixinUserList

  attr_accessor :uuid, :created_at, :school_id, :users, :users_by_groups,
                :creator, :downloaded

  def initialize(user_ids = nil, creator = nil)
    return if user_ids.nil?

    user = PuavoRest::User.by_id(user_ids.first)
    self.school_id = user.school.id

    super(user_ids, creator)
  end

end
end
