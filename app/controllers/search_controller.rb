class SearchController < ApplicationController
  layout false

  # GET /users/search?words=Williams
  def index
    words = params[:words].delete("()&|!=~<>*")
    filter = words.split(" ").map do |w|
      "(|(givenName=#{w}*)(sn=#{w}*))"
    end.join()
    filter = "(&#{filter})"

    @objects = User.search( :filter => filter,
                            :scope => :one,
                            :attributes => ["puavoId", "puavoSchool", "sn", "givenName"] ).map do |dn, v|
      { "id" => v["puavoId"],
        "school_id" => v["puavoSchool"].to_s.match(/^puavoId=([^,]+)/)[1],
        "name" => "#{v['sn']} #{v['givenName']}" }
    end

    respond_to do |format|
      if @objects.length > 0
        @objects = @objects.sort{ |a,b| a['name'] <=> b['name'] }
        @schools = Hash.new
        School.search( :scope => :one,
                       :attributes => ["puavoId", "displayName"] ).map do |dn, v|
          @schools[v["puavoId"].to_s] = v["displayName"].to_s
        end
        format.html # index.html.erb
      end
      format.html { render :inline => '' }
    end
  end
end
