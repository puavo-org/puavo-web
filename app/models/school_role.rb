class SchoolRole < BaseGroup
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=SchoolRoles,ou=Groups",
                :classes => ['top',  'puavoSchoolRole', 'posixGroup', 'sambaGroupMapping'] )
  
end
