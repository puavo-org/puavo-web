class ImportToolController < ApplicationController
  def index
    @school = School.find(params["school_id"])
    @school_json = {
      "dn" => @school.dn.to_s,
      "id" => @school.puavo_id
    }.to_json
  end
end
