class User < LdapBase
  include Puavo::Authentication if defined?(Puavo::Authentication)

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

  def self.authenticate(login, password)
    result = super(login, password)
    if result == false && login.match(/#{Server.base.to_s}$/)
      server = Server.new(login)
      if server.bind(password)
        logger.info("Server login successful!")
        logger.info("Server dn: #{login}")
        host = LdapBase.configuration[:host]
        base = LdapBase.base.to_s
        server.remove_connection
        LdapBase.ldap_setup_connection(host, base, login, password)
        result = server
      else
        logger.info("Server login failed!")
        logger.info("Server dn: #{login}")
        result = false
      end
    end
    return result
  end
end

