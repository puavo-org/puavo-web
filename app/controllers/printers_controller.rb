class PrintersController < ApplicationController
  # POST /devices/printers.json
  def create
    @printer = Printer.new(printer_params)

    respond_to do |format|
      if @printer.save
        format.json  { render :json => @printer, :status => :created }
      else
        format.json  { render :json => @printer.errors, :status => :unprocessable_entity }
      end
    end
  end

  # GET /devices/printers
  def index
    # Collect servers and group printers in them
    servers = {}

    Server.all.each do |s|
      servers[s.dn.to_s] = {
        hostname: s.puavoHostname,
        printers: []
      }
    end

    Printer.all.each do |p|
      next unless servers.include?(p.puavoServer.to_s)
      servers[p.puavoServer.to_s][:printers] << p
    end

    # Remove servers that have no printers
    servers.reject! { |dn, s| s[:printers].empty? }

    # Flatten and sort the servers list
    # TODO: This really needs a "natural" sort order, because
    # there can be tens of servers, usually named "bootXX"
    # where XX is an increasing number.
    @servers_and_printers = servers.values.sort do |a, b|
      a[:hostname].downcase <=>
      b[:hostname].downcase
    end

    # Finally sort the printers
    @servers_and_printers.each do |s|
      s[:printers].sort! do |a, b|
        a.printerDescription.downcase <=> b.printerDescription.downcase
      end
    end

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  # GET /devices/printers/1/edit
  def edit
    @printer = Printer.find(params[:id])

    @schools = School.find(
      :all,
      {
        :attribute => 'puavoPrinterQueue',
        :value => @printer.dn
      }
    )

    @schools_by_wireless = School.find(
      :all,
      {
        :attribute => 'puavoWirelessPrinterQueue',
        :value => @printer.dn
      }
    )

    @groups = Group.find(
      :all,
      {
        :attribute => 'puavoPrinterQueue',
        :value => @printer.dn
      }
    )

    @schools_by_groups = @groups.map do |group|
      [group, School.find(group.puavoSchool)]
    end

    @devices = Device.find(
      :all,
      {
        :attribute => 'puavoPrinterQueue',
        :value => @printer.dn
      }
    )

    @schools_by_devices = @devices.map do |device|
      [device, School.find(device.puavoSchool)]
    end

    respond_to do |format|
      format.html { render :action => "edit" }
    end
  end

  # PUT /devices/printers/1
  def update

    @printer = Printer.find(params[:id])

    respond_to do |format|
      if @printer.update_attributes(printer_params)
        flash[:notice] = t('flash.printer.updated')
        format.html { redirect_to(printers_path) }
      else
        format.html { render :action => "edit" }
      end
    end
  end

  # DELETE /devices/printers/1
  def destroy
    @printer = Printer.find(params[:id])
    @printer.destroy

    respond_to do |format|
      format.html { redirect_to(printers_url) }
    end
  end

  private
    def printer_params
      return params.require(:printer).permit(
        :puavoRule,             # used when editing a printer
        :printerDescription,    # (from here on) used when adding a printer
        :printerLocation,
        :printerMakeAndModel,
        :printerType,
        :printerURI,
        :puavoServer).to_hash
    end
end
