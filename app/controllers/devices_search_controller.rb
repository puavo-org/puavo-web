class DevicesSearchController < ApplicationController
  layout false

  # GET /devices/search?words=Williams
  def index
    words = Net::LDAP::Filter.escape( params[:words] )

    # Devices search
    @devices = ldap_search( 'device',
                            ['puavoHostname'],
                            'puavoHostname',
                            lambda { |w| "(cn=*#{w}*)" },
                            words )
    
    @schools = Hash.new
    School.search( :scope => :one,
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

  private

  def ldap_search(model, attributes, name_attribute_block, filter_block, words)
    filter = "(&" + words.split(" ").map do |w|
      filter_block.call(w)
    end.join() + ")"

    Module.class_eval(model.capitalize).search( :filter => filter,
                                                :scope => :one,
                                                :attributes => (["puavoId",
                                                                 "puavoSchool"] +
                                                                attributes) ).map do |dn, v|
      { "id" => v["puavoId"],
        "school_id" => v["puavoSchool"].first.match(/^puavoId=([^,]+)/)[1],
        "puavoSchool" => v["puavoSchool"].first,
        "name" => name_attribute_block.class == Proc ? name_attribute_block.call(v) : v[name_attribute_block]
      }.merge( attributes.inject({}) { |result, a|
                 result.merge(a => v[a])
               } )
    end.sort{ |a,b| a['name'] <=> b['name'] }
  end
end
