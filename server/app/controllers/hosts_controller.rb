class HostsController < ApplicationController
  # GET /hosts
  # GET /hosts.xml
  # GET /hosts.json
  def index
    @hosts = Host.all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @hosts }
      format.json  { render :json => @hosts }
    end
  end

  def types
    respond_to do |format|
      format.html # index.html.erb
      format.json # index.json.erb
    end
  end

end
