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


class UserLists < PuavoSinatra
  post "/v3/schools/:school_id/user_lists" do
    auth :basic_auth, :kerberos

    school = School.by_id!(params["school_id"])
    user_ids = json_params["ids"]

    # XXX Pass school.id to here when it excepts it
    list = UserList.new(user_ids)
    list.save
    json({"id" => list.uuid })
  end

  get "/v3/schools/:school_id/user_lists" do
    auth :basic_auth, :kerberos
    school = School.by_id!(params["school_id"]) # Just assert the school existence
    json(UserList.all)
  end

  get "/v3/schools/:school_id/user_lists/:id" do
    auth :basic_auth, :kerberos
    school = School.by_id!(params["school_id"])
    list = UserList.by_id(params["id"])
    json list
  end
end

end
