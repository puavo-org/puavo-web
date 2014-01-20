class UsersPdf

  # @param [LdapOrganisation] organisation
  # @param [School] school
  # @param [String] create_timestamp Timestamp used to create users.
  # (User#puavoTimestamp)
  def initialize(organisation, school, create_timestamp)
    @create_timestamp = create_timestamp
    @organisation = organisation
    @school = school
    @pdf = Prawn::Document.new(
      :skip_page_creation => true,
      :page_size => 'A4'
    )
  end

  def existing?(user)
    user.puavoTimestamp != @create_timestamp
  end

  def add_users(users)
    User.list_by_role(users).each do |users|
      @pdf.start_new_page
      @pdf.font "Times-Roman"
      @pdf.font_size = 12
      start_page_number = @pdf.page_number

      # Sort users by sn + givenName
      users = users.sort{|a,b| a.sn + a.givenName <=> b.sn + a.givenName }

      @pdf.text "\n"

      users_of_page_count = 0
      users.each do |user|
        @pdf.indent(300) do
          @pdf.text "#{t('activeldap.attributes.user.displayName')}: #{user.displayName}"
          @pdf.text "#{t('activeldap.attributes.user.uid')}: #{user.uid}"
          if existing?(user)
            @pdf.text t('controllers.import.school_has_changed') + "\n\n\n"
          else
            @pdf.text "#{t('activeldap.attributes.user.password')}: #{user.new_password}\n\n\n"
          end
          users_of_page_count += 1
          if users_of_page_count > 10 && user != users.last
            users_of_page_count = 0
            @pdf.start_new_page
          end
        end
        @pdf.repeat start_page_number..@pdf.page_number do
          @pdf.draw_text(
            "#{@organisation.o}, #{@school.displayName}, #{users.first.roles.first.displayName}",
            :at => @pdf.bounds.top_left
          )
        end
      end

    end
  end

  def render
    @pdf.render
  end

  def t(*args)
    I18n.translate(*args)
  end

end

class ImportWorker
  @queue = "import:#{ Socket.gethostname }"

  def self.perform(job_id, organisation_key, user_dn, params)
    started = Time.now

    db = Redis::Namespace.new("puavo:import:#{ job_id }", REDIS_CONNECTION)

    flog = FLOG.merge(
      :organisation_key => organisation_key,
      :user_dn => user_dn
    )

    timestamp = Time.now.getutc.strftime("%Y%m%d%H%M%SZ")
    create_timestamp = "create:#{user_dn}:" + timestamp
    change_school_timestamp = "change_school:#{user_dn}:" + timestamp

    encrypted_password = db.get("pw")
    if encrypted_password.nil?
      db.set("status", "error: password missing")
      return
    end

    db.del("pw")
    db.set("status", "started")

    password = Puavo::RESQUE_WORKER_PRIVATE_KEY.private_decrypt(
      Base64.decode64(encrypted_password)
    )

    authentication = Puavo::Authentication.new
    authentication.configure_ldap_connection({
      :dn => user_dn,
      :password => password,
      :organisation_key => organisation_key
      })

    authentication.authenticate


    school = School.find(params["school_id"])
    organisation = LdapOrganisation.current

    users = User.hash_array_data_to_user(
      params["users"],
      params["columns"],
      school
    )

    failed_users = []
    ok_users = []

    puavo_ids = IdPool.next_puavo_id_range(users.select{ |u| u.puavoId.nil? }.count)
    id_index = 0

    # Generate password if import data does not contain one
    generate_password = !params["columns"].include?("new_password")

    User.reserved_uids = []

    users.each do |user, i|
      if user.puavoId.nil?
        user.puavoId = puavo_ids[id_index]
        id_index += 1
      end
      db.set("status", "working #{ i }/#{ users.size }")

      # If user existed already just copy the attributes from the new unsaved
      # user object to the existing one
      if user.earlier_user
        user.earlier_user.change_school(user.puavoSchool.to_s)
        user.earlier_user.role_name = user.role_name
        user.earlier_user.puavoTimestamp = Array(user.earlier_user.puavoTimestamp).push change_school_timestamp
        user.earlier_user.new_password = user.new_password

        # and continue importing with the old one
        user = user.earlier_user
      else
        user.set_generated_password if generate_password
        user.puavoTimestamp = create_timestamp
      end

      begin
        user.save!
        ok_users.push(user)
      rescue Exception => e
        puts "Failed user: " + user.inspect
        failed_users.push({
          "user" => user.inspect,
          "error" => e.message
        })
      end

    end
    db.set("status", "rendering pdf")

    users.each{ |u| u.roles.reload }

    log_msg = { :user_count => users.size }

    users_pdf = UsersPdf.new(organisation, school, create_timestamp)
    users_pdf.add_users(ok_users)

    if not failed_users.empty?
      db.set("failed_users", failed_users.to_json)
      log_msg[:failed_users] = failed_users
    end

    db.set("pdf", users_pdf.render())
    db.set("status", "finished")


    flog.info "import finished", log_msg.merge(
      :duration => (Time.now - started).to_f.round(3)
    )

  end

end
