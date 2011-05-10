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
    @printers = Printer.all

    respond_to do |format|
      format.html # index.html.erb
    end
  end
end
