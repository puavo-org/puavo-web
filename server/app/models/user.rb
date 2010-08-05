class User < LdapBase
  include Puavo::Authentication if defined?(Puavo::Authentication)

  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=People",
                :classes => ['top', 'posixAccount', 'inetOrgPerson', 'puavoEduPerson','sambaSamAccount','eduPerson'] )

  def managed_schools
    School.all
  end
end

