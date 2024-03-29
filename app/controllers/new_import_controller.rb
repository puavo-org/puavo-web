# New Mass Users Import/Update

class NewImportController < ApplicationController
  include PasswordsPdfHelper      # PDF generation

  # Attributes whose values must be unique and must therefore be processed separately, so
  # that if their values cause problems, other values can be still saved
  UNIQUE_ATTRS = ['eid', 'phone', 'email'].freeze

  def index
    unless is_owner? || current_user.has_admin_permission?(:import_users)
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

    @can_create_users = is_owner? || current_user.has_admin_permission?(:create_users)

    respond_to do |format|
      format.html
    end
  end

  # Retrieve an updated list of groups in the current school
  def reload_groups
    render json: get_school_groups(School.find(params['school_id'].to_i).dn.to_s)
  end

  # Compare the given usernames to all users in this organisation.
  def get_current_users
    response = {
      status:    'ok',
      error:     nil,
      usernames: [],
    }

    begin
      requested_users = JSON.parse(request.body.read)

      puavo_ids_by_username = Hash[
        User.search_as_utf8(
          filter: '(objectClass=puavoEduPerson)',
          attributes: %w(puavoId uid),
        ).collect do |_, u|
          [ u['uid'][0], u['puavoId'][0].to_i ]
        end
      ]

      response[:usernames] \
        = requested_users.map do |u|
            username, _, row_id = *u
            [ username, (puavo_ids_by_username[username] || -1), row_id ]
          end
    rescue StandardError => e
      response[:status] = 'failed'
      response[:error] = e.to_s
    end

    render json: response
  end

  # Extended version of get_current_users(), used in duplicate username detection.
  # Returns user information, but also includes schools
  def duplicate_detection
    response = {
      status:  'ok',
      error:   nil,
      users:   [],
      schools: {},
    }

    begin
      extract_dn = /puavoId=(\d+),ou=Groups/

      response[:users] = User.search_as_utf8(
        filter: '(objectClass=puavoEduPerson)',
        attributes: %w(puavoId uid puavoExternalId mail telephoneNumber),
      ).collect do |_, u|
        {
          username: u['uid'][0],
          external_id: u.fetch('puavoExternalId', [nil])[0],
          email: Array(u['mail'] || []),
          phone: Array(u['telephoneNumber'] || [])
        }
      end

      response[:schools] = Hash[
        School.search_as_utf8(attributes: %w(puavoId displayName)) \
              .collect { |dn, s| [ s['puavoId'][0].to_i, s['displayName'][0] ] }
      ]
    rescue StandardError => e
      response[:status] = 'failed'
      response[:error] = e.to_s
    end

    render json: response
  end

  # Given a list of usernames, returns information about which schools they
  # already exist in
  def find_existing_users
    extract_dn = /puavoId=(\d+),ou=Groups/

    response = {
      status: 'ok',
      error:  nil,
      states: [],
    }

    begin
      data = JSON.parse(request.body.read)
      school_id_to_lookup = data['school_id']
      usernames_to_lookup = data['usernames']

      schoolnames_by_id = Hash[
        School.search_as_utf8(attributes: ['puavoId', 'displayName']) \
              .collect { |dn, s| [ s['puavoId'][0].to_i, s['displayName'][0] ] }
      ]

      # Look up each user on the list and fill in the return state
      usernames_to_lookup.each do |uid|
        user_list = User.search_as_utf8(
          filter: "(&(objectClass=puavoEduPerson)(uid=#{Net::LDAP::Filter.escape(uid)}))",
          attributes: %w(puavoId puavoEduPersonPrimarySchool puavoSchool),
        ).collect do |_,u|
          {
            school: extract_dn.match(u['puavoEduPersonPrimarySchool'][0])[1].to_i,
            schools: u['puavoSchool'].collect { |dn| extract_dn.match(dn)[1].to_i },
          }
        end

        if user_list.nil? then
          response[:states] << [-1, nil]
          next
        end

        if user_list.empty? then
          # This user does not exist on the server
          response[:states] << [0, nil]
          next
        end

        user = user_list[0]

        if user[:school] == school_id_to_lookup then
          # This user exists in this school
          response[:states] << [1, nil]
          next
        end

        # The user exists in some other school(s), list their names
        warn ">>> user=#{ user.inspect }"
        ids = user[:schools].map { |sid| schoolnames_by_id.fetch(sid, '???') }
        response[:states] << [2, ids]
      end

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

    # Can the current user even do this?
    can_create_users = is_owner? || current_user.has_admin_permission?(:create_users)

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
      group_priority = PasswordsPdfHelper.get_group_priorities()

      users.each do |user|
        best = nil

        groups.each do |this|
          next unless this[:members].include?(user[:dn])

          if best.nil? || group_priority[this[:type]] > group_priority[best[:type]]
            best = this
          end
        end

        if best
          if best[:type]
            user[:group] = "#{best[:name]} (#{t('group_type.' + best[:type])})"
          else
            user[:group] = "#{best[:name]}"
          end
        else
          user[:group] = t('new_import.pdf.no_group')
        end
      end

      # Sort the users by their username. Assume it's even somewhat related to their real name.
      users.sort! do |a, b|
        [a[:group], a[:last], a[:first], a[:uid]] <=> [b[:group], b[:last], b[:first], b[:uid]]
      end

      # Generate the PDF
      filename_timestamp, pdf = PasswordsPdfHelper.generate_pdf(users, current_organisation.name)
      filename = "#{current_organisation.organisation_key}_#{@school.cn}_#{filename_timestamp}.pdf"

      send_data(pdf.render, filename: filename, type: 'application/pdf', disposition: 'attachment')
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

      if attributes.include?('licenses')
        user.puavoLicenses = attributes['licenses']
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

          when 'licenses'
            if !value.nil? && user.puavoLicenses != value
              puts "  -> User licenses changed from |#{user.puavoLicenses}| to |#{value}|"
              user.puavoLicenses = value
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
