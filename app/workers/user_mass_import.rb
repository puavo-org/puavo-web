class UserMassImport
  @queue = :user_mass_import

  def self.perform(organisation, user_dn, encrypt_password, params)
    # Decrypt user password by private key
    password = Puavo::RESQUE_WORKER_PRIVATE_KEY.private_decrypt Base64.decode64(encrypt_password)

    # Create LDAP-connection
    authentication = Puavo::Authentication.new
    authentication.configure_ldap_connection({
                                               :dn => user_dn,
                                               :password => password,
                                               :organisation_key => organisation
                                             })
    authentication.authenticate

    puts "params: " + params.inspect

    school = School.find(params["school_id"])

    users = User.hash_array_data_to_user( params["users"],
                                          params["columns"],
                                          school )

    users_of_roles = Hash.new

    timestamp = Time.now.getutc.strftime("%Y%m%d%H%M%SZ")
    create_timestamp = "create:#{user_dn}:" + timestamp
    change_school_timestamp = "change_school:#{user_dn}:" + timestamp

    puavo_ids = IdPool.next_puavo_id_range(users.select{ |u| u.puavoId.nil? }.count)
    id_index = 0

    User.reserved_uids = []

    users.each do |user|
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

    # If data of users inlucde new password then not generate new password when create pdf-file.
    reset_password = params["columns"].include?("new_password") ? false : true

  end

end
