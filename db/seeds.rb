# encoding: UTF-8
require "puavo/etc"

authentication = Puavo::Authentication.new
authentication.configure_ldap_connection({
    :dn => PUAVO_ETC.ldap_dn,
    :password => PUAVO_ETC.ldap_password,
    :organisation_key => PUAVO_ETC.domain.split(".", 2).first
})
authentication.authenticate

ExternalService.ldap_setup_connection(
  PUAVO_ETC.get(:ldap_master),
  "o=Puavo",
  PUAVO_ETC.ldap_dn,
  PUAVO_ETC.ldap_password
)


school = School.create(
  :cn => "gryffindor",
  :displayName => "Gryffindor"
)
school.save!

group = Group.new
group.cn = "group1"
group.displayName = "Group 1"
group.puavoSchool = school.dn
group.save!

role = Role.new
role.displayName = "Some role"
role.puavoSchool = school.dn
role.groups << group
role.save!


[
  {
    :givenName => "Alice",
    :sn  => "Brown",
    :uid => "alice",
    :puavoEduPersonAffiliation => "student",
    :preferredLanguage => "en",
    :mail => "alice@example.com"
  },
  {
    :givenName => "Bob",
    :sn  => "Brown",
    :uid => "bob",
    :puavoEduPersonAffiliation => "student",
    :preferredLanguage => "en",
    :mail => "bob@example.com"
  },
  {
    :givenName => "Matti",
    :sn  => "Meikäläinen",
    :uid => "matti.meikalainen",
    :puavoEduPersonAffiliation => "student",
    :preferredLanguage => "fi",
    :mail => "matti@example.com"
  },
  {
    :givenName => "Opettaja",
    :sn  => "Opettajainen",
    :uid => "opettaja",
    :puavoEduPersonAffiliation => "teacher",
    :preferredLanguage => "fi",
    :mail => "opettaja@example.com"
  },
  {
    :givenName => "Pääkäyttäjä",
    :sn  => "Opettajainen",
    :uid => "schooladmin",
    :puavoEduPersonAffiliation => "admin",
    :preferredLanguage => "fi",
    :mail => "schooladmin@example.com"
  }

].each do |attrs|
  user = User.new(attrs)
  user.set_password "secret"
  user.puavoSchool = school.dn
  user.role_ids = [role.puavoId]
  user.save!
  if user.puavoEduPersonAffiliation == "admin"
    school.add_admin(user)
  end
end


bootserver = Server.new(
  :puavoHostname => "boot1",
  :macAddress => "27:b0:59:3c:ac:a4",
  :puavoDeviceType => "bootserver"
)
bootserver.save!

[
  {
    :puavoHostname => "boot2",
    :macAddress => "00:60:2f:A4:40:8C",
    :puavoDeviceType => "bootserver"
  },
  {
    :puavoHostname => "ltsp1",
    :macAddress => "00:60:2f:2C:C3:ED",
    :puavoDeviceType => "ltspserver"
  },
  {
    :puavoHostname => "ltsp2",
    :macAddress => "00:60:2f:4D:00:4B",
    :puavoDeviceType => "ltspserver"
  },
].each do |attrs|
  server = Server.new
  server.attributes = attrs
  server.save!
end


[
  {
    :printerDescription => "HP",
    :printerLocation => "Eteinen",
    :printerMakeAndModel => "hp",
    :printerType => "1234",
    :printerURI => "socket://baz",
 },
  {
    :printerDescription => "Samsung",
    :printerLocation => "Opettajien huone",
    :printerMakeAndModel => "samsung",
    :printerType => "1234",
    :printerURI => "socket://baz",
 }

].each do |attrs|
  printer = Printer.new attrs
  printer.puavoServer = bootserver.dn
  printer.save!
end

[
  {
    :puavoHostname => "thin1",
    :puavoDeviceType => "thinclient",
    :macAddress => "00:60:2f:D0:77:1D",
  },
  {
    :puavoHostname => "thin2",
    :puavoDeviceType => "thinclient",
    :macAddress => "00:60:2f:32:A3:55",
  },
  {
    :puavoHostname => "fat1",
    :puavoDeviceType => "fatclient",
    :macAddress => "00:60:2f:CB:1F:91",
  },
  {
    :puavoHostname => "fat2",
    :puavoDeviceType => "fatclient",
    :macAddress => "00:60:2f:14:BD:00",
  },
].each do |attrs|
  device = Device.new
  device.classes = ["top", "device", "puppetClient", "puavoNetbootDevice"]
  device.attributes = attrs
  device.puavoSchool = school.dn
  device.save!
end

[
  {
    :puavoHostname => "laptop1",
    :puavoDeviceType => "laptop",
    :macAddress => "00:60:2f:98:63:F8",
  },
  {
    :puavoHostname => "laptop2",
    :puavoDeviceType => "laptop",
    :macAddress => "00:60:2f:42:16:FF",
  }
].each do |attrs|
  device = Device.new
  device.classes = ["top", "device", "puppetClient", "puavoLocalbootDevice", "simpleSecurityObject"]
  device.attributes = attrs
  device.puavoSchool = school.dn
  device.save!
end


[
  {
    :cn => "Localhost Service",
    :puavoServiceDomain => "localhost",
    :puavoServiceSecret => "secret",
    :description  => "Services for localhost",
    :mail  => "dev@example.com",
    :puavoServiceTrusted => true
  },
  {
    :cn => "Client Service",
    :puavoServiceDomain => "example.com",
    :puavoServiceSecret => "secret",
    :description  => "Client service",
    :mail  => "dev@example.com",
    :puavoServiceTrusted => false
  }
].each do |attrs|
  app = ExternalService.new
  app.classes = ["top", "puavoJWTService"]
  app.attributes = attrs
  app.save!
end



