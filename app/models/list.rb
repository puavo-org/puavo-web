require "puavo/mixin_user_lists"

class List
  include Puavo::MixinUserLists

  attr_accessor :uuid, :created_at, :school_id, :users, :users_by_groups,
                :creator, :downloaded

  def initialize(user_ids = nil, creator = nil)
    return if user_ids.nil?

    user = User.find(user_ids.first)
    self.school_id = user.school.puavoId

    super(user_ids, creator)
  end

end
