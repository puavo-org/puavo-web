Given(/^I am logged in as "([^\"]*)" with password "([^\"]*)"$/) do |login, password|
  visit login_path
  fill_in("Username", :with => login)
  fill_in("Password", :with => password)
  click_button("Login")
end

Given(/^I am logged out$/) do
  visit logout_path
end

Given(/^the following users:$/) do |users|
  set_ldap_admin_connection
  users.hashes.each do |u|
    groups = nil
    school = nil
    if u['school'] then
      school = School.find(:first, :attribute => "displayName", :value => u['school'])
      u.delete('school')
    else
      school = @school
    end

    raise "No school found from user definition #{ u.inspect }" unless school

    if u['groups'] then
      groups = u['groups'].split.map do |g_cn|
                 Group.find(:first, :attribute => 'cn', :value => g_cn)
               end
      u.delete('groups')
    end

    user = User.new(u)
    user.puavoSchool = school.dn
    user.puavoEduPersonPrimarySchool = school.dn

    is_school_admin = (u['school_admin'] && u['school_admin'] == 'true')

    if is_school_admin then
      user.puavoAdminOfSchool = user.puavoSchool
      SambaGroup.add_uid_to_memberUid('Domain Admins', user.uid)
    end

    user.set_password(u['password'])
    user.save!

    if is_school_admin then
      school.puavoSchoolAdmin = Array(school.puavoSchoolAdmin).push(user.dn)
      school.save!
    end

    user.groups = groups if groups  # XXX must be after .save! due to weird APIs
  end
end

When(/^I set in "([^\"]*)" with "([^\"]*)" to "([^\"]*)"$/) do |method, text, username|
  user = User.find_by_username(username)
  user.send(method.to_s + "=", text)
end

Then(/^I should get "([^\"]*)" with "([^\"]*)" from "([^\"]*)"$/) do |text, method, username|
  User.find_by_username(username).send(method).should == text
end

Then(/^I should see the following users:$/) do |users_table|
  rows = find('table').all('tr')
  table = rows.map { |r| r.all('th,td').map { |c| c.text.strip } }
  users_table.diff!(table)
end

When(/^I fill test data into user forms$/) do
  steps %Q{
    And I fill in "Given names" with "Ben Lars"
    And I fill in "Nickname" with "Ben"
    And I fill in "Lastname" with "Mabey"
    And I fill in "Login" with "ben"
    And I fill in "School start year" with "2005"
    And I check "Student"
    And I check "Employee"
    And I check "Library walk in"
    And I check "Guardian"
    And I check "Locked"
    And I fill in "Email(s)" with "ben@some.com"
    And I fill in "Phone number(s)" with "+3581234567890"
    And I fill in "tags" with "english programming"
    And I fill in "Password" with "secret"
    And I fill in "Password confirmation" with "secret"
  }
end

When(/^I should see same test data on the user page$/) do
  steps %Q{
    And I should see "Ben Lars"
    And I should see "Ben"
    And I should see "Mabey"
    And I should see "ben"
    And I should see "2005"
    And I should see "Student"
    And I should see "Employee"
    And I should see "Library walk-in"
    And I should see "Guardian"
    And I should see "Locked"
    And I should see "ben@some.com"
    And I should see "+3581234567890"
    And I should see "english"
    And I should see "programming"
}
end

Then(/^I should see the following special ldap attributes on the "([^\"]*)" object with "([^\"]*)":$/) do
  |model, key, table|
  set_ldap_admin_connection
  object = get_object_by_model_and_key(model, key)
  table.rows_hash.each do |attribute, regexp|
    regexp = eval(regexp)
    object.send(attribute).to_s.should =~ /#{regexp}/
  end
end

Then(/^I should see the following JSON on the "([^\"]*)" object with "([^\"]*)" on attribute "([^\"]*)":$/) do
  |model, key, attribute, json_string|
  set_ldap_admin_connection
  object = get_object_by_model_and_key(model, key)

  object.send(attribute).should == JSON.parse(json_string)
end

Given(/^I am set the "([^\"]*)" role for "([^\"]*)"$/) do |role, uid|
  steps %Q{
    And I am on the edit user page with "#{uid}"
    And I check "#{role}"
    And I press "Update"
}
end

Then(/^I should login with "([^"]*)" and "([^"]*)"$/) do |uid, password|
  set_ldap_admin_connection
  user = User.find(:first, :attribute => "uid", :value => uid)
  lambda{ user.bind(password) }.should_not raise_error
  user.remove_connection
end

Then(/^I should not login with "([^"]*)" and "([^"]*)"$/) do |uid, password|
  set_ldap_admin_connection
  user = User.find(:first, :attribute => "uid", :value => uid)
  lambda{ user.bind(password) }.should raise_error(ActiveLdap::AuthenticationError)
  user.remove_connection
end

Then(/^the ([^ ]*) attribute should contain "([^\"]*)" of "([^\"]*)"$/) do |attribute, school_name, uid|
  set_ldap_admin_connection
  school = School.find(:first, :attribute => "displayName", :value => school_name)
  user = User.find(:first, :attribute => "uid", :value => uid)

  case attribute
  when "puavoSchool"
    user.puavoSchool.to_s.should == school.dn.to_s
  when "gidNumber"
    user.gidNumber.to_s.should == school.gidNumber.to_s
  when "homeDirectory"
    user.homeDirectory.to_s.should == "/home/" + uid
  when "sambaPrimaryGroupSID"
    user.sambaPrimaryGroupSID.to_s.should == "#{SambaDomain.first.sambaSID}-#{school.puavoId}"
  end
end

Then(/^I should see image of "(.*?)"$/) do |uid|
  set_ldap_admin_connection
  user = User.find(:first, :attribute => 'uid', :value => uid)

  page.should have_xpath("//img[@src='/users/#{ user.primary_school.puavoId }/users/#{ user.puavoId }/image']")
end

When(/^I change "(.*?)" user type to "(.*?)"$/) do |uid, user_type|
  set_ldap_admin_connection
  user = User.find(:first, :attribute => "uid", :value => uid)
  user.puavoEduPersonAffiliation = user_type
  user.save!
end

When(/^I add user "(.*?)" to teaching group "(.*?)"$/) do |uid, groupname|
  set_ldap_admin_connection
  user = User.find(:first, :attribute => 'uid', :value => uid)
  group = Group.find(:first, :attribute => 'displayName', :value => groupname)

  user.teaching_group = group.id
  # XXX no user.save! due to weird API
end

# Used when testing password changing timeouts
Then(/^I wait (\d+) seconds$/) do |number|
  sleep(number)
end

private

def get_object_by_model_and_key(model, key)
  case model
    when 'User'
      User.find(:first, :attribute => 'uid', :value => key)
    when 'School'
      School.find(:first, :attribute => 'displayName', :value => key)
    when 'Group'
      Group.find(:first, :attribute => 'displayName', :value => key)
    when 'Organisation'
      LdapOrganisation.first
    else
      raise "Unsupported model type: #{ model }"
  end
end
