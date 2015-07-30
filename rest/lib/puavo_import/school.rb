module PuavoImport

  class School

    @@schools = []
    @@schools_by_external_id = {}

    attr_accessor :name, :external_id

    def initialize(args)
      @name = args[:name]
      @external_id = args[:external_id]

      @@schools << self
      @@schools_by_external_id[self.external_id] = self
    end

    def self.by_external_id(id)
      @@schools_by_external_id[id]
    end

    def self.all
      @@schools
    end

  end
end
