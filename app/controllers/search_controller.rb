class SearchController < ApplicationController
  layout false

  # GET /users/search?words=Williams
  def index
    words = Net::LDAP::Filter.escape( params[:words] )
    
    # Users search
    @users = ldap_search( 'user',
                          ["sn", "givenName", "uid"],
                          lambda{ |v| "#{v['sn'].first} #{v['givenName'].first}" },
                          lambda { |w| "(|(givenName=*#{w}*)(sn=*#{w}*)(uid=*#{w}*))" },
                          words )

    # Roles search
    @roles = ldap_search( 'role',
                            ['displayName'],
                            'displayName',
                            lambda { |w| "(displayName=*#{w}*)" },
                            words )

    # Groups search
    @groups = ldap_search( 'group',
                            ['displayName', 'cn'],
                            'displayName',
                            lambda { |w| "(|(displayName=*#{w}*)(cn=*#{w}*))" },
                            words )

    @schools = Hash.new
    School.search( :scope => :one,
                   :attributes => ["puavoId", "displayName"] ).map do |dn, v|
      @schools[v["puavoId"].first] = v["displayName"].first
    end

    respond_to do |format|
      if @users.length == 0 && @roles.length == 0 && @groups.length == 0
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
      { "id" => v["puavoId"].first,
        "school_id" => v["puavoSchool"].first.match(/^puavoId=([^,]+)/).to_a[1],
        "puavoSchool" => v["puavoSchool"].first,
        "name" => name_attribute_block.class == Proc ? name_attribute_block.call(v) : v[name_attribute_block]
      }.merge( attributes.inject({}) { |result, a|
                 result.merge(a => v[a])
               } )
    end.sort{ |a,b| a['name'] <=> b['name'] }
  end
end
