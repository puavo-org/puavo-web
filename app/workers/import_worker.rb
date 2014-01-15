class ImportWorker
  @queue = :import

  def self.t(*args)
    I18n.translate(*args)
  end

  def self.perform(job_id, organisation_key, user_dn, params)
    db = Redis::Namespace.new("puavo:import:#{ job_id }", REDIS_CONNECTION)

    timestamp = Time.now.getutc.strftime("%Y%m%d%H%M%SZ")
    create_timestamp = "create:#{user_dn}:" + timestamp
    change_school_timestamp = "change_school:#{user_dn}:" + timestamp

    encrypted_password = db.get("pw")
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

    users = User.hash_array_data_to_user( params["users"],
                                          params["columns"],
                                          school )

    users_of_roles = Hash.new


    puavo_ids = IdPool.next_puavo_id_range(users.select{ |u| u.puavoId.nil? }.count)
    id_index = 0

    User.reserved_uids = []

    users.each do |user, i|
      begin
        if user.puavoId.nil?
          user.puavoId = puavo_ids[id_index]
          id_index += 1
        end
        if user.earlier_user
          user.earlier_user.change_school(user.puavoSchool.to_s)
          user.earlier_user.role_name = user.role_name
          user.earlier_user.puavoTimestamp = Array(user.earlier_user.puavoTimestamp).push change_school_timestamp
          user.earlier_user.new_password = user.new_password
          user.earlier_user.save!
        else
          user.puavoTimestamp = create_timestamp
          user.save!
        end
      rescue Exception => e
        puts "Failed user: " + user.inspect
      end

    end

    # If data of the users include new password then do not generate new password when creating pdf-file.
    reset_password = params["columns"].include?("new_password") ? false : true
    password_timestamp = "password:#{user_dn}:#{ Time.now.getutc.strftime("%Y%m%d%H%M%SZ") }"

    users.each do |user|
      user.set_generated_password if params[:reset_password] == "true"
      # Update puavoTimestamp
      user.puavoTimestamp = Array(user.puavoTimestamp).push password_timestamp
      user.save!
    end

    if params[:change_school_timestamp]
      User.find( :all,
                 :attribute => "puavoTimestamp",
                 :value => params[:change_school_timestamp] ).each do |user|
        user.earlier_user = true
        users.push user
      end
    end

    # Reload roles association
    users.each do |u| u.roles.reload end

    filename = organisation_key + "_" +
      # XXX
      # @school.cn + "_" + Time.now.strftime("%Y%m%d") + ".pdf"
      "TODOschoolCN" + "_" + Time.now.strftime("%Y%m%d") + ".pdf"


    db.set("pdf", create_pdf(users))
    db.set("status", "finished")
  end

  def self.create_pdf(users)
    role_name = String.new
    pdf = Prawn::Document.new( :skip_page_creation => true, :page_size => 'A4')

    users_by_role = User.list_by_role(users)
    users_by_role.each do |users|
      role_to_pdf(users, pdf)
    end
    pdf.render
  end

  def self.role_to_pdf(users, pdf)
    pdf.start_new_page
    pdf.font "Times-Roman"
    pdf.font_size = 12
    start_page_number = pdf.page_number

    # Sort users by sn + givenName
    users = users.sort{|a,b| a.sn + a.givenName <=> b.sn + a.givenName }

    pdf.text "\n"

    users_of_page_count = 0
    users.each do |user|
      pdf.indent(300) do
        pdf.text "#{t('activeldap.attributes.user.displayName')}: #{user.displayName}"
        pdf.text "#{t('activeldap.attributes.user.uid')}: #{user.uid}"
        if user.earlier_user
          pdf.text t('controllers.import.school_has_changed') + "\n\n\n"
        else
          pdf.text "#{t('activeldap.attributes.user.password')}: #{user.new_password}\n\n\n"
        end
        users_of_page_count += 1
        if users_of_page_count > 10 && user != users.last
          users_of_page_count = 0
          pdf.start_new_page
        end
      end
      pdf.repeat start_page_number..pdf.page_number do
        # XXX
        # pdf.draw_text "#{current_organisation.name}, #{@school.displayName}, #{users.first.roles.first.displayName}", :at => pdf.bounds.top_left
        pdf.draw_text "TODO org name here, TODO school name, #{users.first.roles.first.displayName}", :at => pdf.bounds.top_left
      end
    end
  end

end
