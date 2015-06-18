
def define_basic(env)

  env.define :organisation do |config|
    config.dn = LdapOrganisation.first.dn
  end

  env.define :school, :role do |school_config, role_config|

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )
    school_config.dn = @school.dn

    # Role for students
    Role.create(
      :displayName => "Class 4",
      :puavoSchool => @school.dn
    )

    # Role for teachers and admins
    Role.create(
      :displayName => "Staff",
      :puavoSchool => @school.dn
    )

    # Unused role for testing
    role = Role.create(
      :displayName => "Class 5",
      :puavoSchool => @school.dn
    )
    role_config.dn = role.dn

  end

  env.define :group do |config|
    group = Group.create(
      :displayName => "Test Group",
      :cn          => "testgroup",
      :puavoSchool => env.school.dn
    )
    config.dn = group.dn
  end

  env.define :teacher do |config|
    teacher = User.create(
      :puavoSchool => env.school.dn,
      :givenName => "Severus",
      :sn => "Snape",
      :uid => "severus.snape",
      :role_name => "Staff",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "teacher"
    )
    config.dn = teacher.dn
  end

  env.define :admin do |config|
    admin = User.create(
      :puavoSchool => env.school.dn,
      :givenName => "Minerva",
      :sn => "McGonagall",
      :uid => "minerva.mcgonagall",
      :role_name => "Staff",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "admin",
      :school_admin => true
    )
    @school.add_admin(admin)
    config.dn = admin.dn
  end


  env.define :owner do |config|
    config.dn = User.find(:first, :attribute => "uid", :value => "cucumber").dn.to_s
    config.password = "cucumber"
  end

  env.define :puavo do |config|
    config.dn = "uid=puavo,o=puavo"
    config.password = "password"
  end

  env.define :ticket do |config|
    config.dn = "uid=puavo-ticket,o=puavo"
    config.password = "password"
  end

  env.define :pwmgmt do |config|
    config.dn = "uid=pw-mgmt,o=puavo"
    config.password = "password"
  end

  env.define :student do |config|
    test_image = Magick::Image.read("features/support/test.jpg").first.to_blob
    student = User.new(
      :puavoSchool => env.school.dn,
      :givenName => "Harry",
      :sn => "Potter",
      :mail => "harry@example.com",
      :uid => "harry.potter",
      :role_name => "Class 4",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "student",
      :puavoPreferredDesktop => "foo",
      :puavoEduPersonPersonnelNumber => "123",
      :jpegPhoto => test_image,
      :preferredLanguage => "en",
      :puavoLocale => "en_US.UTF-8",
      :telephoneNumber => "123456",
      :puavoAcceptedTerms => "TRUE",
      :puavoLocked => "FALSE"
    )
    student.save!
    config.dn = student.dn
  end

  env.define :teacher2 do |config|
    teacher2 = User.create(
      :puavoSchool => env.school.dn,
      :givenName => "Gilderoy",
      :sn => "Lockhart",
      :uid => "gilderoy.lockhart",
      :role_name => "Staff",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "teacher"
    )
    config.dn = teacher2.dn
  end

  env.define :student2 do |config|
    student2 = User.create(
      :puavoSchool => env.school.dn,
      :givenName => "Ron",
      :mail => "ron@example.com",
      :sn => "Wesley",
      :uid => "ron.wesley",
      :role_name => "Class 4",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "student"
    )
    config.dn = student2.dn
  end



  env.define :other_school do |config|
    @other_school = School.create(
      :cn => "slytherin",
      :displayName => "Slytherin"
    )
    config.dn = @other_school.dn

    Role.create(
      :displayName => "Class 4",
      :puavoSchool => @other_school.dn
    )
  end

  env.define :other_school_student do |config|
    other_school_student = User.create(
      :puavoSchool => env.other_school.dn,
      :givenName => "Draco",
      :sn => "Malfoy",
      :mail => "malfoy@example.com",
      :uid => "draco.malfoy",
      :role_name => "Class 4",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "student"
    )
    config.dn = other_school_student.dn
  end

  env.define :id_pool do |config|
    config.dn = "cn=IdPool,o=puavo"
  end

  env.define :domain_users do |config|
    config.dn = "cn=Domain Users,ou=Groups," + env.organisation.dn
  end

  env.define :domain_admins do |config|
    config.dn = "cn=Domain Admins,ou=Groups," + env.organisation.dn
  end

  env.define :printer do |config|
    printer = Printer.create(
      :printerDescription => "foo"
    )
    config.dn = printer.dn
  end

  env.define :bootserver do |config|
    bootserver = Server.create(
      :puavoHostname => "boot01",
      :puavoDeviceType => "bootserver",
      :macAddress => "27:c0:59:3c:bc:b4",
      :description => "test",
      :puavoSchool => env.school.dn )
    config.dn = bootserver.dn
  end

  env.define :bootserver2 do |config|
    bootserver = Server.create(
      :puavoHostname => "boot10",
      :puavoDeviceType => "bootserver",
      :macAddress => "27:c0:59:3c:bc:b5",
      :description => "test" )
    config.dn = bootserver.dn
  end

  env.define :laptop do |config|
    laptop = Device.new
    laptop.classes = ["top", "device", "puppetClient", "puavoNetbootDevice", "simpleSecurityObject"]
    laptop.puavoSchool = env.school.dn
    laptop.puavoHostname = "ldaptop-01"
    laptop.puavoDeviceType = "laptop"
    laptop.macAddress = "27:c0:59:3c:bc:b6"
    laptop.description = "test laptop"
    laptop.userPassword = config.default_password
    laptop.save
    config.dn = laptop.dn
    config.password = config.default_password
  end

end
