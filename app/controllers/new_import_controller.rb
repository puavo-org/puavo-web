# New Mass Users Import/Update

class NewImportController < ApplicationController
  # Attributes whose values must be unique and must therefore be processed separately, so
  # that if their values cause problems, other values can be still saved
  UNIQUE_ATTRS = ['eid', 'phone', 'email'].freeze

  def index
    return if redirected_nonowner_user?

    @automatic_email_addresses, _ = get_automatic_email_addresses
    @initial_groups = get_school_groups(School.find(@school.id).dn.to_s)

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
    users = User.search_as_utf8(
      filter: '(objectClass=puavoEduPerson)',
      attributes: ['puavoId', 'uid']
    ).collect do |dn, u|
      {
        id: u['puavoId'][0].to_i,
        uid: u['uid'][0],
      }
    end

    render json: users
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

    #puts response.inspect

    render json: response
  end

  def generate_password_pdf
    begin
      uids_with_passwords = JSON.parse(request.body.read.to_s)

      # Get the user's full names from the database
      users = []

      uids_with_passwords.each do |uid, _|
        u = User.search_as_utf8(
          filter: "(uid=#{Net::LDAP::Filter.escape(uid)})",
          attributes: ['uid', 'givenName', 'sn']
        )

        users << {
          dn: u[0][0],
          uid: uid,
          first: u[0][1]['givenName'][0],
          last: u[0][1]['sn'][0],
          group: '',    # filled in later
          password: uids_with_passwords[uid],
        }
      end

      # Make a list of schools, so we can format group names properly
      school_names = School.search_as_utf8(attributes: ['displayName']).collect do |dn, s|
        [dn, s['displayName'][0]]
      end.to_h

      # Fill in the groups. Try teaching groups first, but if the user does not have
      # a teaching group, use archiving group next.
      # TODO: Try *all* the group types, in some predefined priority order.
      archived_groups = []
      teaching_groups = []

      Group.search_as_utf8(
        filter: '(&(objectClass=puavoEduGroup)(|(puavoEduGroupType=teaching group)(puavoEduGroupType=archive users)))',
        attributes: ['cn', 'displayName', 'puavoEduGroupType', 'member', 'puavoSchool']
      ).each do |dn, group|
        type = group.fetch('puavoEduGroupType', [nil])[0]
        next unless type

        school_name = school_names.fetch(group['puavoSchool'][0], '?')

        g = {
          name: "#{school_name}, #{group['displayName'][0]}",
          members: Array(group['member'] || []).to_set.freeze,
        }

        if type == 'teaching group'
          teaching_groups << g
        elsif type == 'archive users'
          archived_groups << g
        end
      end

      users.each do |user|
        teaching_groups.each do |group|
          if group[:members].include?(user[:dn])
            user[:group] = group[:name]
            break
          end
        end

        if user[:group] == ''
          # This user has no teaching group. See if they're in an archived users group.
          archived_groups.each do |group|
            if group[:members].include?(user[:dn])
              user[:group] = group[:name]
              break
            end
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
            pdf.draw_text(headertext, :at => [0, (pdf.bounds.top - 15)] )

            pdf.font('unicodefont')
            pdf.font_size(12)
            pdf.draw_text("(#{t('new_import.pdf.page')} #{current_page + 1}/#{num_pages}, #{header_timestamp})",
                :at => [(pdf.bounds.right - 160), 0] )
            pdf.text("\n\n\n")

            current_page += 1

            block.each do |u|
              pdf.font('unicodefont')
              pdf.font_size(12)

              title = "#{u[:last]}, #{u[:first]} (#{u[:uid]})"

              pdf.text(title)

              pdf.font('Courier')
              pdf.text(u[:password])
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
