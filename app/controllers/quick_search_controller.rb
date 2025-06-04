class QuickSearchController < ApplicationController
  layout false

  # GET /quick_search?words=Williams
  def index
    words = params[:query].split(' ').map { |q| Net::LDAP::Filter.escape(q) }

    # Search results
    @users = []
    @groups = []
    @devices = []
    @servers = []

    # Schools lookup
    @schools_cache = {}

    is_owner = current_user.organisation_owner?
    admin_schools = Array(current_user.puavoAdminOfSchool).map { |dn| puavoid_from_dn(dn.to_s) }.to_set

    begin
      # Users. User searches can have multiple words.
      # ACLs prevent admins from seeing users from schools they're not an admin of.
      filter_parts = words.collect { |w| "(|(givenName=*#{w}*)(sn=*#{w}*)(uid=*#{w}*))" }

      User.search_as_utf8(
        scope: :one,
        filter: "(&#{filter_parts.join})",
        attributes: ['puavoId', 'givenName', 'sn', 'uid', 'puavoEduPersonPrimarySchool']
      ).collect do |u|
        u = u[1]

        name = "#{u['sn'][0]}, #{u['givenName'][0]}"
        id = u['puavoId'][0]
        school_id = puavoid_from_dn(u['puavoEduPersonPrimarySchool'][0])
        cache_school(@schools_cache, school_id)

        @users << {
          id: id,
          name: name,
          uid: u['uid'][0],
          sortable_name: name.downcase,
          school_id: school_id,
          link: "/users/#{school_id}/users/#{id}",
        }
      end

      @users.sort! { |a, b| a[:sortable_name] <=> b[:sortable_name] }

      # Groups
      Group.search_as_utf8(
        scope: :one,
        filter: "(&(|(displayName=*#{words[0]}*)(cn=*#{words[0]}*)))",
        attributes: ['puavoId', 'displayName', 'cn', 'puavoSchool']
      ).each do |g|
        g = g[1]

        id = g['puavoId'][0]
        school_id = puavoid_from_dn(g['puavoSchool'][0])

        next unless is_owner || admin_schools.include?(school_id)

        cache_school(@schools_cache, school_id)

        @groups << {
          id: id,
          name: g['displayName'][0],
          sortable_name: g['displayName'][0].downcase,
          abbreviation: g['cn'][0],
          school_id: school_id,
          link: "/users/#{school_id}/groups/#{id}"
        }
      end

      @groups.sort! { |a, b| a[:sortable_name] <=> b[:sortable_name] }

      # Devices search
      Device.search_as_utf8(
        scope: :one,
        filter: "(|(puavoHostname=*#{words[0]}*)(puavoDisplayName=*#{words[0]}*))",
        attributes: ['puavoId', 'puavoHostname', 'puavoSchool', 'puavoDisplayName']
      ).each do |d|
        d = d[1]

        # ACLs prevent users from seeing the school attribute if they're not an admin
        # in that school
        next unless d.include?('puavoSchool')

        id = d['puavoId'][0]
        school_id = puavoid_from_dn(d['puavoSchool'][0])
        cache_school(@schools_cache, school_id)

        @devices << {
          id: id,
          name: d['puavoHostname'][0],
          display_name: d.fetch('puavoDisplayName', [nil])[0],
          school_id: school_id,
          link: "/devices/#{school_id}/devices/#{id}"
        }
      end

      @devices.sort! { |a, b| a[:name] <=> b[:name] }

      # Bootservers search (owners only)
      if is_owner
        Server.search_as_utf8(
          scope: :one,
          filter: "(puavoHostname=*#{words[0]}*)",
          attributes: ['puavoId', 'puavoHostname']
        ).each do |s|
          s = s[1]

          id = s['puavoId'][0]

          @servers << {
            id: id,
            name: s['puavoHostname'][0],
            link: "/devices/servers/#{id}"
          }
        end

        @servers.sort! { |a, b| a[:name] <=> b[:name] }
      end

      respond_to do |format|
        if @users.empty? && @groups.empty? && @devices.empty? && @servers.empty?
          format.html { render inline: "<p>#{t('search.no_matches')}</p>" }
        else
          format.html   # index.html.erb
        end
      end
    rescue StandardError => e
      puts e
      render inline: "<p class=\"searchError\">#{t('search.failed')}</p>"
    end
  end

private

  # TODO: There are multiple similar methods like this scattered everywhere in the codebase.
  # Merge them.
  def puavoid_from_dn(dn)
    dn.match(/^puavoId=([^,]+)/).to_a[1]
  end

  def cache_school(cache, id)
    return if cache.include?(id)

    s = School.search_as_utf8(
      scope: :one,
      filter: "(puavoId=#{id})",
      attributes: ['displayName'])

    if s.nil? || s.empty?
      cache[id] = {
        name: '?',
        link: '',
      }
    else
      cache[id] = {
        name: s[0][1]['displayName'][0],
        link: "/users/schools/#{id}",
      }
    end
  end
end
