class ImportToolController < ApplicationController
  def index
    @school = School.find(params["id"])
  end
end
