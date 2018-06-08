require 'sinatra/r18n'

module PuavoRest

class MySchoolUsers < PuavoSinatra
  get '/v3/my_school_users' do
    auth :basic_auth, :kerberos

    u = User.current

    # only let teachers and admins view this page
    unless (Array(u.user_type) & ['teacher', 'admin']).any?
      halt 401, 'Unauthorized'
    end

    school = u.school

    begin
      s_groups = Group.by_attr(:school_dn, school.dn, :multiple => true)
    rescue
      halt 400, "Cannot retrieve groups for school #{s.dn}"
    end

    groups = {}

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

      u_group = :ungrouped
      id = 'ungrouped'

      s_groups.each do |g|
        if g.member_dns.include?(m)
          u_group = g.name
          id = u_group.gsub(/[^0-9a-z]/i, '_')    # ID for HTML tables and toggles
          break
        end
      end

      unless groups.include?(u_group)
        groups[u_group] = [id, []]
      end

      groups[u_group][1] << u_data
    end

    @data = {}
    @data['school'] = school.name
    @data['groups'] = groups
    @data['domain'] = 'http://10.246.133.89:8081'
    #@data['domain'] = 'http://' + request.host

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

    @data['language'] = lang || setup_language('english')

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
          password_tooltip: 'Change this user\'s pasword',
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
