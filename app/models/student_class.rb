class StudentClass < BaseGroup
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Classes,ou=Groups",
                :classes => ['top', 'puavoClass','sambaGroupMapping'] )

  belongs_to( :student_year_class, :class_name => "StudentYearClasss",
              :foreign_key => 'puavoYearClass',
              :primary_key => 'dn' )
end
