class Api::V2::ServersController < ApplicationController

  # GET /servers/1.json
  def show
    @server = Server.build_hash_for_to_json( Server.find(params[:id]).attributes )
    
    respond_to do |format|
      format.json  { render :json => @server }
    end
  end
end
