class DevicesSearchController < ApplicationController
  layout false

  # GET /devices/search?words=Williams
  def index
    words = params[:words]

    # Devices search
    @devices = Device.words_search_and_sort_by_name(
      ['puavoHostname'],
      'puavoHostname',
      lambda { |w| "(cn=*#{w}*)" },
      words )
    
    @schools = Hash.new
    School.search_as_utf8( :scope => :one,
                   :attributes => ["puavoId", "displayName"] ).map do |dn, v|
      @schools[v["puavoId"].first] = v["displayName"].first
    end

    respond_to do |format|
      if @devices.length == 0
        format.html { render :inline => '' }
      else
        format.html # index.html.erb
      end
    end

  end
end
