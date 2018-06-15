require 'sinatra/r18n'

module PuavoRest

class MySchoolUsers < PuavoSinatra
  get '/v3/my_school_users' do
    auth :basic_auth, :kerberos

    user = User.current

    # only let teachers, admins and staff members view this page
    unless (Array(user.user_type) & ['teacher', 'staff', 'admin']).any?
      halt 401, 'Unauthorized'
    end

    school = user.school

    begin
      s_groups = Group.by_attr(:school_dn, school.dn, :multiple => true)
    rescue
      halt 400, "Cannot retrieve groups for school #{s.dn}"
    end

    groups_by_id = {}   # IDs are group abbreviations
    ungrouped = []      # students who are not in any group
    group_num = 0

    # split users into groups
    school.member_dns&.each do |m|
      begin
        u = User.by_dn!(m)
      rescue
        next
      end

      # list only students
      next unless (u.user_type || '').include?('student')

      u_data = {
        first: u.first_name,
        last: u.last_name,
        username: u.username,
      }

      # find this user's group, if any
      u_group = nil

      s_groups.each do |g|
        if g.member_dns.include?(m)
          u_group = g
          break
        end
      end

      if u_group
        id = u_group.abbreviation

        unless groups_by_id.include?(id)
          groups_by_id[id] = {
            name: u_group.name,
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
    @data[:changing] = user.username

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
          page_title: "School User List",
          users: 'users',
          ungrouped: 'Ungrouped',
          last_name: 'Last name',
          first_names: 'First names',
          username: 'Username',
          actions: 'Actions',
          change_password: 'Change password',
          password_tooltip: 'Change this user\'s password',
          footer: 'Page created:'
        }

      when 'finnish'
        return {
          html_lang: 'fi',
          page_title: 'Koulun käyttäjälista',
          users: 'käyttäjää',
          ungrouped: 'Ryhmittelemättömät',
          last_name: 'Sukunimi',
          first_names: 'Etunimet',
          username: 'Käyttäjätunnus',
          actions: 'Toiminnot',
          change_password: 'Vaihda salasana',
          password_tooltip: 'Vaihda tämän käyttäjän salasana',
          footer: 'Sivu luotu'
        }

      when 'german'
        return {
          html_lang: 'de',
          page_title: "Schulbenutzerliste",
          users: 'Benutzer',
          ungrouped: 'Nicht gruppiert',
          last_name: 'Nachname',
          first_names: 'Vornamen',
          username: 'Nutzername',
          actions: 'Aktionen',
          change_password: 'Passwort ändern',
          password_tooltip: 'Ändern Sie das Passwort dieses Benutzers',
          footer: 'Erstellt:'
        }

    end
  end

end   # class MySchoolUsers

end   # module PuavoRest
