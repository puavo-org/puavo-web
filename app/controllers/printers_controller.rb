class PrintersController < ApplicationController
  
  # POST /devices/printers.json
  def create
    @printer = Printer.new(params[:printer])

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
    @servers_and_printers = Server.all.inject({ }) do |result, server|
      result.merge( { server.dn.first => { :server => server} } )
    end

    Printer.all.each do |printer|
      unless @servers_and_printers[printer.puavoServer.to_s].has_key?(:printers)
        @servers_and_printers[printer.puavoServer.to_s][:printers] = Array.new
      end
      @servers_and_printers[printer.puavoServer.to_s][:printers].push(printer)
    end

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  # GET /devices/printers/1/edit
  def edit
    @printer = Printer.find(params[:id])
  end

  # PUT /devices/printers/1
  def update
    @printer = Printer.find(params[:id])

    respond_to do |format|
      if @printer.update_attributes(params[:printer])
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

end
