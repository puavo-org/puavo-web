# -*- coding: utf-8 -*-
module PuavoImport

  class School

    @@schools = []
    @@schools_by_external_id = {}

    attr_accessor :name, :external_id, :abbreviation, :school_code

    OVERWRITE_CHARACTERS = {
      "ä" => "a",
      "ö" => "o",
      "å" => "a",
      "é" => "e",
    }

    def initialize(args)
      @name = args[:name]
      @external_id = args[:external_id]
      @abbreviation = abbreviation_escape(args[:abbreviation])
      @school_code = args[:school_code]

      @@schools << self
      @@schools_by_external_id[self.external_id] = self
    end

    def to_hash
      { :name => self.name,
        :external_id => self.external_id,
        :school_code => self.school_code }
    end

    def to_s
      "#{ self.name } (external_id: #{ self.external_id })"
    end

    def need_update?(school)
      self.name != school.name ||
        self.abbreviation != school.abbreviation ||
        self.school_code != school.school_code
    end

    def self.by_external_id(id)
      @@schools_by_external_id[id]
    end

    def self.all
      @@schools
    end

    private

    def abbreviation_escape(string)
      string = string.encode('utf-8', 'ISO8859-1')
      string = string.downcase
      string.strip.split(//).map do |char|
        OVERWRITE_CHARACTERS.has_key?(char) ? OVERWRITE_CHARACTERS[char] : char
      end.join.downcase.gsub(/[^0-9a-z-]/, '')
    end

  end
end
