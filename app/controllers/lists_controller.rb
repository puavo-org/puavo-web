class ListsController < ApplicationController

  # GET /users/:school_id/lists
  def index

    @lists = List.all

    respond_to do |format|
      format.html
    end
  end

end
