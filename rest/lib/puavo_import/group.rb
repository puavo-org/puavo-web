module PuavoImport

  class Group

    attr_accessor :name,
                  :external_id,
                  :school_external_id

    def initialize(args)
      @name = args[:name]
      @external_id = args[:external_id]
      @school_external_id = args[:school_external_id]
    end

    def school
      @school ||= PuavoRest::School.by_attr(:external_id, @school_external_id)
    end

    def abbreviation
      school.abbreviation + "-" + PuavoImport.sanitize_name(@name)
    end

    def to_s
      "#{ self.name } (external_id: #{ self.external_id })"
    end

    def need_update?(group)
      return true if self.name != group.name

      return true if self.abbreviation != group.abbreviation

      return true if self.school.dn != group.school_dn

      return false
    end

  end
end
