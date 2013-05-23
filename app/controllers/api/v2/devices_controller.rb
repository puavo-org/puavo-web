class Api::V2::DevicesController < ApplicationController

  # GET /devices
  # GET /devices.xml
  def index
    @devices = Device.search_as_utf8( :scope => :one,
                              :attributes => attributes ).map do |d|
      d.last
    end
    # FIXME: fix ldap_prettify api
    @devices = @devices.map{ |d| Device.new.ldap_prettify(d) }

    respond_to do |format|
      format.json  { render :json => @devices }
    end
  end

  def show
    device = Device.find(params[:id])
    # FIXME: fix ldap_prettify api
    @device = device.ldap_prettify(device)

    respond_to do |format|
      format.json  { render :json => @device }
    end
  end

  # FIXME: jpegPhoto attribute?
  def attributes
    [ "description",
      "ipHostNumber",
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
