class Course < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Courses",
                :classes => ['puavoCourse'] )

  before_validation :set_puavoId

  def set_puavoId
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end

  def id
    self.puavoId.to_s unless puavoId.nil?
  end

  def to_json(*args)
    { "name" => self.puavoCourseName,
      "course_id" => self.puavoCourseId,
      "description" => self.puavoCourseDescription,
      "puavo_id" => self.puavoId }.to_json
  end
end
