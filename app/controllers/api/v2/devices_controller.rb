class Api::V2::DevicesController < ApplicationController

  # GET /devices
  # GET /devices.xml
  def index
    attributes = Device.new.prettify_attributes.map{ |a| a[:original_attribute_name] }
    @devices = Device.search_as_utf8( :scope => :one,
                                      :attributes => attributes ).map do |d|
      d.last
    end
    @devices = @devices.map{ |d| Puavo::Client::Base.new_by_ldap_entry(d) }

    respond_to do |format|
      format.json  { render :json => @devices }
    end
  end

  def show
    device = Device.find(params[:id])
    @device = device.ldap_prettify

    respond_to do |format|
      format.json  { render :json => @device }
    end
  end

  def by_hostname
    device = Device.find(:first, :attribute => "puavoHostname", :value => params[:hostname] )
    @device = device.ldap_prettify

    respond_to do |format|
      format.json  { render :json => @device }
    end
  end
end
