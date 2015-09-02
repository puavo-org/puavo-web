require_relative "../../lib/puavo/mixin_user_lists"

module PuavoRest
class UserLists
  include Puavo::MixinUserLists

  attr_accessor :uuid, :school_id, :users, :users_by_groups


end
end
