# Test helpers for Puavo development
module Puavo
module Test
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
    ExternalFile.all.each { |e| e.destroy }
    OauthClient.all.each { |c| c.destroy }

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
    ldap_organisation.puavoDeviceImage = nil
    ldap_organisation.puavoAllowGuest = nil
    ldap_organisation.save!

  end
end
end
