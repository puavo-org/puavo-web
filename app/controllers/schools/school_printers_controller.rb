class Schools::SchoolPrintersController < ApplicationController

  def index

    # TODO: limit printers to current school
    @printers = Printer.all

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  def show
    render :text => "asdf"
  end

  def edit
    respond_to do |format|
      format.html # edit.html.erb
    end
  end

end
