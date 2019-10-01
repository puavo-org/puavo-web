class QuickSearchController < ApplicationController
  layout false

  # GET /quick_search?words=Williams
  def index
    words = params[:query]

    @users = []
    @roles = []
    @groups = []
    @devices = []

    begin

      # Users search
      @users = User.words_search_and_sort_by_name(
        ["sn", "givenName", "uid"],
        lambda{ |v| "#{v['sn'].first} #{v['givenName'].first}" },
        lambda { |w| "(|(givenName=*#{w}*)(sn=*#{w}*)(uid=*#{w}*))" },
        words )

      # Groups search
      @groups = Group.words_search_and_sort_by_name(
        ['displayName', 'cn'],
        'displayName',
        lambda { |w| "(|(displayName=*#{w}*)(cn=*#{w}*))" },
        words )

      # Devices search
      @devices = Device.words_search_and_sort_by_name(
        ['puavoHostname'],
        'puavoHostname',
        lambda { |w| "(cn=*#{w}*)" },
        words )

      @devices.sort!{|a, b| a["name"].downcase <=> b["name"].downcase }

      @schools = Hash.new
      School.search_as_utf8( :scope => :one,
                     :attributes => ["puavoId", "displayName"] ).map do |dn, v|
        @schools[v["puavoId"].first] = v["displayName"].first
      end

      # I don't know how "words_search_and_sort_by_name" sorts, but it
      # doesn't seem to work
      @users.sort!{|a, b| a["name"].downcase <=> b["name"].downcase }
      @groups.sort!{|a, b| a["name"].downcase <=> b["name"].downcase }

      respond_to do |format|
        if @users.length == 0 && @roles.length == 0 && @groups.length == 0 && @devices.length == 0
          format.html { render :inline => "<p>#{t('search.no_matches')}</p>" }
        else
          format.html # index.html.erb
        end
      end

    rescue StandardError => e
      render :inline => "<p class=\"searchError\">#{t('search.failed')}</p>"
    end

  end

end
