module PuavoImport

  class UserRoleError < StandardError; end
  class UserGroupError < StandardError; end

  class User

    @@users = []
    @@users_by_external_id = {}

    attr_accessor :db_id,
                  :external_id,
                  :first_name,
                  :given_names,
                  :last_name,
                  :email,
                  :telephone_number,
                  :preferred_language,
                  :username,
                  :role,
                  :teacher_group_name,
                  :teacher_group_suffix,
                  :group_external_id,
                  :group,
                  :school_external_ids,
                  :schools

    def initialize(args)
      args.keys.each do |k|
        next if args[k].nil?
        args[k] = nil if args[k].empty?
        self.send("#{ k }=", args[k])
      end

      raise(UserRoleError, "Invalid role of user. --user-role is required param") if @role.nil?

      case @role
      when "student"
        @group = PuavoRest::Group.by_attr(:external_id, @group_external_id)
        raise(UserGroupError,
              "Cannot find group (external_id: #{ @group_external_id }) for student: #{ self.to_s }") if @group.nil?
      when "teacher"
        @group = PuavoRest::Group.by_attr(:abbreviation, "#{ @school.abbreviation }-#{ @teacher_group_suffix }")
        raise(UserGroupError,
              "Cannot find group (external_id: #{ @group_external_id }) for teacher: #{ self.to_s }") if @group.nil?
      end

      @@users << self
      @@users_by_external_id[self.external_id] = self
    end

    def schools
      return [] if @school_external_ids.nil?

      @schools ||= @school_external_ids.uniq.map do |external_id|
        PuavoRest::School.by_attr(:external_id, external_id)
      end.compact
    end

    def import_group_name
      return if @group.nil?
      group.name
    end

    def import_school_names
      schools.map{ |s| s.name }.join(", ")
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
