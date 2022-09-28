require_relative "../../rest/lib/mixin_user_lists"

class List
  include PuavoRest::MixinUserList

  attr_accessor :uuid, :created_at, :school_id, :users, :users_by_groups,
                :creator, :downloaded, :description

  def initialize(user_ids = nil, creator = nil, description = nil)
    return if user_ids.nil?

    user = User.find(user_ids.first)
    self.school_id = user.primary_school.puavoId
    self.description = description

    super(user_ids, creator, description)
  end

end
