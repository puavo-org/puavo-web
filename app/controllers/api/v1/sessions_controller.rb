class Api::V1::SessionsController < ApplicationController

  def show
    @user = current_user

    respond_to do |format|
      format.json  { render :json => @user.v1_as_json(:methods => :managed_schools) }
    end
  end

end
