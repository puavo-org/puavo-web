class Schools::SchoolPrintersController < ApplicationController

  def index
   respond_to do |format|
      format.html # index.html.erb
    end
  end

  def edit
    @printer = Printer.find(params["id"])
  end

  def update
    @printer = Printer.find(params["id"])

    if params["activate"] || params["activate_wireless"]
      @school.add_printer(@printer)
    else
      @school.remove_printer(@printer)
    end

    if params["activate_wireless"]
      @school.add_wireless_printer(@printer)
    else
      @school.remove_wireless_printer(@printer)
    end

    (params["groups"] || {}).each do |group_dn, bool|
      group = Group.find(group_dn)
      if bool == "true"
        group.add_printer(@printer)
      else
        group.remove_printer(@printer)
      end
      group.save!
    end

    @school.save!
    redirect_to :action => :edit
  end

end
