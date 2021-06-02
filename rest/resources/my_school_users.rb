require 'sinatra/r18n'

module PuavoRest

class MySchoolUsers < PuavoSinatra

  # Attributes to fetch in raw queries
  USER_ATTRIBUTES = [
    'puavoId'.freeze,
    'givenName'.freeze,
    'sn'.freeze,
    'uid'.freeze,
    'puavoEduPersonAffiliation'.freeze,
    'puavoSchool'.freeze,
    'puavoEduPersonPrimarySchool'.freeze,
    'puavoRemovalRequestTime'.freeze,
  ].freeze

  GROUP_ATTRIBUTES = [
    'cn'.freeze,
    'displayName'.freeze,
    'puavoSchool'.freeze,
    'puavoEduGroupType'.freeze,
    'memberUid'.freeze,
  ].freeze

  get '/v3/my_school_users' do
    auth :basic_auth, :kerberos

    viewer = User.current

    # only let teachers, admins and staff members view this page
    unless (Array(viewer.user_type) & ['teacher', 'staff', 'admin']).any?
      halt 401, 'Unauthorized'
    end

    school = viewer.school
    target_school_dn = school.dn.to_s

    groups_by_id = {}   # IDs are group abbreviations
    ungrouped = []      # students who are not in any group
    group_num = 0

    # Iterating over school.member_dns is handy but slooooow. So instead do some raw searches,
    # then filter and combine data ourselves. It's a lot more code, but the speedup is worth it.
    base = Organisation.current['base']

    groups_by_dn = {}
    groups_by_username = {}   # fast user groups lookup

    Group.raw_filter("ou=Groups,#{base}",
                     "(&(objectClass=puavoEduGroup)(puavoSchool=#{target_school_dn})(puavoEduGroupType=teaching group))",
                     GROUP_ATTRIBUTES).each do |raw_group|

      dn = raw_group['dn'][0].force_encoding('UTF-8')

      Array(raw_group['memberUid'] || []).each do |uid|
        uid.force_encoding('UTF-8')
        groups_by_username[uid] ||= Set.new
        groups_by_username[uid] << dn
      end

      groups_by_dn[dn] = {
        abbr: raw_group['cn'][0].force_encoding('UTF-8'),
        name: raw_group['displayName'][0].force_encoding('UTF-8'),
      }
    end

    User.raw_filter("ou=People,#{base}",
                    "(objectClass=*)",
                    USER_ATTRIBUTES).each do |raw_user|

      # List only students
      next if !raw_user.include?('puavoEduPersonAffiliation') ||
              !raw_user['puavoEduPersonAffiliation'].include?('student')

      # Don't show students who have been marked for deletion
      next if raw_user.include?('puavoRemovalRequestTime') && raw_user['puavoRemovalRequestTime'] != nil

      # School filtering
      if raw_user.include?('puavoEduPersonPrimarySchool')
        primary_school = raw_user['puavoEduPersonPrimarySchool'][0]
      else
        primary_school = Array(raw_user['puavoSchool'])[0]
      end

      primary_school.force_encoding('UTF-8')
      next unless primary_school == target_school_dn

      uid = raw_user['uid'][0].force_encoding('UTF-8')

      u_data = {
        first: raw_user['givenName'][0].force_encoding('UTF-8'),
        last: raw_user['sn'][0].force_encoding('UTF-8'),
        username: uid,
      }

      teaching_group = nil

      if groups_by_username.include?(uid)
        # In theory, users should not be in multiple teaching groups at the same time.
        # But this is an artificial restriction, so pick the first we have and hope
        # for the best.
        teaching_group = groups_by_dn[groups_by_username[uid].first]
      end

      if teaching_group
        id = teaching_group[:abbr]

        unless groups_by_id.include?(id)
          groups_by_id[id] = {
            name: teaching_group[:name],
            id: "#{id}-#{group_num}",
            users: []
          }

          group_num += 1
        end

        groups_by_id[id][:users] << u_data
      else
        ungrouped << u_data
      end
    end

    @data = {}
    @data[:school] = school.name
    @data[:domain] = "#{request.scheme}://#{User.organisation.domain}"
    @data[:changing] = viewer.username

    # the groups aren't necessarily in any order, so sort them and always
    # put the ungrouped users at the end
    @data[:groups] = groups_by_id.values.sort! do |a, b|
      a[:name].downcase <=> b[:name].downcase
    end

    unless ungrouped.empty?
      @data[:groups] << {
        name: :ungrouped,
        id: "ungrouped-#{group_num}",
        users: ungrouped
      }
    end

    # Alphabetically sort the users in each group. First by last name, then by first name(s).
    @data[:groups].each do |g|
      g[:users].sort! do |a, b|
        [a[:last].downcase, a[:first].downcase] <=> [b[:last].downcase, b[:first].downcase]
      end
    end

    # Localize the page. The HTTP accept languages are sorted by priority,
    # we'll choose the *first* that we have a translation for and stop.
    # If there are no matches, use English.
    languages = Array(request.accept_language).sort_by { |l| l[1] }.reverse

    lang = nil

    languages.each do |l|
      if l[0].start_with?('en')
        lang = setup_language('english')
        break
      elsif l[0].start_with?('fi')
        lang = setup_language('finnish')
        break
      elsif l[0].start_with?('de')
        lang = setup_language('german')
        break
      end
    end

    @data[:language] = lang || setup_language('english')

    halt 200, { 'Content-Type' => 'text/html' },
      erb('my_school_users.erb', :data => @data, :layout => :my_school_users)
  end

