# Generic test helpers shared with rails and puavo-rest
module Puavo
module Test

  def self.setup_test_connection
    test_organisation = Puavo::Organisation.find('example')
    default_ldap_configuration = ActiveLdap::Base.ensure_configuration

    # Setting up ldap configuration
    LdapBase.ldap_setup_connection(
      test_organisation.ldap_host,
      test_organisation.ldap_base,
      default_ldap_configuration["bind_dn"],
      default_ldap_configuration["password"]
    )

    owner = User.find(:first, :attribute => "uid", :value => test_organisation.owner)
    if owner.nil?
      raise "Cannot find organisation owner for 'example'. Organisation not created?"
    end

    ExternalService.ldap_setup_connection(
      test_organisation.ldap_host,
      "o=puavo",
      "uid=admin,o=puavo",
      "password"
    )

    return owner.dn.to_s, test_organisation.owner_pw
  end

  def self.clean_up_ldap

    # Clean Up LDAP server: destroy all schools, groups and users
    User.all.each do |u|
      unless u.uid == "cucumber"
        u.destroy
      end
    end
    Group.all.each do |g|
      unless g.displayName == "Maintenance"
        g.destroy
      end
    end
    School.all.each do |s|
      unless s.displayName == "Administration"
        s.destroy
      end
    end
    Role.all.each do |p|
      unless p.displayName == "Maintenance"
        p.destroy
      end
    end

    Device.all.each { |d| d.destroy }
    Server.all.each { |d| d.destroy }
    LdapService.all.each { |e| e.destroy }
    ExternalService.all.each { |e| e.destroy }
    ExternalFile.all.each { |e| e.destroy }
    Printer.all.each { |p| p.destroy }

    domain_users = SambaGroup.find('Domain Users')
    domain_users.memberUid = []
    domain_users.save

    domain_users = SambaGroup.find('Domain Admins')
    domain_users.memberUid = []
    domain_users.save

    ldap_organisation = LdapOrganisation.current
    ldap_organisation.preferredLanguage = "fi"
    ldap_organisation.puavoDeviceOnHour = "14"
    ldap_organisation.puavoDeviceOffHour = "15"
    ldap_organisation.puavoDeviceAutoPowerOffMode = "off"
    ldap_organisation.preferredLanguage = "en"
    ldap_organisation.o = "Example Organisation"
    ldap_organisation.puavoDomain = "www.example.net"
    ldap_organisation.puavoDeviceImage = nil
    ldap_organisation.puavoAllowGuest = nil
    ldap_organisation.puavoActiveService = nil
    ldap_organisation.save!

    default_ldap_configuration = ActiveLdap::Base.ensure_configuration
    anotherorg_conf = Puavo::Organisation.find('anotherorg')
    LdapBase.ldap_setup_connection(
      default_ldap_configuration["host"],
      anotherorg_conf.ldap_base,
      "uid=admin,o=puavo",
      "password"
    )

    anotherorg = LdapOrganisation.current
    anotherorg.puavoDomain = "anotherorg.example.net"
    anotherorg.o = "Another Organisation"
    anotherorg.save!

    # restore connection
    setup_test_connection
  end



end
end
