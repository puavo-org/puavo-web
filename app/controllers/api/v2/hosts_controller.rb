class Api::V2::HostsController < ApplicationController

  # POST /hosts/:hostname/sign_certificate
  def sign_certificate
    # @server = Server.build_hash_for_to_json( Server.find(params[:id]).attributes )
    @host = Server.find(:first, :attribute => "puavoHostname", :value => params[:hostname])

    unless @host
      @host = Device.(:first, :attribute => "puavoHostname", :value => params[:hostname])
    end

    # @host.reveko_certificate
    # @host.sign_certificate
    
    respond_to do |format|
      format.json  { render :json => @host }
    end
  end
end
