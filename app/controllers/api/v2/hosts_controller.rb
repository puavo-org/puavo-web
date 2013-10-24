class Api::V2::HostsController < ApplicationController

  # POST /hosts/:hostname/sign_certificate
  def sign_certificate
    @host = Server.find(:first, :attribute => "puavoHostname", :value => params[:hostname])

    if @host.nil?
      @host = Device.find(:first, :attribute => "puavoHostname", :value => params[:hostname])
    end


    @host.revoke_certificate( session[:organisation].organisation_key,
                              @authentication.dn,
                              @authentication.password )
    @host.host_certificate_request = params[:host_certificate_request]
    @host.sign_certificate( session[:organisation].organisation_key,
                            @authentication.dn,
                            @authentication.password )

    render :json => @host
  end
end
