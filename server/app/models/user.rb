class User < LdapBase
  include Puavo::Authentication if defined?(Puavo::Authentication)

  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=People",
                :classes => ['top', 'posixAccount', 'inetOrgPerson', 'puavoEduPerson','sambaSamAccount','eduPerson'] )

  def managed_schools
    { 'label' => 'School',
      'default' => School.first.puavoId,
      'title' => 'School selection',
      'question' => 'Select school: ',
      'list' => School.find(:all,
                            :attribute => 'puavoSchoolAdmin',
                            :value => self.dn ) }
  end
end

