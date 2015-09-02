require "puavo/mixin_user_lists"

class List
  include Puavo::MixinUserLists

  attr_accessor :uuid, :school_id, :users, :users_by_groups

end
