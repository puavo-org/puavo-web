module PuavoImport

  class RestUser < PuavoRest::User
    @@teacher_group_suffix = nil

    def self.teacher_group_suffix=(suffix)
      @@teacher_group_suffix = suffix
    end
    def self.teacher_group_suffix
      @@teacher_group_suffix
    end

    def import_group_name
      if self.roles.include?("teacher")
        group = PuavoRest::Group.by_attrs(:abbreviation => "#{ school.abbreviation }-#{ @@teacher_group_suffix }",
                                          :school_dn => school.dn)
      else
        group  = self.group_by_type('teaching group')
      end

      return "" if group.nil?

      return group.name
    end

  end

end
