class Api::V2::HostsController < ApplicationController

  class DeviceNotFound < StandardError
  end

  # POST /hosts/:hostname/sign_certificate
  def sign_certificate

    allowed_device_type = ["ltspserver", "bootserver", "infotv"]

    begin
      @host = Server.find(:first, :attribute => "puavoHostname", :value => params[:hostname])

      if @host.nil?
        @host = Device.find(:first, :attribute => "puavoHostname", :value => params[:hostname])
      end

      if @host.nil?
        raise DeviceNotFound
      end

      @host.revoke_certificate( session[:organisation].organisation_key,
                                @authentication.dn,
                                @authentication.password )
      @host.host_certificate_request = params[:host_certificate_request]
      @host.sign_certificate( session[:organisation].organisation_key,
                              @authentication.dn,
                              @authentication.password )

      render :json => @host

    rescue DeviceNotFound
      render :status => 404, :json => { :error => "Device not found (#{ params[:hostname] })" }
    end
  end
end
