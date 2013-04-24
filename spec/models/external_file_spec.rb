require 'spec_helper'

test_organisation = Puavo::Organisation.find('example')
default_ldap_configuration = ActiveLdap::Base.ensure_configuration
# Setting up ldap configuration
LdapBase.ldap_setup_connection( test_organisation.ldap_host,
                                test_organisation.ldap_base,
                                default_ldap_configuration["bind_dn"],
                                default_ldap_configuration["password"] )

@owner_dn = User.find(:first, :attribute => "uid", :value => test_organisation.owner).dn.to_s
@owner_password = test_organisation.owner_pw

LdapBase.ldap_setup_connection( test_organisation.ldap_host,
                                test_organisation.ldap_base,
                                @owner_dn,
                                @owner_password )

describe ExternalFile do
  it "can save " do

    f = ExternalFile.new
    f.puavoData = "lol"
    f.puavoDataHash = "sdf"
    f.cn = "filename"

    f.save!

    ExternalFile.all.size.should == 1
  end
end
