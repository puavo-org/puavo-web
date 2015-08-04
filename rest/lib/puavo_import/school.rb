module PuavoImport

  class School

    @@schools = []
    @@schools_by_external_id = {}

    attr_accessor :name, :external_id, :abbreviation

    def initialize(args)
      @name = args[:name]
      @external_id = args[:external_id]

      @abbreviation = PuavoImport.sanitize_name(@name)

      @@schools << self
      @@schools_by_external_id[self.external_id] = self
    end

    def to_hash
      { :name => self.name,
        :external_id => self.external_id }
    end

    def to_s
      "#{ self.name } (external_id: #{ self.external_id })"
    end

    def need_update?(school)
      self.name != school.name
    end

    def self.by_external_id(id)
      @@schools_by_external_id[id]
    end

    def self.all
      @@schools
    end

  end
end
