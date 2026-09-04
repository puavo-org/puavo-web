
def define_basic(env)

  env.define :organisation do |config|
    config.dn = LdapOrganisation.first.dn
  end

  env.define :school do |config|
    school = School.create(
      :cn          => 'gryffindor',
      :displayName => 'Gryffindor',
    )
    config.dn = school.dn
    config.model_object = school
  end

  env.define :group do |config|
    group = Group.create(
      :displayName => 'Test Group',
      :cn          => 'testgroup',
      :puavoSchool => env.school.dn)
    config.dn = group.dn
  end

  # teacher with student password change permissions
  env.define :teacher do |config|
    test_image = Magick::Image.read("features/support/test.jpg").first.to_blob
    teacher = User.create(
      :givenName                   => 'Severus',
      :jpegPhoto                   => test_image,
      :mail                        => 'severus@example.com',
      :new_password                => config.default_password,
      :new_password_confirmation   => config.default_password,
      :preferredLanguage           => 'en',
      :puavoAcceptedTerms          => 'TRUE',
      :puavoEduPersonAffiliation   => 'teacher',
      :puavoEduPersonPrimarySchool => env.school.dn,
      :puavoLocale                 => 'en_US.UTF-8',
      :puavoSchool                 => env.school.dn,
      :puavoTeacherPermissions     => [ 'set_student_password' ],
      :sn                          => 'Snape',
      :telephoneNumber             => '234567',
      :uid                         => 'severus.snape')
    config.dn = teacher.dn
  end

  env.define :admin do |config|
    test_image = Magick::Image.read("features/support/test.jpg").first.to_blob
    admin = User.create(
      :givenName                   => 'Minerva',
      :jpegPhoto                   => test_image,
      :mail                        => 'minerva@example.com',
      :new_password                => config.default_password,
      :new_password_confirmation   => config.default_password,
      :preferredLanguage           => 'en',
      :puavoAcceptedTerms          => 'TRUE',
      :puavoEduPersonAffiliation   => 'admin',
      :puavoEduPersonPrimarySchool => env.school.dn,
      :puavoLocale                 => 'en_US.UTF-8',
      :puavoSchool                 => env.school.dn,
      :sn                          => 'McGonagall',
      :telephoneNumber             => '345678',
      :uid                         => 'minerva.mcgonagall')
    env.school.model_object.add_admin(admin)
    config.dn = admin.dn
  end

  env.define :owner do |config|
    config.dn = User.find(:first, :attribute => 'uid', :value => 'cucumber') \
                    .dn.to_s
    config.password = 'cucumber'
  end

  env.define :puavo do |config|
    config.dn = 'uid=puavo,o=puavo'
    config.password = 'password'
  end

  env.define :pwmgmt do |config|
    config.dn = 'uid=pw-mgmt,o=puavo'
    config.password = 'password'
  end

  env.define :slave do |config|
    config.dn = 'uid=slave,o=puavo'
    config.password = 'password'
  end

  env.define :student do |config|
    test_image = Magick::Image.read("features/support/test.jpg").first.to_blob
    student = User.new(
      :givenName                     => "Harry",
      :jpegPhoto                     => test_image,
      :mail                          => "harry@example.com",
      :new_password                  => config.default_password,
      :new_password_confirmation     => config.default_password,
      :preferredLanguage             => "en",
      :puavoAcceptedTerms            => "TRUE",
      :puavoEduPersonAffiliation     => "student",
      :puavoEduPersonPersonnelNumber => "123",
      :puavoEduPersonPrimarySchool   => env.school.dn,
      :puavoLocale                   => "en_US.UTF-8",
      :puavoLocked                   => "FALSE",
      :puavoSchool                   => env.school.dn,
      :sn                            => "Potter",
      :telephoneNumber               => "123456",
      :uid                           => "harry.potter",
    )
    student.save!
    config.dn = student.dn
  end

  env.define :staff do |config|
    staff = User.new(
      :givenName                   => 'Rubeus',
      :new_password                => config.default_password,
      :new_password_confirmation   => config.default_password,
      :puavoEduPersonAffiliation   => 'staff',
      :puavoEduPersonPrimarySchool => env.school.dn,
      :puavoSchool                 => env.school.dn,
      :sn                          => 'Hagrid',
      :uid                         => 'rubeus.hagrid')
    staff.save!
    config.dn = staff.dn
  end

  # teacher without student password change permissions
  env.define :teacher2 do |config|
    teacher2 = User.create(
      :givenName                   => "Gilderoy",
      :new_password                => config.default_password,
      :new_password_confirmation   => config.default_password,
      :puavoEduPersonAffiliation   => "teacher",
      :puavoEduPersonPrimarySchool => env.school.dn,
      :puavoSchool                 => env.school.dn,
      :sn                          => "Lockhart",
      :uid                         => "gilderoy.lockhart")
    config.dn = teacher2.dn
  end

  env.define :student2 do |config|
    student2 = User.create(
      :givenName                   => "Ron",
      :mail                        => "ron@example.com",
      :new_password                => config.default_password,
      :new_password_confirmation   => config.default_password,
      :puavoEduPersonAffiliation   => "student",
      :puavoEduPersonPrimarySchool => env.school.dn,
      :puavoSchool                 => env.school.dn,
      :sn                          => "Weasley",
      :uid                         => "ron.weasley")
    config.dn = student2.dn
  end

  env.define :other_school do |config|
    other_school = School.create(
      :cn          => 'beauxbatons',
      :displayName => 'Beauxbatons')
    config.dn = other_school.dn
  end

  env.define :other_school_admin do |config|
    other_school_admin = User.create(
      :givenName                   => 'Nicolas',
      :mail                        => 'nicolas.flamel@example.com',
      :new_password                => config.default_password,
      :new_password_confirmation   => config.default_password,
      :puavoEduPersonAffiliation   => 'admin',
      :puavoEduPersonPrimarySchool => env.other_school.dn,
      :puavoSchool                 => env.other_school.dn,
      :sn                          => 'Flamel',
      :uid                         => 'nicolas.flamel')
    config.dn = other_school_admin.dn
  end

  env.define :other_school_student do |config|
    other_school_student = User.create(
      :givenName                   => 'Fleur',
      :mail                        => 'fleur.delacour@example.com',
      :new_password                => config.default_password,
      :new_password_confirmation   => config.default_password,
      :puavoEduPersonAffiliation   => 'student',
      :puavoSchool                 => env.other_school.dn,
      :puavoEduPersonPrimarySchool => env.other_school.dn,
      :sn                          => 'Delacour',
      :uid                         => 'fleur.delacour')
    config.dn = other_school_student.dn
  end

  env.define :other_school_teacher do |config|
    other_school_teacher = User.create(
      :givenName                   => 'Madame',
      :mail                        => 'madame.maxine@example.com',
      :new_password                => config.default_password,
      :new_password_confirmation   => config.default_password,
      :puavoEduPersonAffiliation   => 'teacher',
      :puavoSchool                 => env.other_school.dn,
      :puavoEduPersonPrimarySchool => env.other_school.dn,
      :sn                          => 'Maxine',
      :uid                         => 'madame.maxine')
    config.dn = other_school_teacher.dn
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
    printer = Printer.create(:printerDescription => 'foo')
    config.dn = printer.dn
  end

  env.define :systemaccount_with_getent do |config|
    service = LdapService.new
    service.groups = SystemGroup.all.map { |g| g.id }
    service.puavoLdapServiceAccessAll = true
    service.uid = 'testservice'
    service.userPassword = 'secretsecretsecretsecretsecret'
    service.save!
    config.dn = service.dn
    config.password = 'secretsecretsecretsecretsecret'
  end

  env.define :systemaccount_for_beauxbatons do |config|
    service = LdapService.new
    service.groups = SystemGroup.all.map { |g| g.id }
    service.puavoLdapServiceAccessAll = false
    service.puavoSchool = env.other_school.dn
    service.uid = 'testservice2'
    service.userPassword = 'testservicesecret2'
    service.save!
    config.dn = service.dn
    config.password = 'testservicesecret2'
  end

  env.define :bootserver do |config|
    bootserver = Server.new
    bootserver.classes = %w(top device puppetClient puavoServer simpleSecurityObject)
    bootserver.description = 'test'
    bootserver.macAddress = '27:c0:59:3c:bc:b4'
    bootserver.puavoDeviceType = 'bootserver'
    bootserver.puavoHostname = 'boot01'
    bootserver.puavoSchool = env.school.dn
    bootserver.userPassword = config.default_password
    bootserver.save!
    config.dn = bootserver.dn
  end

  env.define :bootserver2 do |config|
    bootserver2 = Server.create(
      :description     => 'test',
      :macAddress      => '27:c0:59:3c:bc:b5',
      :puavoDeviceType => 'bootserver',
      :puavoHostname   => 'boot10')
    config.dn = bootserver2.dn
  end

  env.define :laptop do |config|
    laptop = Device.new
    laptop.classes = %w(top device puppetClient puavoLocalbootDevice simpleSecurityObject)
    laptop.description = "test laptop"
    laptop.macAddress = "27:c0:59:3c:bc:b6"
    laptop.puavoDeviceType = "laptop"
    laptop.puavoHostname = "laptop-01"
    laptop.puavoSchool = env.school.dn
    laptop.userPassword = config.default_password
    laptop.save!
    config.dn = laptop.dn
    config.password = config.default_password
  end

  env.define :other_school_laptop do |config|
    os_laptop = Device.new
    os_laptop.classes = %w(top device puppetClient puavoLocalbootDevice simpleSecurityObject)
    os_laptop.description = "beauxbatons laptop"
    os_laptop.macAddress = "27:c0:19:3c:bc:ff"
    os_laptop.puavoDeviceType = "laptop"
    os_laptop.puavoHostname = "laptop-02"
    os_laptop.puavoSchool = env.other_school.dn
    os_laptop.userPassword = config.default_password
    os_laptop.save!
    config.dn = os_laptop.dn
    config.password = config.default_password
  end

  env.define :fatclient do |config|
    fatclient = Device.new
    fatclient.classes = %w(top device puppetClient puavoNetbootDevice)
    fatclient.description = 'test fatclient'
    fatclient.macAddress = '08:00:27:82:70:df'
    fatclient.puavoDeviceType = 'fatclient'
    fatclient.puavoHostname = 'fatclient-01'
    fatclient.puavoSchool = env.school.dn
    fatclient.save!
    config.dn = fatclient.dn
  end
end
