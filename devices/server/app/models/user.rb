class User < LdapBase
  include Puavo::AuthenticationMixin

  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=People",
                :classes => ['top', 'posixAccount', 'inetOrgPerson', 'puavoEduPerson','sambaSamAccount','eduPerson'] )

  def managed_schools
    if Array(LdapOrganisation.current.owner).include?(self.dn)
      schools = School.all
    else
      schools = School.find( :all,
                             :attribute => 'puavoSchoolAdmin',
                             :value => self.dn )
    end

    return ( { 'label' => 'School',
               'default' => schools.first.puavoId,
               'title' => 'School selection',
               'question' => 'Select school: ',
               'list' =>  schools } ) unless schools.empty?
  end

  def organisation_owner?
    LdapOrganisation.current.owner.include? self.dn
  end

end

