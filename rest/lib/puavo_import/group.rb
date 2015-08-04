module PuavoImport

  class Group

    @@groups = []
    @@groups_by_external_id = {}

    attr_accessor :name,
                  :external_id,
                  :abbreviation,
                  :school_external_id,
                  :school

    def initialize(args)
      @name = args[:name]
      @external_id = args[:external_id]
      @school_external_id = args[:school_external_id]

      @school = PuavoRest::School.by_attr(:external_id, @school_external_id)
      raise RuntimeError => "Cannot find school for group" if @school.nil?

      @abbreviation = @school.abbreviation + "-" + PuavoImport.sanitize_name(@name)

      @@groups << self
      @@groups_by_external_id[self.external_id] = self
    end

    def to_s
      "#{ self.name } (external_id: #{ self.external_id })"
    end

    def self.by_external_id(id)
      @@groups_by_external_id[id]
    end

    def self.all
      @@groups
    end

  end
end
