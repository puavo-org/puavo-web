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
                  :role, # Role of primary school
                  :teacher_group,
                  :teacher_group_name,
                  :teacher_group_suffix,
                  :teaching_group_external_id,
                  :teaching_group,
                  :year_class,
                  :school_external_id,
                  :school,
                  :secodary_school_external_ids,
                  :secondary_schools

    def initialize(args)
      args.keys.each do |k|
        next if args[k].nil?
        args[k] = nil if args[k].empty?
        self.send("#{ k }=", args[k])
      end

      raise(UserRoleError, "Invalid role of user. --user-role is required param") if @role.nil?

      case @role
      when "student"
        @teaching_group = PuavoRest::Group.by_attr(:external_id, @teaching_group_external_id)
        raise(UserGroupError,
              "Cannot find group (external_id: #{ @teaching_group_external_id }) for student: #{ self.to_s }") if @teaching_group.nil?
      when "teacher"
        @teacher_group = PuavoRest::Group.by_attrs(:abbreviation => "#{ school.abbreviation }-#{ @teacher_group_suffix }",
                                           :school_dn => school.dn)
        raise(UserGroupError,
              "Cannot find group (abbreviation: " +
              school.abbreviation +
              "-" +
              @teacher_group_suffix +
              " for teacher: " +
              self.to_s) if @teacher_group.nil?
      end

      @@users << self
      @@users_by_external_id[self.external_id] = self
    end

    def school
      return @school unless @school.nil?
      return if @school_external_id.nil?

      @school = PuavoRest::School.by_attr(:external_id, @school_external_id)
    end

    def secondary_schools
      @secondary_schools ||= @secodary_school_external_ids.uniq.map do |external_id|
        PuavoRest::School.by_attr(:external_id, external_id)
      end.compact
    end

    def import_group_name
      case self.role
      when "teacher"
        return "" if @teacher_group.nil?
        @teacher_group.name
      when "student"
        return "" if @teaching_group.nil?
        @teaching_group.name
      end
    end

    def import_school_name
      return "" if school.nil?
      return school.name
    end

    def to_s
      {
        "db_id" => self.db_id,
        "external_id" => self.external_id,
        "first_name" => self.first_name,
        "given_names" => self.given_names,
        "last_name" => self.last_name,
        "import_group_name" => self.import_group_name,
        "school_external_id" => self.school_external_id,
        "school_name" => self.import_school_name
      }.inspect
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
