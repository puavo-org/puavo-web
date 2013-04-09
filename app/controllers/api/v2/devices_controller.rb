class Api::V2::DevicesController < ApplicationController

  # GET /devices
  # GET /devices.xml
  def index
    @devices = Device.search( :scope => :one,
                              :attributes => attributes ).map do |d|
      d.last
    end
    @devices = @devices.map{ |d| Device.build_hash_for_to_json(d) }

    respond_to do |format|
      format.json  { render :json => @devices }
    end
  end

  def show
    @device = Device.build_hash_for_to_json( Device.find(params[:id]).attributes )

    respond_to do |format|
      format.json  { render :json => @device }
    end
  end


  def attributes
    [ "description",
      "ipHostNumber",
      "jpegPhoto",
      "macAddress",
      "puavoDefaultPrinter",
      "puavoDeviceAutoPowerOffMode",
      "puavoDeviceBootMode",
      "puavoDeviceManufacturer",
      "puavoDeviceModel",
      "puavoLatitude",
      "puavoLocationName",
      "puavoLongitude",
      "puavoPurchaseDate",
      "puavoPurchaseLocation",
      "puavoPurchaseURL",
      "puavoSupportContract",
      "puavoTag",
      "puavoWarrantyEndDate",
      "serialNumber",
      "puavoSchool",
      "puavoHostname",
      "puavoId" ]
  end
end
