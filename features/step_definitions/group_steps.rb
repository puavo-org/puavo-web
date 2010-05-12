Given /^the following groups:$/ do |groups|
  groups.hashes.each do |new_group| 
    new_group[:puavoSchool] = @school.dn
    group = Group.create!(new_group)
  end
end

Then /^I should see "([^\"]*)" on the "([^\"]*)"$/ do |role_name, selector|
  steps %Q{
    Then I should see "#{role_name}" within "##{selector.to_s.downcase.gsub(" ", "_")}"
  }
end

Then /^I should not see "([^\"]*)" on the "([^\"]*)"$/ do |role_name, selector|
  steps %Q{
    Then I should not see "#{role_name}" within "##{selector.to_s.downcase.gsub(" ", "_")}"
  }
end

Then /^the memberUid should include "([^\"]*)" on the "([^\"]*)" group$/ do |uid, group_name|
  group_memberUid_include?(group_name, uid).should == true
end

Then /^the memberUid should not include "([^\"]*)" on the "([^\"]*)" group$/ do |uid, group_name|
  group_memberUid_include?(group_name, uid).should == false
end
def group_memberUid_include?(group_name, uid)
  group = Group.find( :first, :attribute => "displayName", :value => group_name )
  return Array(group.memberUid).include?(uid)
end