private

  # There is no error handling here. You must pass in a valid language name or you'll suffer.
  def setup_language(code)
    case code
      when 'english'
        return {
          html_lang: 'en',
          page_title: "School Students List",
          # -----
          users: 'users',
          ungrouped: 'No teaching group',
          # -----
          search_placeholder: 'Search by name...',
          no_matches: 'No matches',
          one_match: 'match',
          multiple_matches: 'matches',
          # -----
          group: 'Teaching group',
          last_name: 'Last name',
          first_names: 'First names',
          username: 'Username',
          actions: 'Actions',
          # -----
          change_password: 'Change password',
          password_tooltip: 'Change this user\'s password',
          # -----
          footer: 'Page created',
        }

      when 'finnish'
        return {
          html_lang: 'fi',
          page_title: 'Koulun oppilaslista',
          # -----
          users: 'käyttäjää',
          ungrouped: 'Opetusryhmättömät',
          # -----
          search_placeholder: 'Etsi nimellä...',
          no_matches: 'Ei osumia',
          one_match: 'osuma',
          multiple_matches: 'osumaa',
          # -----
          group: 'Opetusryhmä',
          last_name: 'Sukunimi',
          first_names: 'Etunimet',
          username: 'Käyttäjätunnus',
          actions: 'Toiminnot',
          # -----
          change_password: 'Vaihda salasana',
          password_tooltip: 'Vaihda tämän käyttäjän salasana',
          # -----
          footer: 'Sivu luotu',
        }

      when 'german'
        return {
          html_lang: 'de',
          page_title: "Liste von Schüler und Schülerinnen",
          # -----
          users: 'Benutzer',
          ungrouped: 'Schüler und Schülerinnen, die zu keiner Unterrichtsgruppe gehören',
          # -----
          search_placeholder: 'nach Namen suchen...',
          no_matches: 'keine Ergebnisse',
          one_match: 'ein Ergebnis',
          multiple_matches: 'Ergebnisse',
          # -----
          group: 'Unterrichtsgruppe',
          last_name: 'Nachname',
          first_names: 'Vornamen',
          username: 'Benutzername',
          actions: 'Aktionen',
          # -----
          change_password: 'Passwort ändern',
          password_tooltip: 'Passwort von diesem Benutzer ändern',
          # -----
          footer: 'Erstellt am',
        }
    end
  end

end   # class MySchoolUsers

end   # module PuavoRest
