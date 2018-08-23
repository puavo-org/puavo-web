class UsersSearchController < ApplicationController
  layout false

  # GET /users/search?words=Williams
  def index
    words = params[:words]

    # Users search
    @users = User.words_search_and_sort_by_name(
      ["sn", "givenName", "uid"],
      lambda{ |v| "#{v['sn'].first} #{v['givenName'].first}" },
      lambda { |w| "(|(givenName=*#{w}*)(sn=*#{w}*)(uid=*#{w}*))" },
      words )

    # Roles search
    @roles = Role.words_search_and_sort_by_name(
      ['displayName'],
      'displayName',
      lambda { |w| "(displayName=*#{w}*)" },
      words )

    # Groups search
    @groups = Group.words_search_and_sort_by_name(
      ['displayName', 'cn'],
      'displayName',
      lambda { |w| "(|(displayName=*#{w}*)(cn=*#{w}*))" },
      words )

    @schools = Hash.new
    School.search_as_utf8( :scope => :one,
                   :attributes => ["puavoId", "displayName"] ).map do |dn, v|
      @schools[v["puavoId"].first] = v["displayName"].first
    end

    # I don't know how "words_search_and_sort_by_name" sorts, but it
    # doesn't seem to work. Schools are in a hash, can't sort them.
    @users.sort!{|a, b| a["name"].downcase <=> b["name"].downcase }
    @groups.sort!{|a, b| a["name"].downcase <=> b["name"].downcase }

    respond_to do |format|
      if @users.length == 0 && @roles.length == 0 && @groups.length == 0
        format.html { render :inline => '' }
      else
        format.html # index.html.erb
      end
    end
  end

end
