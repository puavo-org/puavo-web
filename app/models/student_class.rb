class StudentClass < BaseGroup
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Classes,ou=Groups",
                :classes => ['top', 'posixGroup', 'puavoClass','sambaGroupMapping'] )

  belongs_to( :student_year_class, :class_name => "StudentYearClasss",
              :foreign_key => 'puavoYearClass',
              :primary_key => 'dn' )

  
  def validate
    if self.puavoClassId.to_s.length > 7
      errors.add( :puavoClassId, I18n.t("activeldap.errors.messages.too_long",
                                        :attribute => I18n.t("activeldap.attributes.student_class.puavoClassId"),
                                        :count => 7) )
    end
  end
end
