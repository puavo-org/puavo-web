Given /^the following student year classes:$/ do |student_year_classes|
  set_ldap_admin_connection
  student_year_classes.hashes.each do |new_class| 
    if new_class["school"]
      school = School.find(:first, :attribute => "displayName", :value => new_class["school"])
      new_class.delete("school")
      new_class[:puavoSchool] = school.dn.to_s
    end
    if new_class["student_class_ids"]
      i = 0
      new_class["student_class_ids"] = new_class["student_class_ids"].split(",[ ]*").inject({}) do |result, char|
        result[i.to_s] = char
        result
      end
    end
    StudentYearClass.create(new_class)
  end
end

When /^I edit the (\d+)(?:st|nd|rd|th) student year class$/ do |pos|
  within("table tr:nth-child(#{pos.to_i+1})") do
    click_link "Edit"
  end
end
