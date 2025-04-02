require 'digest'
require 'base64'
require 'timecop'
require_relative '../../generic_test_helpers'

Before do |scenario|
  @owner_dn, @owner_password = Puavo::Test.setup_test_connection
  Puavo::Test.clean_up_ldap
end

Given(/^I am logged in as "([^\"]*)" organisation owner$/) do |organisation_name|
  organisation = Puavo::Organisation.find(organisation_name)

  visit login_path
  fill_in("Username", :with => organisation.owner)
  fill_in("Password", :with => organisation.owner_pw)
  click_button("Login")
  page.should have_content("LDAP services")
end

Given(/^an "([^\"]*)" organisation where teachers have permission to change student passwords by default$/) do |organisation_name|
  set_organisation(organisation_name)
  organisation = LdapOrganisation.current
  organisation.puavoDefaultTeacherPermissions = %w(set_student_password)
  organisation.save!
  system('curl', '--silent', '--noproxy', 'localhost', '-d', 'foo=bar',
                 'http://localhost:9292/v3/refresh_organisations',
         :out => File::NULL) \
    or raise "could not trigger organisations refresh to puavo-rest"
end

Given(/^a new ([^\"]*) with names (.*) on the "([^\"]*)" organisation$/) \
do |names_of_the_models, values, organisation|
  set_organisation(organisation)
  models = names_of_the_models.split(' and ')
  values = values.split(', ').map { |value| value.tr('"', '') }
  models_value = Hash.new
  index = 0
  models.each do |model|
    models_value[model] = values[index]
    index += 1
  end

  if models_value.has_key?('school')
    @school = School.new( :displayName =>  models_value['school'],
                          :cn => models_value['school'].downcase.gsub(/[^a-z0-9]/, "")
                          )
    @school.save!
  end
  if models_value.has_key?('group')
    @group = Group.create( :displayName => models_value['group'],
                           :cn => models_value['group'].downcase.gsub(/[^a-z0-9]/, ""),
                           :puavoEduGroupType => 'teaching group')
    @school.groups << @group
  end
end

Given(/^"([^\"]*)" is a school admin on the "([^\"]*)" school$/) do |uid, school_name|
  set_ldap_admin_connection
  school = School.find(:first, :attribute => "displayName", :value => school_name)
  user = User.find(:first, :attribute => "uid", :value => uid)
  user.puavoAdminOfSchool = Array(user.puavoAdminOfSchool).push school.dn
  user.save
  school.puavoSchoolAdmin = Array(school.puavoSchoolAdmin) + Array(user.dn)
  school.save
end

When(/^I check field by id "([^\"]*)"$/) do |field_id|
  check( field_with_id(field_id) )
end

Given(/^I am on ([^\"]+) with "([^\"]*)"$/) do |page_name, value|
  set_ldap_admin_connection
  case page_name
  when /user page$/
    user = User.find(:first, :attribute => "uid", :value => value)
    case page_name
    when /edit/
      visit edit_user_path(@school, user)
    when /show/
      visit user_path(@school, user)
    end
  when /the new other device page/, /the devices list/
    @school = School.find( :first, :attribute => "displayName", :value => value )
    visit path_to(page_name)
  when /device page$/
    device = Device.find_by_hostname(value)
    case page_name
    when /show/
      visit device_path(@school, device)
    end
  when /the change device school page/
    device = Device.find_by_hostname(value)
    visit select_school_device_path(device.puavoSchool, device)
  when /the change group school page/
    group = Group.find(:first, attribute: 'displayName', value: value)
    visit select_new_school_path(group.puavoSchool, group)
  when /school page$/
    @school = School.find( :first, :attribute => "displayName", :value => value )
    visit school_path(@school)
    #visit path_to(page_name) # FIXME
  when /the school edit page/
    @school = School.find( :first, attribute: 'displayName', value: value )
    visit edit_school_path(@school)
  when /the school WLAN page/
    @school = School.find( :first, attribute: 'displayName', value: value )
    visit wlan_school_path(@school)
  when /group page/
    group = Group.find( :first, :attribute => "displayName", :value => value )
    case page_name
    when /the group page/
      visit group_path(@school, group)
    when /the edit group page/
      visit edit_group_path(@school, group)
    end
  when /change schools page/
    @user = User.find(:first, :attribute => "uid", :value => value)
    visit change_schools_path(@user.primary_school, @user)
  when /the edit admin permissions/
    @user = User.find(:first, :attribute => "uid", :value => value)
    visit edit_admin_permissions_path(@user.primary_school, @user)
  else
    raise "Unknow page: #{page_name}"
  end
end

When(/^I find device by hostname "([^\"]*)"$/) do |hostname|
  device = Device.find(:first, :attribute => "puavoHostname", :value => hostname )
  # Generate new password for laptop
  device.userPassword = nil
  device.save
  page.driver.browser.basic_authorize(device.dn.to_s,  device.ldap_password)
  visit "/devices/api/v2/devices/by_hostname/#{ hostname }.json"
end

When(/^I get on ([^\"]+) with "([^\"]*)"$/) do |page_name, value|
  page.driver.browser.basic_authorize('cucumber', 'cucumber')
  case page_name
  when /user JSON page$/
    @json_user = User.find(:first, :attribute => "uid", :value => value)
    case page_name
    when /show/
      visit "/users/users/" + @json_user.id.to_s + ".json"
    end
  when /users JSON page$/
    # FIXME:
    #school = School.find(:first, :attribute => "displayName", :value => value)
    visit users_path(@school, :format => :json)
  when /members group JSON page$/
    json_group = Group.find(:first, :attribute => "displayName", :value => value)
    visit "/users/#{@school.id}/groups/" + json_group.id.to_s + "/members.json"
  end
end

Then(/^I should see JSON '([^\']*)'$/) do |json_string|
  response_data = ActiveSupport::JSON.decode(page.body)
  compare_data = ActiveSupport::JSON.decode(json_string)

  if compare_data.class == Hash
    response_data = [response_data]
    compare_data = [compare_data]
  end

  keys = compare_data.first.keys
  response_data.each do |r|
    r.keys.each do |k|
      unless keys.include?(k)
        r.delete(k)
      end
    end
  end

  if response_data.first
    keys = response_data.first.keys
  else
    keys = []
  end

  response_data = response_data.sort { |a,b| stringify(a, keys) <=> stringify(b, keys) }
  compare_data = compare_data.sort { |a,b| stringify(a, keys) <=> stringify(b, keys) }
  response_data.length.should == compare_data.length
  response_data.each_index do |i|
    response_data[i].should == compare_data[i]
  end
end

private

def stringify(hash_data, keys)
  keys.map{ |k| "#{k} => #{hash_data[k]}" }.join
end

def sort_tags(tags)
  return tags.split(TagList.delimiter).sort.join(TagList.delimiter)
end

When(/^I fill in textarea "([^\"]*)" with "([^\"]*)"$/) do |field, value|
  fill_in(field, :with => value)
end

Then(/^I should see the following:$/) do |values|
  values.rows.each do |value|
    step %{I should see "#{value.first}"}
  end
end

Then(/^named the "([^\"]*)" field should contain "([^\"]*)"$/) do |field, value|
  field_named(field).value.should =~ /#{value}/
end

Then(/^id the "([^\"]*)" field should contain "([^\"]*)"$/) do |field_id, value|
  field_with_id(field_id).value.should =~ /#{value}/
end

Then(/^id the "([^\"]*)" field should not contain "([^\"]*)"$/) do |field_id, value|
  field_with_id(field_id).value.should_not =~ /#{value}/
end

Then(/^"([^"]*)" should be selected for "([^"]*)"$/) do |value, field_id|
  field_with_id(field_id).native.search(".//option[@selected = 'selected']").inner_html.should =~ /#{value}/
end

Then(/^I can select "([^\"]*)" from the "([^\"]*)"$/) do |value, field_id|
  field_with_id(field_id).native.inner_html.should =~ /#{value}/
end

Then(/^the "([^\"]*)" select box should contain "([^\"]*)"$/) do |field, value|
  find_field(field).native.inner_html.should =~ /#{value}/
end

Then(/^I can not select "([^\"]*)" from the "([^\"]*)"$/) do |value, field|
  find_field(field).native.inner_html.should_not =~ /#{value}/
end
Then(/^the "([^\"]*)" ([^ ]+) not include incorrect ([^ ]+) values$/) do |object_name, class_name, method|
  object = eval(class_name.capitalize).send("find", :first, :attribute => 'displayName', :value => object_name)
  Array(object.send(method)).each do |dn|
    lambda{ User.find(dn) }.should_not raise_error
  end
end

When(/^I follow "([^\"]*)" on the "([^\"]*)" ([^ ]+)$/) do |link_name, name, model|
  set_ldap_admin_connection
  link_id = link_name.downcase + "_#{model}_" +
    eval(model.capitalize).send("find", :first,
                                :attribute => "displayName",
                                :value => name ).id.to_s
  steps %Q{
    When I follow "#{link_id}"
  }
end


Then(/^the ([^ ]*) should include "([^\"]*)" on the "([^\"]*)" (.*)$/) do |method, uid, object_name, model|
  memberUid_include?(model, object_name, method, uid).should == true
end

Then(/^the ([^ ]*) should not include "([^\"]*)" on the "([^\"]*)" (.*)$/) do |method, uid, object_name, model|
  memberUid_include?(model, object_name, method, uid).should == false
end

def read_pdf
  tmp_pdf = Tempfile.new('tmp_pdf')
  tmp_pdf.binmode # Switch to binary mode to avoid encoding errors
  tmp_pdf << page.body
  tmp_pdf.close
  tmp_txt = Tempfile.new('tmp_txt')
  tmp_txt.close
  `pdftotext -q #{tmp_pdf.path} #{tmp_txt.path}`
  @pdf_text = File.read tmp_txt.path
end

When(/^I follow the PDF link "([^\"]*)"$/) do |link_name|
  click_link(link_name)
  read_pdf
end

When(/^I press the PDF button "([^\"]*)"$/) do |button_name|
  click_button(button_name)
  read_pdf
end

Then(/^I should see "([^\"]*)" on the PDF$/) do |text|
  @pdf_text.should have_content(text)
end

When(/^I cut nextPuavoId value by one$/) do
  IdPool.set_id!("puavoNextId", IdPool.last_id("puavoNextId").to_i - 1)
end

Then(/^I should see "([^\"]*)" titled "([^\"]*)"$/) do |text, title|
  page.has_xpath?("//div[text()='#{text}'][@title='#{ title }']")
end

def memberUid_include?(model, object_name, method, uid)
  set_ldap_admin_connection
  # manipulate string to Class name, e.g. "school" -> "School", "samba group" -> "SambaGroup"
  model = model.split(" ").map { |m| m.capitalize }.join("")
  object = Class.class_eval(model).find( :first, :attribute => "displayName", :value => object_name )

  case method
  when "member"
    user = User.find( :first, :attribute => "uid", :value => uid )
    return Array(object.send(method)).include?(user.dn)
  when "memberUid"
    return Array(object.send(method)).include?(uid)
  end
end

def set_ldap_admin_connection(organisation_key=nil)
  return if @admin_connection_organisation == organisation_key \
              && LdapBase.connected?

  @admin_connection_organisation = organisation_key if organisation_key

  test_organisation = Puavo::Organisation.find(@admin_connection_organisation)
  owner_dn, owner_pw \
    = Puavo::Test.setup_test_connection(@admin_connection_organisation)

  LdapBase.ldap_setup_connection(test_organisation.ldap_host,
                                 test_organisation.ldap_base,
                                 owner_dn,
                                 owner_pw)
end

def set_organisation(organisation_key)
  organisation = Puavo::Organisation.find(organisation_key)
  raise "could not find organisation for '#{ organisation_key }'" \
    unless organisation
  host = organisation.host
  raise "could not find organisation host for '#{ organisation_key }'" \
    unless host

  # see https://makandracards.com/makandra/12725-how-to-change-the-hostname-in-cucumber-features
  #     https://stackoverflow.com/questions/6536503/capybara-with-subdomains-default-host
  # NOTE this should be better with cucumber, but gives an ArgumentError:
  # page.config.stub app_host: "http://#{host}"
  Capybara.app_host = "http://#{host}"

  set_ldap_admin_connection(organisation_key)
end

Given(/^I wait ([0-9]+) (hour|day|month|year)s?$/) do |digit, type|
  Timecop.travel Time.now + digit.to_i.send(type)
end


Given /^I am on the edit page of "(.*?)" device$/ do |hostname|
  set_ldap_admin_connection
  device = Device.find_by_hostname(hostname)
  visit edit_device_path(@school, device)
end
