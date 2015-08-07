module PuavoImport

  class User

    @@users = []
    @@users_by_external_id = {}

    attr_accessor :external_id,
                  :first_name,
                  :last_name,
                  :email,
                  :telephone_number,
                  :preferred_language,
                  :username,
                  :group_external_id,
                  :group,
                  :school_external_id,
                  :school

    def initialize(args)
      args.keys.each do |k|
        args[k] = nil if args[k].empty?
        self.send("#{ k }=", args[k])
      end

      @school = PuavoRest::School.by_attr(:external_id, @school_external_id)
      raise "Cannot find school for user" if @school.nil?

      @group = PuavoRest::Group.by_attr(:external_id, @group_external_id)
      raise "Cannot find group for user" if @group.nil?

      @@users << self
      @@users_by_external_id[self.external_id] = self
    end

    def to_s
      "#{ self.first_name } #{ self.last_name } (external_id: #{ self.external_id })"
    end

    def need_update?(user)
      [ :first_name,
        :last_name,
        :email,
        :telephone_number,
        :preferred_language,
        :username
      ].each do |attr|
        return true if self.send(attr.to_s) != user[attr]
      end

      return true if self.school.dn != user.school.dn

      return false
    end

    def self.by_external_id(id)
      @@users_by_external_id[id]
    end

    def self.all
      @@users
    end

  end
end
