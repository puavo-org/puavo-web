class User < LdapBase
  include Puavo::Authentication if defined?(Puavo::Authentication)

  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=People",
                :classes => ['top', 'posixAccount', 'inetOrgPerson', 'puavoEduPerson','sambaSamAccount','eduPerson'] )

  def managed_schools
    schools = School.find( :all,
                           :attribute => 'puavoSchoolAdmin',
                           :value => self.dn )

    return ( { 'label' => 'School',
               'default' => schools.first.puavoId,
               'title' => 'School selection',
               'question' => 'Select school: ',
               'list' =>  schools } )
  end
end

