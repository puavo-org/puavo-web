env = LDAPTestEnv.new

env.define :new_admin do |config|
  admin = User.create(
    :givenName                 => 'Gilderoy',
    :new_password              => config.default_password,
    :new_password_confirmation => config.default_password,
    :puavoEduPersonAffiliation => 'admin',
    :puavoSchool               => env.school.dn,
    :role_name                 => 'Staff',
    :sn                        => 'Lockhart',
    :uid                       => 'gilderoy.lockhart')
  config.dn = admin.dn
end

school_attributes = [
  :cn,
  :displayName,
  :gidNumber,
  :member,
  :memberUid,
  :objectClass,
  :puavoId,
  :puavoSchoolAdmin,
  :sambaGroupType,
  :sambaSID,
]

env.validate "school" do
  admin.can_read school,   school_attributes
  student.can_read school, school_attributes
  teacher.can_read school, school_attributes

  owner.can_modify school,
                   [ :replace, :displayName, [ "Test school" ] ]
  owner.can_modify school,
                   [ :add, :puavoSchoolAdmin, [ new_admin.dn ] ]
  owner.can_modify school,
                   [ :replace, :puavoPrinterQueue, [printer.dn] ]
  owner.can_modify school,
                   [ :replace, :puavoWirelessPrinterQueue, [ printer.dn ] ]

  {
    :cn                        => 'testname',
    :description               => 'test',
    :displayName               => 'Test name',
    :facsimileTelephoneNumber  => '0123456789',
    :jpegPhoto                 => 'test',
    :l                         => 'test',
    :postalAddress             => 'test',
    :postalCode                => 'test',
    :postOfficeBox             => 'test',
    :preferredLanguage         => 'en',
    :puavoAllowGuest           => false,
    :puavoBillingInfo          => 'test',
    :puavoDeviceImage          => 'test-image',
    :puavoNamePrefix           => 'test prefix',
    :puavoPersonalDevice       => false,
    :puavoPrinterQueue         => printer.dn,
    :puavoSchoolAdmin          => student.dn,
    :puavoSchoolHomePageURL    => 'http://www.test.com',
    :puavoWirelessPrinterQueue => printer.dn,
    :street                    => 'test',
    :st                        => 'test',
    :telephoneNumber           => '0123456789',
  }.each do |attribute, value|
    student.cannot_modify school, [ :replace, attribute, [value] ],
                                  InsufficientAccessRights
  end


  admin.cannot_modify school, [ :replace, :puavoSchoolAdmin, [ student.dn ] ],
                              InsufficientAccessRights
  admin.cannot_modify school, [ :replace, :puavoBillingInfo, [ "test" ] ],
                              InsufficientAccessRights

  {
    :cn                        => 'testname',
    :description               => 'test',
    :displayName               => 'Test name',
    :facsimileTelephoneNumber  => '0123456789',
    :jpegPhoto                 => 'test',
    :l                         => 'test',
    :postalAddress             => 'test',
    :postalCode                => 'test',
    :postOfficeBox             => 'test',
    :preferredLanguage         => 'en',
    :puavoAllowGuest           => false,
    :puavoDeviceImage          => 'test-image',
    :puavoNamePrefix           => 'test prefix',
    :puavoPersonalDevice       => false,
    :puavoPrinterQueue         => printer.dn,
    :puavoSchoolHomePageURL    => 'http://www.test.com',
    :puavoWirelessPrinterQueue => printer.dn,
    :street                    => 'test',
    :st                        => 'test',
    :telephoneNumber           => '0123456789',
  }.each do |attribute, value|
    admin.can_modify school, [ :replace, attribute, [value] ]
  end
end
