require_relative "../../lib/puavo/mixin_user_lists"

module PuavoRest
class UserLists
  include Puavo::MixinUserLists

  attr_accessor :uuid, :created_at, :school_id, :users, :users_by_groups,
                :creator, :downloaded


end
end
