# New Mass Users Import/Update

class NewImportController < ApplicationController
  # Attributes whose values must be unique and must therefore be processed separately, so
  # that if their values cause problems, other values can be still saved
  UNIQUE_ATTRS = ['eid', 'phone', 'email'].freeze

  def index
    if !is_owner? && !current_user.has_admin_permission(:import_users) then
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to users_path
      return
    end

    @automatic_email_addresses, _ = get_automatic_email_addresses
    @initial_groups = get_school_groups(School.find(@school.id).dn.to_s)

    @lists = List
      .all
      .reject { |l| l.downloaded }
      .select { |l| l.school_id == @school.id.to_i }
      .sort { |a, b| a.created_at <=> b.created_at }
      .reverse

    @can_create_users = true

    unless is_owner?
      @can_create_users = can_schooladmin_do_this?(current_user.uid, :create_users)
    end

    respond_to do |format|
      format.html
    end
  end

  # Retrieve an updated list of groups in the current school
  def reload_groups
    render json: get_school_groups(School.find(params['school_id'].to_i).dn.to_s)
  end

  # Get the IDs and usernames of all users in this organisation
  def get_current_users
    response = {
      status: 'ok',
      error: nil,
      usernames: [],
    }

    begin
      rest = get_superuser_proxy

      users = JSON.parse(request.body.read)

      # Find the puavoID for every user on the list
      users.each do |user|
        raw_user = JSON.parse(rest.get("/v4/users?no_eltern&fields=id&filter[]=username|is|#{user[0]}").body)

        if raw_user['status'] != 'ok'
          # Abort the operation here
          response[:status] = 'rest_status_fail'
          response[:error] = user[0]
          return render json: response
        end

        raw_user = raw_user['data']

        if raw_user.empty?
          # This user does not exist, use -1 for puavoID
          user[1] = -1
        else
          user[1] = raw_user[0]['id']
        end
      end

      # Send the updated data back
      response[:usernames] = users
    rescue PuavoRestProxy::BadStatus => e
      response[:status] = 'puavo_rest_call_failed'
      response[:error] = e.to_s
    rescue StandardError => e
      response[:status] = 'failed'
      response[:error] = e.to_s
    end

    render json: response
  end

  # Extended version of get_current_users(), used in duplicate username detection.
  # Returns user information, but also includes schools.
  def duplicate_detection
    response = {
      status: 'ok',
      error: nil,
      users: [],
      schools: {},
    }

    begin
      rest = get_superuser_proxy

      users = JSON.parse(rest.get(
        '/v4/users?no_eltern&fields=id,username,primary_school_id,school_ids,external_id,email,phone').body)
      raise if users['status'] != 'ok'
      response[:users] = users['data']

      schools = JSON.parse(rest.get('/v4/schools?fields=id,name').body)
      raise if schools['status'] != 'ok'

      schools['data'].each do |s|
        response[:schools][s['id']] = s['name']
      end
    rescue PuavoRestProxy::BadStatus => e
      response[:status] = 'puavo_rest_call_failed'
      response[:error] = e.to_s
    rescue StandardError => e
      puts e.backtrace.join("\n")
      response[:status] = 'failed'
      response[:error] = e.to_s
    end

    render json: response
  end

  # Given a list of usernames, returns informatin about which schools they already exist in
  def find_existing_users
    response = {
      status: 'ok',
      error: nil,
      states: []
    }

    begin
      rest = get_superuser_proxy

      # Make a list of schools so we can tell which school the user is in
      schools = {}
      raw_schools = JSON.parse(rest.get('/v4/schools?fields=id,name').body)
      raise if raw_schools['status'] != 'ok'

      raw_schools['data'].each do |s|
        schools[s['id']] = s['name']
      end

      # Look up each user on the list and fill in the return state
      data = JSON.parse(request.body.read)
      this_school = data['school_id']

      data['usernames'].each do |name|
        raw_user = JSON.parse(rest.get(
          "/v4/users?no_eltern&fields=primary_school_id,school_ids&filter[]=username|is|#{name}").body)

        if raw_user['status'] != 'ok'
          response[:states] << [-1, nil]
          next
        end

        user = raw_user['data']

        if user.empty?
          # This user does not exist on the server
          response[:states] << [0, nil]
        elsif user[0]['primary_school_id'] == this_school
          # This user exists in this school
          response[:states] << [1, nil]
        else
          # The user exists in some other school(s), list their names
          msg = []

          user[0]['school_ids'].each do |sid|
            msg << schools.fetch(sid, '???')
          end

          response[:states] << [2, msg]
        end
      end
    rescue PuavoRestProxy::BadStatus => e
      response[:status] = 'puavo_rest_call_failed'
      response[:error] = e.to_s
    rescue StandardError => e
      response[:status] = 'failed'
      response[:error] = e.to_s
    end

    render json: response
  end

  def make_username_list
    response = {
      status: 'ok',
      error: nil,
    }

    begin
      data = JSON.parse(request.body.read)

      missing = []
      valid = []

      # Convert usernames into puavoIds. We could extract them from the DNs (that all
      # raw searches always return), but it seems that we have to give some attributes
      # to search for.
      data['usernames'].each do |uid|
        user = User.search_as_utf8(
          filter: "(&(objectClass=puavoEduPerson)(uid=#{Net::LDAP::Filter.escape(uid)}))",
          attributes: ['puavoId']
        )

        if user.nil? || user.empty?
          missing << uid
        else
          valid << user[0][1]['puavoId'][0].to_i
        end
      end

      unless missing.empty?
        response[:status] = 'missing_users'
        response[:error] = missing
      else
        ll = List.new(valid)
        ll.creator = data['creator']
        ll.school_id = data['school']
        ll.description = data['description']
        ll.save
      end
    rescue StandardError => e
      response[:status] = 'failed'
      response[:error] = e.to_s
    end

    render json: response
  end

  def load_username_list
    response = {
      status: 'ok',
      error: nil,
      usernames: [],
    }

    begin
      ll = List.by_id(params['uuid'])
      raise 'already downloaded' if ll.downloaded
    rescue StandardError => e
      response[:status] = 'list_not_found'
      response[:error] = e.to_s
      return render json: response
    end

    begin
      # Convert puavoIds back into usernames
      missing = []
      valid = []

      ll.users.each do |id|
        user = User.search_as_utf8(
          filter: "(&(objectClass=puavoEduPerson)(puavoId=#{Net::LDAP::Filter.escape(id.to_s)}))",
          attributes: ['uid']
        )

        if user.nil? || user.empty?
          missing << id.to_i
        else
          valid << user[0][1]['uid'][0]
        end
      end

      unless missing.empty?
        response[:status] = 'missing_users'
        response[:error] = missing
      end

      response[:usernames] = valid
    rescue StandardError => e
      response[:status] = 'failed'
      response[:error] = e.to_s
    end

    render json: response
  end

  # Import or update one or more users
  def import
    response = {
      # Top-level status/fail indicator. If this is not true, the import worker will retry
      # this chunk a few times before giving up. Of course, if the client sends invalid JSON
      # then retrying it won't help. But it will help with intermittent network errors,
      # for example.
      ok: true,

      # Top-level error message. Logged somewhere in the UI.
      error: nil,

      # Status data for individual rows in this batch (unused if "ok" is not true)
      rows: []
    }

    begin
      data = JSON.parse(request.body.read.to_s)
    rescue => e
      puts e

      response[:ok] = false
      response[:error] = e.to_s

      return render json: response
    end

    column_to_index = {}

    data['columns'].each_with_index do |col, index|
      column_to_index[col] = index
    end

    can_create_users = true

    unless is_owner?
      can_create_users = can_schooladmin_do_this?(current_user.uid, :create_users)
    end

    data['rows'].each do |row|
      row_num = row[0]    # the original table row number
      puavo_id = row[1]

      # The column names are not duplicated on every row to save space. "Unpack" them
      # into a clean hash.
      attributes = {}

      data['columns'].each_with_index do |col, index|
        next if col.empty?        # skipped column

        value = row[index + 2]
        value = nil if value.nil? || value.strip.empty?
        attributes[col] = value
      end

      if puavo_id == -1
        # Create a new user
        unless can_create_users
          # TODO: This probably needs a better message. But getting this far in limited-user
          # mode requires using the browser's developer tools to override the limitation.
          # At that point, the user is intentionally breaking the thing.
          response[:rows] << {
            row: row_num,
            state: 'failed',
            error: 'Haha. No.',
            failed: [],
          }

          next
        end

        state, error, failed = create_new_user(attributes, response, column_to_index)

        response[:rows] << {
          row: row_num,
          state: state.to_s,
          error: error,
          failed: failed,
        }
      else
        # Update an existing user
        state, error, failed = update_existing_user(puavo_id, attributes, response, column_to_index)

        response[:rows] << {
          row: row_num,
          state: state.to_s,
          error: error,
          failed: failed,
        }
      end
    end

    render json: response
  end

  def generate_pdf
    begin
      raw_users = JSON.parse(request.body.read.to_s)

      # Get the user's full names from the database
      users = []

      raw_users.each do |uid, _|
        u = User.search_as_utf8(
          filter: "(uid=#{Net::LDAP::Filter.escape(uid)})",
          attributes: ['uid', 'givenName', 'sn']
        )

        # the report can theoretically contain users who don't exist yet
        next if u.nil? || u.empty?

        users << {
          dn: u[0][0],
          uid: uid,
          first: u[0][1]['givenName'][0],
          last: u[0][1]['sn'][0],
          group: '',    # filled in later
          password: raw_users.fetch(uid, nil),
        }
      end

      # Make a list of schools, so we can format group names properly
      school_names = School.search_as_utf8(attributes: ['displayName']).collect do |dn, s|
        [dn, s['displayName'][0]]
      end.to_h

      # Make a list of groups, their types, and members
      groups = []

      Group.search_as_utf8(
        filter: '(objectClass=puavoEduGroup)',
        attributes: ['cn', 'displayName', 'puavoEduGroupType', 'member', 'puavoSchool']
      ).each do |dn, group|
        type = group.fetch('puavoEduGroupType', [nil])[0]

        school_name = school_names.fetch(group['puavoSchool'][0], '?')

        g = {
          name: "#{school_name}, #{group['displayName'][0]}",
          type: type,
          members: Array(group['member'] || []).to_set.freeze,
        }

        groups << g
      end

      # Find a suitable group for each user. Since a user can belong to many groups,
      # prioritize the groups and try to find the "best" match.
      group_priority = {
        'teaching group' => 5,
        'year class' => 4,
        'course group' => 3,
        'administrative group' => 2,
        'archive users' => 1,
        'other groups' => 0,
        nil => -1,
      }.freeze

      users.each do |user|
        best = nil

        groups.each do |this|
          next unless this[:members].include?(user[:dn])

          if best.nil? || group_priority[this[:type]] > group_priority[best[:type]]
            # This group type has a higher priority than the existing group
            best = this
          end
        end

        if best
          if best[:type]
            user[:group] = "#{best[:name]} (#{t('group_type.' + best[:type])})"
          else
            user[:group] = "#{best[:name]}"
          end
        end
      end

      # Sort the users by their username. Assume it's even somewhat related to their real name.
      users.sort! do |a, b|
        [a[:group], a[:last], a[:first], a[:uid]] <=> [b[:group], b[:last], b[:first], b[:uid]]
      end

      # Figure out the total page count. Each teaching group gets its own page (or pages).
      # I determined empirically that 18 users per page is more or less the maximum.
      # If you put more, the final user can get split across two pages.
      users_per_page = 18
      num_pages = 0
      current_page = 0

      grouped_users = users.chunk { |u| u[:group] }

      grouped_users.each do |group_name, group_users|
        num_pages += group_users.each_slice(users_per_page).count
      end

      now = Time.now
      header_timestamp = now.strftime('%Y-%m-%d %H:%M:%S')
      filename_timestamp = now.strftime('%Y%m%d_%H%M%S')

      pdf = Prawn::Document.new(skip_page_creation: true, page_size: 'A4')
      Prawn::Fonts::AFM.hide_m17n_warning = true

      # Use a proper Unicode font
      pdf.font_families['unicodefont'] = {
        normal: {
          font: 'Regular',
          file: Pathname.new(Rails.root.join('app', 'assets', 'stylesheets', 'font', 'FreeSerif.ttf')),
        }
      }

      if users.count == 0
        pdf.start_new_page()
        pdf.font('unicodefont')
        pdf.font_size(12)
        pdf.draw_text("(No users)",
                      at: pdf.bounds.top_left)
      else
        grouped_users.each do |group_name, group_users|
          group_users.each_slice(users_per_page).each_with_index do |block, _|
            pdf.start_new_page()

            pdf.font('unicodefont')
            pdf.font_size(18)
            headertext = "#{current_organisation.name}"
            headertext += ", #{group_name}" if group_name && group_name.length > 0
            pdf.text(headertext)

            pdf.font('unicodefont')
            pdf.font_size(12)
            pdf.draw_text("(#{t('new_import.pdf.page')} #{current_page + 1}/#{num_pages}, #{header_timestamp})",
                          at: [(pdf.bounds.right - 160), 0])
            pdf.text("\n")

            current_page += 1

            block.each do |u|
              pdf.font('unicodefont')
              pdf.font_size(12)

              pdf.text("#{u[:last]}, #{u[:first]} (#{u[:uid]})")

              if u[:password]
                pdf.font('Courier')
                pdf.text(u[:password])
              end

              pdf.text("\n")
            end
          end
        end
      end

      filename = "#{current_organisation.organisation_key}_#{@school.cn}_#{filename_timestamp}.pdf"

      send_data(pdf.render,
                filename: filename,
                type: 'application/pdf',
                disposition: 'attachment')
    rescue => e
      puts e
      puts e.backtrace.join("\n")

      # Send back an error message
      response = {
        'success' => false,
        'message' => e
      }

      send_data(response.to_json.to_s,
                type: 'application/json',
                disposition: 'attachment')
    end
  end

  private

  # Returns a puavo-rest proxy that is authenticated using some super-user account. In order for
  # non-owner users to be able to access the import tool, we need something that can access ALL
  # users in the organisation, for duplicate checks, etc. and normal admin users cannot do that.
  def get_superuser_proxy
    # The default password will work fine for development puavo-standalone, but in production,
    # you need something else. Put something like this in /etc/puavo-web/puavo_web.yml:
    # import_tool:
    #   superuser_name: "uid=admin,o=puavo"
    #   superuser_password: "the real password here"
    credentials = Puavo::CONFIG.fetch('import_tool', {})

    rest_proxy(credentials.fetch('superuser_name', 'uid=admin,o=puavo'),
               credentials.fetch('superuser_password', 'password'))
  end

  def get_school_groups(school_dn)
    Group.search_as_utf8(
      filter: "(&(objectClass=puavoEduGroup)(puavoSchool=#{school_dn}))",
      attributes: ['puavoId', 'cn', 'displayName', 'puavoEduGroupType', 'puavoSchool']
    ).collect do |dn, g|
      {
        id: g['puavoId'][0].to_i,
        abbr: g['cn'][0],
        name: g['displayName'][0],
        type: g.fetch('puavoEduGroupType', [nil])[0],
      }
    end
  end

  def create_new_user(attributes, response, column_to_index)
    begin
      user = User.new

      # These attributes always exist, since the tool won't let you submit entries that
      # don't have them
      user.givenName = attributes['first']
      user.sn = attributes['last']
      user.uid = attributes['uid']
      user.puavoEduPersonAffiliation = attributes['role']

      # The school is currently hardcoded for new users
      user.puavoSchool = @school.dn
      user.puavoEduPersonPrimarySchool = @school.dn

      # Optional attributes that don't have to be unique
      if attributes.include?('pnumber')
        user.puavoEduPersonPersonnelNumber = attributes['pnumber']
      end

      if attributes.include?('password')
        user.new_password = attributes['password']
      end

      # FIXME: WHY. THIS. IS. NOT. IN. THE. MODEL?!
      automatic_email_addresses, domain = get_automatic_email_addresses

      if automatic_email_addresses
        # WHY?
        user.mail = "#{attributes['uid']}@#{domain}"
      end

      user.save!
    rescue => e
      puts "-"*50
      puts e
      puts "-"*50
      return [:failed, e.to_s, []]
    end

    # Now set the optional attributes that have to be unique. This loop is slow; it was
    # designed to be robust, not fast. It sets every attribute separately and if it fails,
    # it just moves on to the next. This ensures that one invalid/duplicate values does
    # not prevent other values, possibly valid, from being set. I believe that most people
    # who use the mass import tool care about getting most of their work done for them, not
    # how long it takes.
    failed = []

    UNIQUE_ATTRS.each do |attr|
      next unless attributes.include?(attr)
      next if attr == 'group'

      begin
        user = User.find(:first, attribute: 'uid', value: attributes['uid'])

        case attr
          when 'eid'
            user.puavoExternalId = attributes['eid']

          when 'phone'
            user.telephoneNumber = attributes['phone']

          when 'email'
            user.mail = attributes['email']
        end

        user.save!
      rescue => e
        puts "-"*50
        puts e
        puts "-"*50
        failed << [attr, column_to_index[attr], e.to_s]
      end
    end

    # Add to groups
    attributes.each do |key, value|
      next unless key == 'group'
      next if value.nil? || value.empty?

      begin
        group = Group.find(:first, attribute: 'cn', value: value)

        if group.nil?
          failed << [key, column_to_index[key], t('new_import.errors.unknown_group')]
          next
        end

        # This has its own internal error handling. If the user is already in the group,
        # nothing happens. We simply don't have to worry.
        group.add_user(user)
      rescue => e
        failed << [key, column_to_index[key], e.to_s]
        next
      end
    end

    if failed.empty?
      # No errors happened when the unique attributes were set, so everything is good
      # for this user
      return [:ok, nil, []]
    else
      # The user was created, but not all unique attributes could be set
      return [:partial_ok, nil, failed]
    end
  end

  def update_existing_user(puavo_id, attributes, response, column_to_index)
    # Fetch the user. If it fails, mark the entire user as "failed".
    begin
      user = User.find(puavo_id)
    rescue ActiveLdap::EntryNotFound => e
      puts "-"*50
      puts e
      puts "-"*50
      return [:failed, e.to_s, []]
    end

    something_changed = false
    have_unique = false
    have_groups = false

    # Again, why this isn't in the model?!?!?!?!?!
    automatic_email_addresses, domain = get_automatic_email_addresses

    if automatic_email_addresses
      attributes['email'] = "#{attributes['uid']}@#{domain}"
    end

    begin
      # Update the changed attributes
      attributes.each do |key, value|
        if UNIQUE_ATTRS.include?(key)
          have_unique = true
          next
        end

        if key == 'group'
          have_groups = true
          next
        end

        #puts "|#{key}| = |#{value.inspect}|"

        case key
          when 'first'
            if !value.nil? && user.givenName != value
              puts "  -> First name changed from |#{user.givenName}| to |#{value}|"
              user.givenName = value
              something_changed = true
            end

          when 'last'
            if !value.nil? && user.sn != value
              puts "  -> Last name changed from |#{user.sn}| to |#{value}|"
              user.sn = value
              something_changed = true
            end

          when 'password'
            if !value.nil?
              puts "  -> Setting new password"
              user.new_password = value
              something_changed = true
            end

          when 'pnumber'
            if !value.nil? && user.puavoEduPersonPersonnelNumber != value
              puts "  -> Personnel number changed from |#{user.puavoEduPersonPersonnelNumber}| to |#{value}|"
              user.puavoEduPersonPersonnelNumber = value
              something_changed = true
            end
        end
      end

      puts "something_changed: #{something_changed}  have_unique: #{have_unique}  have_groups: #{have_groups}"

      if !something_changed && !have_unique && !have_groups
        puts "  -> nothing to save or change, moving on"
        return [:ok, nil, []]
      end

      if something_changed
        puts "  -> simple attributes changed, saving"

        begin
          user.save!
        rescue => e
          puts "  -> simple save failed!"
          puts "-"*50
          puts e
          puts "-"*50
          return [:failed, e.to_s, []]
        end
      end

      unless have_unique || have_groups
        # Simple attributes OK, nothing else to do
        return [:ok, nil, []]
      end

      # Process the unique attributes one-by-one, while ignoring duplicates
      puts "  -> simple save done, processing unique values next"
      failed = []

      UNIQUE_ATTRS.each do |attr|
        next unless attributes.include?(attr)

        #puts "|#{attr}| = |#{attributes[attr].inspect}|"

        next if attributes[attr].nil?

        user = User.find(:first, attribute: 'uid', value: attributes['uid'])

        case attr
          when 'eid'
            user.puavoExternalId = attributes['eid']

          when 'phone'
            user.telephoneNumber = attributes['phone']

          when 'email'
            user.mail = attributes['email']
        end

        begin
          user.save!
        rescue => e
          puts "-"*50
          puts e
          puts "-"*50
          failed << [attr, column_to_index[attr], e.to_s]
        end
      end

      puts "  -> unique values done"

      if have_groups
        puts "  -> processing groups"

        attributes.each do |key, value|
          next unless key == 'group'
          next if value.nil? || value.empty?

          begin
            group = Group.find(:first, attribute: 'cn', value: value)

            if group.nil?
              failed << [key, column_to_index[key], t('new_import.errors.unknown_group')]
              next
            end

            # This has its own internal error handling. If the user is already in the group,
            # nothing happens. We simply don't have to worry.
            group.add_user(user)
          rescue => e
            failed << [key, column_to_index[key], e.to_s]
            next
          end
        end
      end

      if failed.empty?
        # All unique attributes really were unique
        puts "  -> all unique/group values were good"
        return [:ok, nil, []]
      else
        # Some of the new values were not unique
        puts "  -> some unique/group values failed"
        return [:partial_ok, nil, failed]
      end
    rescue => e   # main user update
      puts "-"*50
      puts e
      puts "-"*50
      return [:partial_ok, e, []]
    end
  end
end
